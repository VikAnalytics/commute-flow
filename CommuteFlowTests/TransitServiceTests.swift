import CoreLocation
import XCTest
@testable import CommuteFlow

final class TransitServiceTests: XCTestCase {
    func testFetchApartmentsReturnsLiveResultsWhenLiveFetcherSucceeds() async throws {
        let resolver = FixedLocationResolver(
            coordinate: CLLocationCoordinate2D(latitude: 33.7826, longitude: -84.3888)
        )
        let analytics = AnalyticsSpy()

        let service = TransitService(
            locationResolver: resolver,
            googleAPIKey: "test-key",
            shouldUseDirectGoogle: true,
            backendBaseURL: nil,
            analytics: analytics,
            liveApartmentsFetcher: { workplace, _, _, _ in
                [
                    Property(
                        kind: .apartment,
                        name: "Live Property",
                        coordinate: workplace,
                        monthlyRentRange: "$2000 - $2500",
                        nightlyRateRange: nil,
                        commuteTimeMinutes: 14,
                        walkingMinutes: 6,
                        commuteBreakdown: "Live route",
                        websiteURL: URL(string: "https://example.com")!,
                        rating: 4.5,
                        ratingReviewCount: 111,
                        listingSource: .verified,
                        touristConnectivityScore: nil,
                        polylineCoordinates: [workplace]
                    )
                ]
            }
        )

        let result = try await service.fetchApartments(near: "Any Address", withinMiles: 15)

        XCTAssertEqual(result.properties.count, 1)
        XCTAssertEqual(result.properties.first?.name, "Live Property")
        XCTAssertEqual(result.properties.first?.listingSource, .verified)
        XCTAssertTrue(analytics.events.contains(where: { $0.name == "apartments_google_success" }))
    }

    func testFetchApartmentsFallsBackToGeneratedWhenLiveFetcherFails() async throws {
        let resolver = FixedLocationResolver(
            coordinate: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        )
        let analytics = AnalyticsSpy()

        let service = TransitService(
            locationResolver: resolver,
            googleAPIKey: "test-key",
            shouldUseDirectGoogle: true,
            backendBaseURL: nil,
            analytics: analytics,
            liveApartmentsFetcher: { _, _, _, _ in
                throw TransitServiceError.providerUnavailable
            }
        )

        let result = try await service.fetchApartments(near: "Seattle", withinMiles: 15)

        XCTAssertFalse(result.properties.isEmpty)
        XCTAssertTrue(result.properties.allSatisfy { $0.listingSource == .generated })
        XCTAssertTrue(analytics.events.contains(where: { $0.name == "apartments_google_failed" }))
        XCTAssertTrue(analytics.events.contains(where: { $0.name == "apartments_mock_fallback" }))
    }

    func testFetchApartmentsFallsBackWhenAPIKeyMissing() async throws {
        let resolver = FixedLocationResolver(
            coordinate: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        )
        let analytics = AnalyticsSpy()

        let service = TransitService(
            locationResolver: resolver,
            googleAPIKey: nil,
            shouldUseDirectGoogle: true,
            backendBaseURL: nil,
            analytics: analytics
        )

        let result = try await service.fetchApartments(near: "Seattle", withinMiles: 15)

        XCTAssertFalse(result.properties.isEmpty)
        XCTAssertTrue(result.properties.allSatisfy { $0.listingSource == .generated })
        XCTAssertTrue(analytics.events.contains(where: { $0.name == "apartments_missing_api_key" }))
        XCTAssertTrue(analytics.events.contains(where: { $0.name == "apartments_mock_fallback" }))
    }

