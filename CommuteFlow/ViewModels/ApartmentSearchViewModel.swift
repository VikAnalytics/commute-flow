import Foundation

@MainActor
final class ApartmentSearchViewModel: ObservableObject {
    static let defaultSortOption: PropertySortOption = .fastestCommute
    static let defaultMaxCommuteMinutes: Double = 40
    static let defaultMaxMonthlyRent: Double = 3000

    @Published var workplaceAddress: String = MockData.workplaceName
    @Published var sortOption: PropertySortOption = defaultSortOption
    @Published var maxCommuteMinutes: Double = defaultMaxCommuteMinutes
    @Published var maxMonthlyRent: Double = defaultMaxMonthlyRent
    @Published private(set) var workplaceCoordinate = MockData.workplaceCoordinate
    @Published private(set) var workplaceName = MockData.workplaceName
    @Published private(set) var apartments: [Property] = []
    @Published private(set) var loadState: LoadState = .idle

    private let transitService: TransitProviding

    init(transitService: TransitProviding) {
        self.transitService = transitService
    }

    var sortedApartments: [Property] {
        let filtered = apartments.filter { apartment in
            apartment.commuteTimeMinutes <= Int(maxCommuteMinutes.rounded()) &&
                extractLowerPrice(from: apartment.priceDisplay) <= Int(maxMonthlyRent.rounded())
        }

        switch sortOption {
        case .fastestCommute:
            return filtered.sorted { $0.commuteTimeMinutes < $1.commuteTimeMinutes }
        case .cheapest:
            return filtered.sorted { extractLowerPrice(from: $0.priceDisplay) < extractLowerPrice(from: $1.priceDisplay) }
        case .leastWalking:
            return filtered.sorted { $0.walkingMinutes < $1.walkingMinutes }
        case .highestRated:
            return filtered.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        }
    }

    func loadApartments() async {
        loadState = .loading
        do {
            let result = try await transitService.fetchApartments(near: workplaceAddress, withinMiles: 15)
            workplaceCoordinate = result.workplaceCoordinate
            workplaceName = result.workplaceName
            apartments = result.properties
            loadState = .loaded
        } catch {
            apartments = []
            loadState = .failed(error.localizedDescription)
        }
    }

    var hasCustomFilters: Bool {
        sortOption != Self.defaultSortOption ||
            Int(maxCommuteMinutes.rounded()) != Int(Self.defaultMaxCommuteMinutes.rounded()) ||
            Int(maxMonthlyRent.rounded()) != Int(Self.defaultMaxMonthlyRent.rounded())
    }

    func resetFilters() {
        sortOption = Self.defaultSortOption
        maxCommuteMinutes = Self.defaultMaxCommuteMinutes
        maxMonthlyRent = Self.defaultMaxMonthlyRent
    }

    private func extractLowerPrice(from priceText: String) -> Int {
        let cleaned = priceText.replacingOccurrences(of: ",", with: "")
        let values = cleaned.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap(Int.init)
        return values.min() ?? .max
    }
}
