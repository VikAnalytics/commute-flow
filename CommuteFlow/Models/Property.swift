import CoreLocation
import Foundation
import MapKit

struct Property: Identifiable, Hashable {
    enum Kind: String {
        case apartment
        case hotel
        case airbnb
    }

    enum ListingSource: String {
        case verified
        case generated
    }

    let id = UUID()
    let kind: Kind
    let name: String
    let coordinate: CLLocationCoordinate2D
    let monthlyRentRange: String?
    let nightlyRateRange: String?
    let commuteTimeMinutes: Int
    let walkingMinutes: Int
    let commuteBreakdown: String
    let websiteURL: URL
    let rating: Double?
    let ratingReviewCount: Int?
    let listingSource: ListingSource
    let touristConnectivityScore: Int?
    let polylineCoordinates: [CLLocationCoordinate2D]

    var routePolyline: MKPolyline {
        MKPolyline(coordinates: polylineCoordinates, count: polylineCoordinates.count)
    }

    var priceDisplay: String {
        monthlyRentRange ?? nightlyRateRange ?? "N/A"
    }

    var primaryActionTitle: String {
        switch kind {
        case .apartment:
            return "Visit Website"
        case .hotel, .airbnb:
            return "Book Now"
        }
    }

    var ratingSummary: String? {
        guard let rating else { return nil }
        if let ratingReviewCount {
            return String(format: "%.1f (%d reviews)", rating, ratingReviewCount)
        }
        return String(format: "%.1f", rating)
    }

    var stableKey: String {
        "\(kind.rawValue)|\(name.lowercased())|\(coordinate.latitude)|\(coordinate.longitude)|\(listingSource.rawValue)"
    }

    var listingSourceBadgeTitle: String {
        switch listingSource {
        case .verified:
            return "Verified Listing"
        case .generated:
            return "Generated Sample"
        }
    }

    static func == (lhs: Property, rhs: Property) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
