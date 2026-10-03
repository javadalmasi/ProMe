import CoreLocation
import MapKit
import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Saved places with free OpenStreetMap search (Nominatim). Balad needs an
/// API key; OSM is keyless and free, so it is the default provider.
struct PlacesView: View {
    @Environment(AppModel.self) private var appModel

    @State private var places: [PlaceMO] = []
    @State private var searchPresented = false
    @State private var selectedPlace: PlaceMO?

    var body: some View {
        VStack(spacing: 0) {
            if places.isEmpty {
                ScrollView {
                    EmptyStateView(
                        systemImage: "mappin.and.ellipse",
                        title: String(localized: "No saved places"),
                        detail: String(localized: "Search the map (OpenStreetMap) and save home, work and other places.")
                    )
                    .padding(.top, 60)
                }
            } else {
                List {
                    ForEach(places, id: \.objectID) { place in
                        row(place)
                    }
                    .onDelete { offsets in
                        delete(at: offsets)
                    }
                }
                .appListStyle()
            }
        }
        .navigationTitle(String(localized: "Places"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    searchPresented = true
                } label: {
                    Label(String(localized: "Find on Map"), systemImage: "magnifyingglass")
                }
            }
        }
        .task(id: appModel.dataEpoch) { reload() }
        .onAppear { reload() }
        .sheet(isPresented: $searchPresented, onDismiss: reload) {
            PlaceSearchSheet()
        }
        .sheet(item: $selectedPlace, onDismiss: { selectedPlace = nil }) { place in
            PlaceMapSheet(place: place)
        }
    }

    private func reload() {
        guard let services = appModel.services else { return }
        places = (try? services.places.all()) ?? []
    }

    private func delete(at offsets: IndexSet) {
        let targets = offsets.compactMap { places.indices.contains($0) ? places[$0] : nil }
        for place in targets {
            try? appModel.services?.places.delete(place)
        }
        reload()
        appModel.bumpData()
    }

    @ViewBuilder
    private func row(_ place: PlaceMO) -> some View {
        Button {
            selectedPlace = place
        } label: {
            HStack(spacing: 12) {
                Image(systemName: PlaceGlyph.icon(place.category))
                    .font(.appTitle3)
                    .foregroundStyle(Color.orange)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(place.name).font(.appBody.weight(.medium))
                        if place.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.appCaption2)
                                .foregroundStyle(Color.yellow)
                        }
                    }
                    if let address = place.address, !address.isEmpty {
                        Text(address)
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(String(format: "%.4f, %.4f", place.latitude, place.longitude))
                        .font(.appCaption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                categoryBadge(place.category)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .contextMenu {
            Button(place.isFavorite ? String(localized: "Remove Favorite") : String(localized: "Favorite")) {
                place.isFavorite.toggle()
                try? appModel.services?.places.save(place)
                reload()
            }
            Button(String(localized: "Delete"), role: .destructive) {
                try? appModel.services?.places.delete(place)
                reload()
                appModel.bumpData()
            }
        }
    }

    @ViewBuilder
    private func categoryBadge(_ category: PlaceCategory) -> some View {
        Text(PlaceGlyph.name(category))
            .font(.appCaption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.orange.opacity(0.12)))
            .foregroundStyle(Color.orange)
    }
}

enum PlaceGlyph {
    static func icon(_ category: PlaceCategory) -> String {
        switch category {
        case .home: "house"
        case .work: "building.2"
        case .family: "person.2"
        case .friends: "figure.2.and.person.handsup"
        case .other: "mappin"
        }
    }

    static func name(_ category: PlaceCategory) -> String {
        switch category {
        case .home: String(localized: "Home")
        case .work: String(localized: "Work")
        case .family: String(localized: "Family")
        case .friends: String(localized: "Friends")
        case .other: String(localized: "Other")
        }
    }
}

// MARK: - OpenStreetMap search

