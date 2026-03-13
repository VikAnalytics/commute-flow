import Foundation

enum PropertySortOption: String, CaseIterable, Identifiable {
    case fastestCommute = "Fastest Commute"
    case cheapest = "Cheapest"
    case leastWalking = "Least Walking"
    case highestRated = "Highest Rated"

    var id: String { rawValue }
}
