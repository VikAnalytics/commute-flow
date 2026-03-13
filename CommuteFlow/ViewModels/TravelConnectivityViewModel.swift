import Foundation

@MainActor
final class TravelConnectivityViewModel: ObservableObject {
    @Published var cityName: String = MockData.cityName
    @Published private(set) var touristHubs: [TouristHub] = []
    @Published private(set) var stays: [Property] = []
    @Published private(set) var loadState: LoadState = .idle

    private let transitService: TransitProviding

    init(transitService: TransitProviding) {
        self.transitService = transitService
    }

    var sortedStays: [Property] {
        stays.sorted {
            ($0.touristConnectivityScore ?? 0) > ($1.touristConnectivityScore ?? 0)
        }
    }

    func load() async {
        loadState = .loading
        touristHubs = MockData.touristHubs
        do {
            stays = try await transitService.fetchTouristStays(for: cityName, hubs: touristHubs)
            loadState = .loaded
        } catch {
            stays = []
            loadState = .failed(error.localizedDescription)
        }
    }
}