/// One Nominatim search hit.
struct GeoResult: Identifiable, Equatable {
    let id: String
    let title: String
    let address: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Parses the Nominatim JSON element.
    static func from(_ element: [String: Any]) -> GeoResult? {
        guard let latString = element["lat"] as? String,
              let lonString = element["lon"] as? String,
              let lat = Double(latString),
              let lon = Double(lonString) else { return nil }
        let displayName = element["display_name"] as? String ?? ""
        let parts = displayName.split(separator: ",", omittingEmptySubsequences: true).map(String.init)
        let title = parts.first ?? displayName
        let address = parts.dropFirst().joined(separator: ", ")
        return GeoResult(
            id: element["place_id"].map { "\($0)" } ?? UUID().uuidString,
            title: title,
            address: address,
            latitude: lat,
            longitude: lon
        )
    }
}

/// Free text search against the OpenStreetMap Nominatim service.
enum GeoSearch {
    /// `https://nominatim.openstreetmap.org/search?q=…&format=json&accept-language=fa&limit=20`
    static func search(_ query: String, language: String = "fa") async throws -> [GeoResult] {
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "accept-language", value: language),
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        // Nominatim requires an identifying User-Agent.
        request.setValue("ProMe/1.0 (personal organizer app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        guard let elements = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return elements.compactMap(GeoResult.from)
    }

    /// Reverse geocode for the address label of a saved place.
    static func address(latitude: Double, longitude: Double, language: String = "fa") async -> String? {
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "accept-language", value: language),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("ProMe/1.0 (personal organizer app)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let element = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return element["display_name"] as? String
    }
}

// MARK: - Search sheet

/// Map + search sheet: pick a result, name it, choose a category, save.
struct PlaceSearchSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [GeoResult] = []
    @State private var searching = false
    @State private var selected: GeoResult?
    @State private var name = ""
    @State private var category: PlaceCategory = .other
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6892, longitude: 51.3890), // Tehran
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    ))

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField(String(localized: "Search address…"), text: $query)
                        .onSubmit { Task { await search() } }
                    Button {
                        Task { await search() }
                    } label: {
                        if searching {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    .disabled(query.isEmpty || searching)
                }
                .padding(12)

                Map(position: $cameraPosition) {
                    if let selected {
                        Marker(selected.title, coordinate: selected.coordinate)
                    }
                }
                .frame(minHeight: 220)

                if let selected {
                    saveForm(selected)
                }

                List {
                    ForEach(results) { result in
                        Button {
                            select(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title).font(.appCallout.weight(.medium))
                                Text(result.address).font(.appCaption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                }
                .appListStyle()
            }
            .navigationTitle(String(localized: "Find on Map"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 640)
        #endif
    }

    @ViewBuilder
    private func saveForm(_ result: GeoResult) -> some View {
        VStack(spacing: 8) {
            Divider()
            TextField(String(localized: "Place name"), text: $name)
                .textFieldStyle(.roundedBorder)
            Picker(String(localized: "Category"), selection: $category) {
                ForEach(PlaceCategory.allCases, id: \.self) { option in
                    Label(PlaceGlyph.name(option), systemImage: PlaceGlyph.icon(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            Button {
                save(result)
            } label: {
                Label(String(localized: "Save Place"), systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func select(_ result: GeoResult) {
        selected = result
        if name.isEmpty { name = result.title }
        cameraPosition = .region(MKCoordinateRegion(
            center: result.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    private func save(_ result: GeoResult) {
        guard let services = appModel.services else { return }
        _ = try? services.places.create(
            name: name.trimmingCharacters(in: .whitespaces),
            category: category,
            address: result.address,
            latitude: result.latitude,
            longitude: result.longitude
        )
        appModel.bumpData()
        dismiss()
    }

    private func search() async {
        searching = true
        defer { searching = false }
        results = (try? await GeoSearch.search(query)) ?? []
    }
}

/// Full map preview of a saved place.
struct PlaceMapSheet: View {
    @Environment(\.dismiss) private var dismiss

    let place: PlaceMO
    @State private var address: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))) {
                    Marker(place.name, coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
                }
                if let address {
                    Text(address)
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            }
            .navigationTitle(place.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .task {
                address = await GeoSearch.address(latitude: place.latitude, longitude: place.longitude)
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
    }
}