    func testFetchApartmentsFallsBackWhenDirectGoogleDisabled() async throws {
        let resolver = FixedLocationResolver(
            coordinate: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        )
        let analytics = AnalyticsSpy()

        let service = TransitService(
            locationResolver: resolver,
            googleAPIKey: "test-key",
            shouldUseDirectGoogle: false,
            backendBaseURL: nil,
            analytics: analytics
        )

        let result = try await service.fetchApartments(near: "Seattle", withinMiles: 15)

        XCTAssertFalse(result.properties.isEmpty)
        XCTAssertTrue(result.properties.allSatisfy { $0.listingSource == .generated })
        XCTAssertTrue(analytics.events.contains(where: { $0.name == "apartments_direct_google_disabled" }))
        XCTAssertTrue(analytics.events.contains(where: { $0.name == "apartments_mock_fallback" }))
    }

    func testFetchApartmentsAttemptsBackendBeforeGoogleWhenBackendConfigured() async throws {
        let resolver = FixedLocationResolver(
            coordinate: CLLocationCoordinate2D(latitude: 33.7826, longitude: -84.3888)
        )
        let analytics = AnalyticsSpy()
        let flag = MutableFlag()

        let service = TransitService(
            locationResolver: resolver,
            googleAPIKey: "test-key",
            shouldUseDirectGoogle: true,
            backendBaseURL: URL(string: "https://127.0.0.1:65535")!,
            analytics: analytics,
            liveApartmentsFetcher: { _, _, _, _ in
                flag.value = true
                return []
            }
        )

        _ = try await service.fetchApartments(near: "Atlanta", withinMiles: 15)

        XCTAssertTrue(flag.value)
        let eventNames = analytics.events.map(\.name)
        let backendIndex = eventNames.firstIndex(of: "apartments_backend_failed")
        let googleIndex = eventNames.firstIndex(of: "apartments_google_empty")
        XCTAssertNotNil(backendIndex)
        XCTAssertNotNil(googleIndex)
        if let backendIndex, let googleIndex {
            XCTAssertLessThan(backendIndex, googleIndex)
        }
    }

    func testFetchApartmentsFallsBackWhenGoogleReturnsEmptyList() async throws {
        let resolver = FixedLocationResolver(
            coordinate: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        )
        let analytics = AnalyticsSpy()

        let service = TransitService(
            locationResolver: resolver,
            googleAPIKey: "test-key",
            shouldUseDirectGoogle: true,
            backendBaseURL: nil,
            analytics: analytics,
            liveApartmentsFetcher: { _, _, _, _ in [] }
        )

        let result = try await service.fetchApartments(near: "Seattle", withinMiles: 15)

        XCTAssertFalse(result.properties.isEmpty)
        XCTAssertTrue(result.properties.allSatisfy { $0.listingSource == .generated })
        XCTAssertTrue(analytics.events.contains(where: { $0.name == "apartments_google_empty" }))
        XCTAssertTrue(analytics.events.contains(where: { $0.name == "apartments_mock_fallback" }))
    }

    func testFetchApartmentsGracefullyFallsBackWhenBackendInvalid() async throws {
        let resolver = FixedLocationResolver(
            coordinate: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        )
        let analytics = AnalyticsSpy()

        let service = TransitService(
            locationResolver: resolver,
            googleAPIKey: nil,
            shouldUseDirectGoogle: false,
            backendBaseURL: URL(string: "https://127.0.0.1:65535")!,
            analytics: analytics
        )

        let result = try await service.fetchApartments(near: "Seattle", withinMiles: 15)

        XCTAssertFalse(result.properties.isEmpty)
        XCTAssertTrue(analytics.events.contains(where: { $0.name == "apartments_backend_failed" }))
        XCTAssertTrue(analytics.events.contains(where: { $0.name == "apartments_mock_fallback" }))
    }
}

private struct FixedLocationResolver: LocationResolving {
    let coordinate: CLLocationCoordinate2D

    func resolveAddress(_ address: String) async throws -> CLLocationCoordinate2D {
        coordinate
    }
}

private final class AnalyticsSpy: AnalyticsTracking {
    struct Event {
        let name: String
        let metadata: [String: String]
    }

    private(set) var events: [Event] = []

    func track(name: String, metadata: [String: String]) {
        events.append(Event(name: name, metadata: metadata))
    }
}

private final class MutableFlag {
    var value: Bool = false
}
