import Foundation
import OSLog

/// Central diagnostics: every handled error lands here (OSLog + an
/// in-memory ring buffer shown in Settings → Diagnostics). Amounts and
/// other financial data are never logged — only messages and contexts.
@MainActor
enum ProMeLog {
    static let logger = Logger(subsystem: "app.prome", category: "app")

    @Observable
    final class Store {
        static let shared = Store()
        private(set) var entries: [String] = []
        private let capacity = 200

        func append(_ line: String) {
            entries.append(line)
            if entries.count > capacity {
                entries.removeFirst(entries.count - capacity)
            }
        }

        func clear() {
            entries.removeAll()
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Records a handled error and returns its message, so call sites can
    /// stay one-liners: `errorMessage = ProMeLog.record(error)`.
    static func record(_ error: any Error, context: String = "") -> String {
        let line = "[\(timeFormatter.string(from: .now))] \(context.isEmpty ? "" : context + ": ")\(error.localizedDescription)"
        logger.error("\(line, privacy: .public)")
        Store.shared.append(line)
        return error.localizedDescription
    }

    /// Records a noteworthy (non-error) event.
    static func event(_ message: String) {
        let line = "[\(timeFormatter.string(from: .now))] \(message)"
        logger.info("\(line, privacy: .public)")
        Store.shared.append(line)
    }
}
