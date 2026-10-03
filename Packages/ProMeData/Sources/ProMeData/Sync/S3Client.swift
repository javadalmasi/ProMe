import CryptoKit
import Foundation

/// S3 bucket addressing configuration. The secret key is never part of
/// this struct — it lives in the keychain.
public struct S3Config: Codable, Equatable, Sendable {
    /// Base endpoint, e.g. "https://s3.amazonaws.com" or any S3-compatible
    /// service (Wasabi, MinIO, ArvanCloud, Backblaze B2 S3 endpoints).
    public var endpoint: String
    public var region: String
    public var bucket: String
    /// Key prefix for all ProMe objects in the bucket.
    public var prefix: String
    public var accessKey: String
    /// Path-style addressing (endpoint/bucket/key); virtual-host style is
    /// used when false. Custom endpoints usually need path style.
    public var usePathStyle: Bool

    public init(
        endpoint: String, region: String, bucket: String, prefix: String,
        accessKey: String, usePathStyle: Bool = true
    ) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.prefix = prefix
        self.accessKey = accessKey
        self.usePathStyle = usePathStyle
    }
}

public struct S3ObjectSummary: Equatable, Sendable {
    public var key: String
    public var size: Int
    public var lastModified: Date?

    public init(key: String, size: Int, lastModified: Date?) {
        self.key = key
        self.size = size
        self.lastModified = lastModified
    }
}

/// A minimal S3 REST client with AWS Signature Version 4 implemented on
/// CryptoKit primitives — no third-party SDK, works on every Apple
/// platform and against any S3-compatible endpoint.
public struct S3Client: Sendable {
    public let config: S3Config
    public let secretKey: String

    public init(config: S3Config, secretKey: String) {
        self.config = config
        self.secretKey = secretKey
    }

    public static let service = "s3"

    // MARK: - Public operations

    public func put(_ key: String, data: Data, contentType: String = "application/octet-stream") async throws {
        var request = try signedRequest(method: "PUT", key: key, payload: data)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        try Self.checkResponse(response)
    }

    public func get(_ key: String) async throws -> Data {
        let request = try signedRequest(method: "GET", key: key, payload: Data())
        let (data, response) = try await session.data(for: request)
        try Self.checkResponse(response)
        return data
    }

    public func delete(_ key: String) async throws {
        let request = try signedRequest(method: "DELETE", key: key, payload: Data())
        let (_, response) = try await session.data(for: request)
        try Self.checkResponse(response)
    }

    public func list(prefix: String) async throws -> [S3ObjectSummary] {
        let query = ["list-type": "2", "prefix": fullKey(prefix), "max-keys": "1000"]
        var request = try signedRequest(method: "GET", key: "", payload: Data(), extraQuery: query)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.checkResponse(response)
        return Self.parseListXML(data)
    }

    /// Parses the ListObjectsV2 response with XMLParser, which is available
    /// on every Apple platform (XMLDocument is macOS-only).
    static func parseListXML(_ data: Data) -> [S3ObjectSummary] {
        let delegate = ListBucketParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.results
    }

