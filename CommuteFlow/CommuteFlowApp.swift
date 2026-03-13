import CoreLocation
import Foundation
import SwiftUI
import SwiftData

@main
struct CommuteFlowApp: App {
    private let dependencies = LiveAppDependencies()

    var body: some Scene {
        WindowGroup {
            RootTabView(dependencies: dependencies)
        }
        .modelContainer(for: [RecentSearch.self, SavedProperty.self])
    }
}

@Model
final class RecentSearch {
    @Attribute(.unique) var query: String
    var lastUsedAt: Date

    init(query: String, lastUsedAt: Date = .now) {
        self.query = query
        self.lastUsedAt = lastUsedAt
    }
}

@Model
final class SavedProperty {
    @Attribute(.unique) var propertyKey: String
    var savedAt: Date
    var kindRawValue: String
    var name: String
    var latitude: Double
    var longitude: Double
    var monthlyRentRange: String?
    var nightlyRateRange: String?
    var commuteTimeMinutes: Int
    var walkingMinutes: Int
    var commuteBreakdown: String
    var websiteURLString: String
    var rating: Double?
    var ratingReviewCount: Int?
    var listingSourceRawValue: String
    var touristConnectivityScore: Int?
    var journeySegmentsBlob: String = ""

    init(from property: Property, savedAt: Date = .now) {
        propertyKey = property.stableKey
        self.savedAt = savedAt
        kindRawValue = property.kind.rawValue
        name = property.name
        latitude = property.coordinate.latitude
        longitude = property.coordinate.longitude
        monthlyRentRange = property.monthlyRentRange
        nightlyRateRange = property.nightlyRateRange
        commuteTimeMinutes = property.commuteTimeMinutes
        walkingMinutes = property.walkingMinutes
        commuteBreakdown = property.commuteBreakdown
        websiteURLString = property.websiteURL.absoluteString
        rating = property.rating
        ratingReviewCount = property.ratingReviewCount
        listingSourceRawValue = property.listingSource.rawValue
        touristConnectivityScore = property.touristConnectivityScore
        journeySegmentsBlob = property.journeySegments.joined(separator: "\n")
    }

    var property: Property {
        Property(
            kind: Property.Kind(rawValue: kindRawValue) ?? .apartment,
            name: name,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            monthlyRentRange: monthlyRentRange,
            nightlyRateRange: nightlyRateRange,
            commuteTimeMinutes: commuteTimeMinutes,
            walkingMinutes: walkingMinutes,
            commuteBreakdown: commuteBreakdown,
            websiteURL: URL(string: websiteURLString) ?? URL(string: "https://www.apartments.com")!,
            rating: rating,
            ratingReviewCount: ratingReviewCount,
            listingSource: Property.ListingSource(rawValue: listingSourceRawValue) ?? .verified,
            touristConnectivityScore: touristConnectivityScore,
            polylineCoordinates: [CLLocationCoordinate2D(latitude: latitude, longitude: longitude)],
            journeySegments: journeySegmentsBlob.isEmpty ? [] : journeySegmentsBlob.components(separatedBy: "\n")
        )
    }
}
