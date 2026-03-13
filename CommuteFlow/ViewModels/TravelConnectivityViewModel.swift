import CoreLocation
import Foundation

@MainActor
final class TravelConnectivityViewModel: ObservableObject {
    enum TravelSortOption: String, CaseIterable, Identifiable {
        case bestConnectivity = "Best Connectivity"
        case cheapest = "Cheapest"

        var id: String { rawValue }
    }

    @Published var cityName: String = MockData.cityName
    @Published var sortOption: TravelSortOption = .bestConnectivity
    @Published var minTouristScore: Double = 70
    @Published var maxNightlyPrice: Double = 350
    @Published private(set) var cityCoordinate = CLLocationCoordinate2D(latitude: 33.765, longitude: -84.389)
    @Published private(set) var touristHubs: [TouristHub] = []
    @Published private(set) var stays: [Property] = []
    @Published private(set) var loadState: LoadState = .idle

    private let transitService: TransitProviding

    init(transitService: TransitProviding) {
        self.transitService = transitService
    }

    var sortedStays: [Property] {
        let filtered = stays.filter { stay in
            let score = stay.touristConnectivityScore ?? 0
            return score >= Int(minTouristScore.rounded()) &&
                extractLowerPrice(from: stay.priceDisplay) <= Int(maxNightlyPrice.rounded())
        }

        switch sortOption {
        case .bestConnectivity:
            return filtered.sorted {
                ($0.touristConnectivityScore ?? 0) > ($1.touristConnectivityScore ?? 0)
            }
        case .cheapest:
            return filtered.sorted {
                extractLowerPrice(from: $0.priceDisplay) < extractLowerPrice(from: $1.priceDisplay)
            }
        }
    }

    func load() async {
        loadState = .loading
        touristHubs = cityName.caseInsensitiveCompare("Atlanta") == .orderedSame ? MockData.touristHubs : []
        do {
            let result = try await transitService.fetchTouristStays(for: cityName, hubs: touristHubs)
            cityCoordinate = result.cityCoordinate
            touristHubs = result.touristHubs
            stays = result.properties
            loadState = .loaded
        } catch {
            stays = []
            loadState = .failed(error.localizedDescription)
        }
    }

    private func extractLowerPrice(from priceText: String) -> Int {
        let cleaned = priceText.replacingOccurrences(of: ",", with: "")
        let values = cleaned.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap(Int.init)
        return values.min() ?? .max
    }
}