    static func checkResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SyncError.network("Invalid response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw SyncError.http(status: http.statusCode)
        }
    }

    var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    // MARK: - Request signing

    /// The full object key including the bucket prefix.
    public func fullKey(_ key: String) -> String {
        let trimmedPrefix = config.prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanKey = key.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPrefix.isEmpty { return cleanKey }
        return trimmedPrefix + "/" + cleanKey
    }

    public func signedRequest(method: String, key: String, payload: Data, extraQuery: [String: String] = [:]) throws -> URLRequest {
        let objectKey = fullKey(key)
        let host = Self.host(from: config.endpoint, bucket: config.bucket, pathStyle: config.usePathStyle)
        let rawPath = Self.rawPath(for: objectKey, bucket: config.bucket, pathStyle: config.usePathStyle)
        let canonicalURI = Self.encodePath(rawPath)

        var components = URLComponents(string: config.endpoint)!
        components.percentEncodedPath = canonicalURI
        components.queryItems = extraQuery.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        guard let url = components.url else { throw SyncError.network("Invalid S3 URL") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = payload.isEmpty ? nil : payload
        request.setValue(host, forHTTPHeaderField: "Host")

        let now = Date()
        let amzDate = Self.amzDateFormat.string(from: now)
        let dateStamp = Self.dateStampFormat.string(from: now)
        let payloadHash = Self.sha256Hex(payload)

        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        let signedHeaderNames = ["host", "x-amz-content-sha256", "x-amz-date"]
        let headerValues = ["host": host, "x-amz-content-sha256": payloadHash, "x-amz-date": amzDate]
        let authorization = Self.authorizationHeader(
            method: method,
            canonicalURI: canonicalURI,
            canonicalQuery: Self.canonicalQuery(from: extraQuery),
            headers: headerValues,
            signedHeaderNames: signedHeaderNames,
            payloadHash: payloadHash,
            accessKey: config.accessKey,
            secretKey: secretKey,
            amzDate: amzDate,
            dateStamp: dateStamp,
            region: config.region,
            service: Self.service
        )
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - SigV4 pieces (pure, unit-testable)

    /// Builds the Authorization header value for a request.
    public static func authorizationHeader(
        method: String, canonicalURI: String, canonicalQuery: String,
        headers: [String: String], signedHeaderNames: [String], payloadHash: String,
        accessKey: String, secretKey: String, amzDate: String, dateStamp: String,
        region: String, service: String
    ) -> String {
        let canonicalHeaders = signedHeaderNames
            .sorted()
            .map { "\($0):\(headers[$0]?.trimmingCharacters(in: .whitespaces) ?? "")\n" }
            .joined()
        let signedHeaders = signedHeaderNames.sorted().joined(separator: ";")

        let canonical = canonicalRequest(
            method: method, canonicalURI: canonicalURI, canonicalQuery: canonicalQuery,
            canonicalHeaders: canonicalHeaders, signedHeaders: signedHeaders, payloadHash: payloadHash
        )
        let toSign = stringToSign(amzDate: amzDate, dateStamp: dateStamp, region: region, service: service, canonicalRequest: canonical)
        let key = signingKey(secret: secretKey, dateStamp: dateStamp, region: region, service: service)
        let signature = Self.hmacHex(key: key, data: Data(toSign.utf8))
        return "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(dateStamp)/\(region)/\(service)/aws4_request, SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    public static func canonicalRequest(
        method: String, canonicalURI: String, canonicalQuery: String,
        canonicalHeaders: String, signedHeaders: String, payloadHash: String
    ) -> String {
        [method, canonicalURI, canonicalQuery, canonicalHeaders, signedHeaders, payloadHash].joined(separator: "\n")
    }

    public static func stringToSign(amzDate: String, dateStamp: String, region: String, service: String, canonicalRequest: String) -> String {
        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        return ["AWS4-HMAC-SHA256", amzDate, scope, sha256Hex(Data(canonicalRequest.utf8))].joined(separator: "\n")
    }

    /// kSigning = HMAC(HMAC(HMAC(HMAC("AWS4" + secret, date), region), service), "aws4_request")
    public static func signingKey(secret: String, dateStamp: String, region: String, service: String) -> Data {
        var key1 = Self.hmac(key: Data(("AWS4" + secret).utf8), data: Data(dateStamp.utf8))
        key1 = Self.hmac(key: key1, data: Data(region.utf8))
        key1 = Self.hmac(key: key1, data: Data(service.utf8))
        return Self.hmac(key: key1, data: Data("aws4_request".utf8))
    }

    public static func signature(
        secret: String, dateStamp: String, region: String, service: String, stringToSign: String
    ) -> String {
        Self.hmacHex(key: signingKey(secret: secret, dateStamp: dateStamp, region: region, service: service), data: Data(stringToSign.utf8))
    }

    /// RFC 3986 percent encoding. `isPath` keeps "/" unescaped.
    public static func urlEncode(_ string: String, isPath: Bool = false) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        if isPath { allowed.insert(charactersIn: "/") }
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    /// Encodes each path segment individually, preserving "/" separators.
    public static func encodePath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { urlEncode(String($0)) }
            .joined(separator: "/")
    }

    public static func canonicalQuery(from queryItems: [String: String]) -> String {
        guard !queryItems.isEmpty else { return "" }
        return queryItems
            .sorted { $0.key == $1.key ? $0.value < $1.value : $0.key < $1.key }
            .map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }
            .joined(separator: "&")
    }

    static func host(from endpoint: String, bucket: String, pathStyle: Bool) -> String {
        var components = URLComponents(string: endpoint)
        components?.path = ""
        var host = components?.url?.absoluteString ?? endpoint
        host = host.hasSuffix("/") ? String(host.dropLast()) : host
        if !pathStyle {
            host = host.replacingOccurrences(of: "://", with: "://\(bucket).")
        }
        return host
    }

    /// The unencoded request path: "/bucket/key" (path style) or "/key".
    static func rawPath(for objectKey: String, bucket: String, pathStyle: Bool) -> String {
        if pathStyle {
            let bucketPart = bucket.isEmpty ? "" : "/" + bucket
            return bucketPart + "/" + objectKey
        }
        return "/" + objectKey
    }

    // MARK: - Hash helpers

    public static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
    }

    public static func hmac(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    public static func hmacHex(key: Data, data: Data) -> String {
        hmac(key: key, data: data).map { String(format: "%02x", $0) }.joined()
    }

    static let amzDateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    static let dateStampFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}

/// Streaming parser for the ListObjectsV2 XML response.
final class ListBucketParser: NSObject, XMLParserDelegate {
    private(set) var results: [S3ObjectSummary] = []

    private var inContents = false
    private var currentField = ""
    private var buffer = ""
    private var key: String?
    private var size = 0
    private var lastModified: Date?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "Contents":
            inContents = true
            key = nil
            size = 0
            lastModified = nil
        case "Key", "Size", "LastModified" where inContents:
            currentField = elementName
            buffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !currentField.isEmpty {
            buffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "Key" where inContents:
            key = buffer
            currentField = ""
        case "Size" where inContents:
            size = Int(buffer.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            currentField = ""
        case "LastModified" where inContents:
            lastModified = Self.dateFormat.date(from: buffer.trimmingCharacters(in: .whitespacesAndNewlines))
            currentField = ""
        case "Contents":
            if let key {
                results.append(S3ObjectSummary(key: key, size: size, lastModified: lastModified))
            }
            inContents = false
        default:
            break
        }
    }

    /// S3 timestamps: "2024-05-01T10:20:30.000Z".
    static var dateFormat: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
