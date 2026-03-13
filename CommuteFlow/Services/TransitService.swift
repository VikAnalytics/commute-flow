import CoreLocation
import Foundation
import os

struct ApartmentSearchResult {
    let workplaceName: String
    let workplaceCoordinate: CLLocationCoordinate2D
    let properties: [Property]
}

struct TravelSearchResult {
    let cityName: String
    let cityCoordinate: CLLocationCoordinate2D
    let touristHubs: [TouristHub]
    let properties: [Property]
}

protocol LocationResolving {
    func resolveAddress(_ address: String) async throws -> CLLocationCoordinate2D
}

enum LocationResolverError: LocalizedError {
    case unresolvedAddress
    case geocoderFailure(String)

    var errorDescription: String? {
        switch self {
        case .unresolvedAddress:
            return "Could not find that address. Try a fuller address like street, city, and state."
        case let .geocoderFailure(message):
            return message
        }
    }
}

final class AppleGeocoderLocationResolver: LocationResolving {
    private let geocoder = CLGeocoder()

    func resolveAddress(_ address: String) async throws -> CLLocationCoordinate2D {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()

        // Keep a deterministic fallback for the seeded demo address.
        if normalized.contains("ncr headquarters") || normalized.contains("spring st nw") {
            return MockData.workplaceCoordinate
        }

        do {
            let placemarks = try await geocoder.geocodeAddressStringAsync(trimmed)
            if let coordinate = placemarks.first?.location?.coordinate {
                return coordinate
            }
            throw LocationResolverError.unresolvedAddress
        } catch let error as LocationResolverError {
            throw error
        } catch {
            throw LocationResolverError.geocoderFailure("Address lookup failed. Please try again.")
        }
    }
}

enum TransitServiceError: LocalizedError {
    case invalidInput(String)
    case providerUnavailable
    case unsupportedCity(String)
    case upstreamError(String)

    var errorDescription: String? {
        switch self {
        case let .invalidInput(message):
            return message
        case .providerUnavailable:
            return "Transit provider is currently unavailable."
        case let .unsupportedCity(city):
            return city
        case let .upstreamError(message):
            return message
        }
    }
}

protocol TransitProviding {
    func fetchApartments(near workplace: String, withinMiles: Double) async throws -> ApartmentSearchResult
    func fetchTouristStays(for cityName: String, hubs: [TouristHub]) async throws -> TravelSearchResult
}

protocol AnalyticsTracking {
    func track(name: String, metadata: [String: String])
}

final class ConsoleAnalyticsTracker: AnalyticsTracking {
    private let logger = Logger(subsystem: "com.commuteflow.app", category: "analytics")

    func track(name: String, metadata: [String: String]) {
        let flat = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        logger.log("\(name, privacy: .public) \(flat, privacy: .public)")
    }
}

final class TransitService: TransitProviding {
    typealias ApartmentsLiveFetcher = @Sendable (_ workplace: CLLocationCoordinate2D, _ destinationName: String, _ withinMiles: Double, _ apiKey: String) async throws -> [Property]
    typealias TravelLiveFetcher = @Sendable (_ cityName: String, _ hubs: [TouristHub], _ apiKey: String) async throws -> [Property]

    private let locationResolver: LocationResolving
    private let cache = TransitCache()
    private let googleAPIKey: String?
    private let shouldUseDirectGoogle: Bool
    private let backendBaseURL: URL?
    private let analytics: AnalyticsTracking
    private let liveApartmentsFetcher: ApartmentsLiveFetcher?
    private let liveTravelFetcher: TravelLiveFetcher?

    init(
        locationResolver: LocationResolving = AppleGeocoderLocationResolver(),
        googleAPIKey: String? = RuntimeConfig.googleAPIKey,
        shouldUseDirectGoogle: Bool = RuntimeConfig.shouldUseDirectGoogle,
        backendBaseURL: URL? = RuntimeConfig.backendBaseURL,
        analytics: AnalyticsTracking = ConsoleAnalyticsTracker(),
        liveApartmentsFetcher: ApartmentsLiveFetcher? = nil,
        liveTravelFetcher: TravelLiveFetcher? = nil
    ) {
        self.locationResolver = locationResolver
        self.googleAPIKey = googleAPIKey
        self.shouldUseDirectGoogle = shouldUseDirectGoogle
        self.backendBaseURL = backendBaseURL
        self.analytics = analytics
        self.liveApartmentsFetcher = liveApartmentsFetcher
        self.liveTravelFetcher = liveTravelFetcher
    }

    func fetchApartments(near workplace: String, withinMiles: Double) async throws -> ApartmentSearchResult {
        let trimmed = workplace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TransitServiceError.invalidInput("Please enter a workplace address.")
        }
        guard withinMiles > 0 else {
            throw TransitServiceError.invalidInput("Search radius must be greater than zero.")
        }

        let cacheKey = "apt|\(trimmed.lowercased())|\(withinMiles)"
        if let cached = await cache.apartmentResult(for: cacheKey) {
            return cached
        }

        let workplaceCoordinate = try await locationResolver.resolveAddress(trimmed)
        guard isInAtlantaMarket(workplaceCoordinate) else {
            throw TransitServiceError.unsupportedCity("Apartments are currently available only in Atlanta metro.")
        }
        let attemptedBackend = backendBaseURL != nil
        if let backendBaseURL {
            do {
                if let backendResult = try await fetchBackendApartments(
                    baseURL: backendBaseURL,
                    workplaceName: trimmed,
                    workplaceCoordinate: workplaceCoordinate,
                    withinMiles: withinMiles
                ) {
                    analytics.track(name: "apartments_backend_success", metadata: ["count": "\(backendResult.properties.count)"])
                    await cache.setApartmentResult(backendResult, for: cacheKey)
                    return backendResult
                }
            } catch {
                analytics.track(name: "apartments_backend_failed", metadata: ["error": error.localizedDescription])
            }
        }

        let apiKey = googleAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if shouldUseDirectGoogle && !apiKey.isEmpty {
            do {
                let liveProperties = if let liveApartmentsFetcher {
                    try await liveApartmentsFetcher(workplaceCoordinate, trimmed, withinMiles, apiKey)
                } else {
                    try await fetchLiveApartments(
                        near: workplaceCoordinate,
                        destinationName: trimmed,
                        withinMiles: withinMiles,
                        apiKey: apiKey
                    )
                }
                if !liveProperties.isEmpty {
                    analytics.track(name: "apartments_google_success", metadata: ["count": "\(liveProperties.count)"])
                    let result = ApartmentSearchResult(
                        workplaceName: trimmed,
                        workplaceCoordinate: workplaceCoordinate,
                        properties: liveProperties
                    )
                    await cache.setApartmentResult(result, for: cacheKey)
                    return result
                }
                analytics.track(name: "apartments_google_empty", metadata: [:])
            } catch {
                analytics.track(name: "apartments_google_failed", metadata: ["error": error.localizedDescription])
            }
        } else if !shouldUseDirectGoogle {
            analytics.track(name: "apartments_direct_google_disabled", metadata: [:])
        } else {
            if attemptedBackend {
                analytics.track(name: "apartments_backend_failed_no_client_key", metadata: [:])
            } else {
                analytics.track(name: "apartments_missing_api_key", metadata: [:])
            }
        }

        let maxDistanceMeters = withinMiles * 1609.344
        let filtered = MockData.atlantaApartments.filter { property in
            let propertyLocation = CLLocation(latitude: property.coordinate.latitude, longitude: property.coordinate.longitude)
            let workplaceLocation = CLLocation(latitude: workplaceCoordinate.latitude, longitude: workplaceCoordinate.longitude)
            return propertyLocation.distance(from: workplaceLocation) <= maxDistanceMeters
        }
        let properties = filtered.isEmpty
            ? MockData.generatedApartments(near: workplaceCoordinate)
            : filtered

        let result = ApartmentSearchResult(
            workplaceName: trimmed,
            workplaceCoordinate: workplaceCoordinate,
            properties: properties
        )
        analytics.track(name: "apartments_mock_fallback", metadata: ["count": "\(properties.count)"])
        await cache.setApartmentResult(result, for: cacheKey)
        return result
    }

    func fetchTouristStays(for cityName: String, hubs: [TouristHub]) async throws -> TravelSearchResult {
        let trimmed = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TransitServiceError.invalidInput("Please enter a city.")
        }
        let cityContext = try await resolveCityContext(trimmed)
        guard cityContext.isAtlanta || cityContext.isInEurope else {
            throw TransitServiceError.unsupportedCity("Travel supports Atlanta and cities in Europe. Received: \(trimmed).")
        }
        let effectiveHubs = if !hubs.isEmpty {
            hubs
        } else {
            generateFallbackHubs(near: cityContext.coordinate)
        }
        let orderedEffectiveHubs = orderHubsSequentially(around: cityContext.coordinate, hubs: effectiveHubs)

        let attemptedBackend = backendBaseURL != nil
        if let backendBaseURL, !orderedEffectiveHubs.isEmpty {
            do {
                if let backendStays = try await fetchBackendTravelStays(baseURL: backendBaseURL, cityName: trimmed, hubs: orderedEffectiveHubs) {
                    analytics.track(name: "travel_backend_success", metadata: ["count": "\(backendStays.count)"])
                    return TravelSearchResult(
                        cityName: trimmed,
                        cityCoordinate: cityContext.coordinate,
                        touristHubs: orderedEffectiveHubs,
                        properties: backendStays
                    )
                }
            } catch {
                analytics.track(name: "travel_backend_failed", metadata: ["error": error.localizedDescription])
            }
        }

        let apiKey = googleAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if shouldUseDirectGoogle && !apiKey.isEmpty {
            do {
                let hubsForLiveScoring = try await discoverTouristHubs(near: cityContext.coordinate, apiKey: apiKey)
                let liveHubs = hubsForLiveScoring.isEmpty ? orderedEffectiveHubs : orderHubsSequentially(around: cityContext.coordinate, hubs: hubsForLiveScoring)
                let liveStays = if let liveTravelFetcher {
                    try await liveTravelFetcher(trimmed, liveHubs, apiKey)
                } else {
                    try await fetchLiveTouristStays(cityName: trimmed, hubs: liveHubs, apiKey: apiKey)
                }
                if !liveStays.isEmpty {
                    analytics.track(name: "travel_google_success", metadata: ["count": "\(liveStays.count)"])
                    return TravelSearchResult(
                        cityName: trimmed,
                        cityCoordinate: cityContext.coordinate,
                        touristHubs: liveHubs,
                        properties: liveStays
                    )
                }
                analytics.track(name: "travel_google_empty", metadata: [:])
            } catch {
                analytics.track(name: "travel_google_failed", metadata: ["error": error.localizedDescription])
            }
        } else if !shouldUseDirectGoogle {
            analytics.track(name: "travel_direct_google_disabled", metadata: [:])
        } else {
            if attemptedBackend {
                analytics.track(name: "travel_backend_failed_no_client_key", metadata: [:])
            } else {
                analytics.track(name: "travel_missing_api_key", metadata: [:])
            }
        }

        // Fallback for local development without API key.
        analytics.track(name: "travel_mock_fallback", metadata: ["count": "\(MockData.atlantaTouristStays.count)"])
        return TravelSearchResult(
            cityName: trimmed,
            cityCoordinate: cityContext.coordinate,
            touristHubs: cityContext.isAtlanta ? MockData.touristHubs : orderedEffectiveHubs,
            properties: cityContext.isAtlanta ? MockData.atlantaTouristStays : MockData.atlantaTouristStays
        )
    }

    private func fetchLiveApartments(
        near workplace: CLLocationCoordinate2D,
        destinationName: String,
        withinMiles: Double,
        apiKey: String
    ) async throws -> [Property] {
        let radiusMeters = min(Int(withinMiles * 1609.344), 50_000)
        let places = try await nearbyPlaces(
            location: workplace,
            radiusMeters: radiusMeters,
            keyword: "apartment",
            type: nil,
            apiKey: apiKey
        )

        if places.isEmpty {
            return []
        }

        var properties: [Property] = []
        for (index, place) in places.prefix(8).enumerated() {
            let route = try await transitRoute(
                from: place.coordinate,
                to: workplace,
                apiKey: apiKey
            ) ?? estimatedRoute(from: place.coordinate, to: workplace)

            let website = try await placeWebsiteURL(for: place.placeID, fallback: place.googleURL, apiKey: apiKey)
            let estimatedRent = estimateMonthlyRent(index: index, rating: place.rating)

            properties.append(
                Property(
                    kind: .apartment,
                    name: place.name,
                    coordinate: place.coordinate,
                    monthlyRentRange: estimatedRent,
                    nightlyRateRange: nil,
                    commuteTimeMinutes: max(1, route.durationSeconds / 60),
                    walkingMinutes: max(0, route.walkingDurationSeconds / 60),
                    commuteBreakdown: route.breakdown,
                    websiteURL: website,
                    rating: place.rating,
                    ratingReviewCount: place.userRatingsTotal,
                    listingSource: .verified,
                    touristConnectivityScore: nil,
                    polylineCoordinates: route.polylineCoordinates,
                    journeySegments: route.segments
                )
            )
        }
        return properties
    }

    private func fetchLiveTouristStays(
        cityName: String,
        hubs: [TouristHub],
        apiKey: String
    ) async throws -> [Property] {
        guard !hubs.isEmpty else { return [] }
        let center = centroid(of: hubs.map(\.coordinate))
        let places = try await nearbyPlaces(
            location: center,
            radiusMeters: 12_000,
            keyword: "hotel",
            type: "lodging",
            apiKey: apiKey
        )

        var properties: [Property] = []
        for place in places.prefix(8) {
            var routesByHub: [LiveTransitRoute] = []
            for hub in hubs {
                let route = try await transitRoute(from: place.coordinate, to: hub.coordinate, apiKey: apiKey)
                    ?? estimatedRoute(from: place.coordinate, to: hub.coordinate)
                routesByHub.append(route)
            }

            let averageDuration = routesByHub.map(\.durationSeconds).reduce(0, +) / routesByHub.count
            let averageWalking = routesByHub.map(\.walkingDurationSeconds).reduce(0, +) / routesByHub.count
            let score = touristConnectivityScore(avgDurationSeconds: averageDuration, avgWalkingSeconds: averageWalking)
            let website = try await placeWebsiteURL(for: place.placeID, fallback: place.googleURL, apiKey: apiKey)
            let headlineRoute = routesByHub.min(by: { $0.durationSeconds < $1.durationSeconds })!
            let journeySegments = zip(hubs, routesByHub).map { hub, route in
                let path = route.segments.joined(separator: " -> ")
                return "To \(hub.name): \(path)"
            }

            properties.append(
                Property(
                    kind: .hotel,
                    name: place.name,
                    coordinate: place.coordinate,
                    monthlyRentRange: nil,
                    nightlyRateRange: estimateNightlyRate(rating: place.rating),
                    commuteTimeMinutes: max(1, averageDuration / 60),
                    walkingMinutes: max(0, averageWalking / 60),
                    commuteBreakdown: headlineRoute.breakdown,
                    websiteURL: website,
                    rating: place.rating,
                    ratingReviewCount: place.userRatingsTotal,
                    listingSource: .verified,
                    touristConnectivityScore: score,
                    polylineCoordinates: headlineRoute.polylineCoordinates,
                    journeySegments: journeySegments
                )
            )
        }

        return properties.sorted { ($0.touristConnectivityScore ?? 0) > ($1.touristConnectivityScore ?? 0) }
    }

    private func nearbyPlaces(
        location: CLLocationCoordinate2D,
        radiusMeters: Int,
        keyword: String,
        type: String?,
        apiKey: String
    ) async throws -> [LivePlace] {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/place/nearbysearch/json")!
        var queryItems = [
            URLQueryItem(name: "location", value: "\(location.latitude),\(location.longitude)"),
            URLQueryItem(name: "radius", value: "\(radiusMeters)"),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "key", value: apiKey)
        ]
        if let type {
            queryItems.append(URLQueryItem(name: "type", value: type))
        }
        components.queryItems = queryItems

        let response: GooglePlacesNearbyResponse = try await requestJSON(url: components.url!)
        guard response.status == "OK" || response.status == "ZERO_RESULTS" else {
            throw TransitServiceError.upstreamError("Google Places error: \(response.status)")
        }

        return response.results.map {
            LivePlace(
                placeID: $0.placeID,
                name: $0.name,
                coordinate: CLLocationCoordinate2D(latitude: $0.geometry.location.lat, longitude: $0.geometry.location.lng),
                rating: $0.rating,
                userRatingsTotal: $0.userRatingsTotal,
                googleURL: URL(string: "https://maps.google.com/?q=place_id:\($0.placeID)")
            )
        }
    }

    private func placeWebsiteURL(for placeID: String, fallback: URL?, apiKey: String) async throws -> URL {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/place/details/json")!
        components.queryItems = [
            URLQueryItem(name: "place_id", value: placeID),
            URLQueryItem(name: "fields", value: "website,url"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        let response: GooglePlaceDetailsResponse = try await requestJSON(url: components.url!)
        if response.status == "OK" {
            if let website = response.result?.website, let url = URL(string: website) {
                return url
            }
            if let googleURL = response.result?.url, let url = URL(string: googleURL) {
                return url
            }
        }
        if let fallback { return fallback }
        return URL(string: "https://maps.google.com")!
    }

    private func transitRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        apiKey: String
    ) async throws -> LiveTransitRoute? {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/directions/json")!
        components.queryItems = [
            URLQueryItem(name: "origin", value: "\(origin.latitude),\(origin.longitude)"),
            URLQueryItem(name: "destination", value: "\(destination.latitude),\(destination.longitude)"),
            URLQueryItem(name: "mode", value: "transit"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        let response: GoogleDirectionsResponse = try await requestJSON(url: components.url!)
        guard response.status == "OK", let route = response.routes.first, let leg = route.legs.first else {
            return nil
        }

        let polyline = decodePolyline(route.overviewPolyline.points)
        let steps = leg.steps
        let walkingSeconds = steps
            .filter { $0.travelMode.uppercased() == "WALKING" }
            .reduce(0) { $0 + ($1.duration?.value ?? 0) }

        let segments = steps.map { step in
            let mode = step.travelMode.uppercased()
            if mode == "WALKING" {
                let minutes = max(1, (step.duration?.value ?? 60) / 60)
                return "Walk \(minutes) min"
            }
            if mode == "TRANSIT" {
                let minutes = max(1, (step.duration?.value ?? 60) / 60)
                let vehicleName = step.transitDetails?.line?.vehicle?.name
                let headsign = step.transitDetails?.headsign?.trimmingCharacters(in: .whitespacesAndNewlines)
                let departureStop = step.transitDetails?.departureStop?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let arrivalStop = step.transitDetails?.arrivalStop?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let directionPart = (headsign?.isEmpty == false) ? " toward \(headsign!)" : ""
                if let shortName = step.transitDetails?.line?.shortName, !shortName.isEmpty {
                    let base = if let vehicleName, !vehicleName.isEmpty {
                        "\(shortName) (\(vehicleName)) \(minutes) min"
                    } else {
                        "\(shortName) \(minutes) min"
                    }
                    if let departureStop, let arrivalStop, !departureStop.isEmpty, !arrivalStop.isEmpty {
                        return "\(base)\(directionPart) from \(departureStop) to \(arrivalStop)"
                    }
                    return "\(base)\(directionPart)"
                }
                if let lineName = step.transitDetails?.line?.name, !lineName.isEmpty {
                    let base = if let vehicleName, !vehicleName.isEmpty {
                        "\(lineName) (\(vehicleName)) \(minutes) min"
                    } else {
                        "\(lineName) \(minutes) min"
                    }
                    if let departureStop, let arrivalStop, !departureStop.isEmpty, !arrivalStop.isEmpty {
                        return "\(base)\(directionPart) from \(departureStop) to \(arrivalStop)"
                    }
                    return "\(base)\(directionPart)"
                }
                let base = "Transit \(minutes) min"
                if let departureStop, let arrivalStop, !departureStop.isEmpty, !arrivalStop.isEmpty {
                    return "\(base)\(directionPart) from \(departureStop) to \(arrivalStop)"
                }
                return "\(base)\(directionPart)"
            }
            let minutes = max(1, (step.duration?.value ?? 60) / 60)
            return "\(mode.capitalized) \(minutes) min"
        }.filter { !$0.isEmpty }

        return LiveTransitRoute(
            durationSeconds: leg.duration.value,
            walkingDurationSeconds: walkingSeconds,
            breakdown: segments.isEmpty ? "Transit route available" : segments.joined(separator: " -> "),
            polylineCoordinates: polyline.isEmpty ? [origin, destination] : polyline,
            segments: segments.isEmpty ? ["Transit route available"] : segments
        )
    }

    private func fetchBackendApartments(
        baseURL: URL,
        workplaceName: String,
        workplaceCoordinate: CLLocationCoordinate2D,
        withinMiles: Double
    ) async throws -> ApartmentSearchResult? {
        let endpoint = baseURL.appendingPathComponent("/api/v1/apartments/search")
        let requestBody = BackendApartmentsRequest(
            workplaceName: workplaceName,
            workplaceLat: workplaceCoordinate.latitude,
            workplaceLng: workplaceCoordinate.longitude,
            withinMiles: withinMiles
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let response: BackendApartmentsResponse = try await requestJSON(request: request)
        guard !response.properties.isEmpty else { return nil }

        return ApartmentSearchResult(
            workplaceName: response.workplaceName ?? workplaceName,
            workplaceCoordinate: CLLocationCoordinate2D(
                latitude: response.workplaceLat ?? workplaceCoordinate.latitude,
                longitude: response.workplaceLng ?? workplaceCoordinate.longitude
            ),
            properties: response.properties.map(mapBackendProperty)
        )
    }

    private func fetchBackendTravelStays(
        baseURL: URL,
        cityName: String,
        hubs: [TouristHub]
    ) async throws -> [Property]? {
        let endpoint = baseURL.appendingPathComponent("/api/v1/travel/stays")
        let requestBody = BackendTravelRequest(
            cityName: cityName,
            hubs: hubs.map {
                BackendHubPayload(name: $0.name, lat: $0.coordinate.latitude, lng: $0.coordinate.longitude)
            }
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let response: BackendTravelResponse = try await requestJSON(request: request)
        let mapped = response.properties.map(mapBackendProperty)
        return mapped.isEmpty ? nil : mapped
    }

    private func mapBackendProperty(_ value: BackendProperty) -> Property {
        Property(
            kind: Property.Kind(rawValue: value.kind) ?? .apartment,
            name: value.name,
            coordinate: CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude),
            monthlyRentRange: value.monthlyRentRange,
            nightlyRateRange: value.nightlyRateRange,
            commuteTimeMinutes: value.commuteTimeMinutes,
            walkingMinutes: value.walkingMinutes,
            commuteBreakdown: value.commuteBreakdown,
            websiteURL: URL(string: value.websiteURL) ?? URL(string: "https://maps.google.com")!,
            rating: value.rating,
            ratingReviewCount: value.ratingReviewCount,
            listingSource: Property.ListingSource(rawValue: value.listingSource) ?? .verified,
            touristConnectivityScore: value.touristConnectivityScore,
            polylineCoordinates: value.polylineCoordinates.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
            }.isEmpty ? [CLLocationCoordinate2D(latitude: value.latitude, longitude: value.longitude)] :
                value.polylineCoordinates.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) },
            journeySegments: value.journeySegments ?? []
        )
    }

    private func requestJSON<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await requestJSON(request: request)
    }

    private func requestJSON<T: Decodable>(request: URLRequest) async throws -> T {
        let maxAttempts = 3
        var attempt = 0
        var lastError: Error?

        while attempt < maxAttempts {
            attempt += 1
            do {
                return try await performJSONRequest(request: request)
            } catch let error as URLError where isRetryable(error: error) && attempt < maxAttempts {
                lastError = error
                try? await Task.sleep(nanoseconds: backoffNanos(forAttempt: attempt))
                continue
            } catch let error as TransitServiceError {
                switch error {
                case let .upstreamError(message) where message.contains("HTTP 429") && attempt < maxAttempts:
                    lastError = error
                    try? await Task.sleep(nanoseconds: backoffNanos(forAttempt: attempt))
                    continue
                case let .upstreamError(message) where message.contains("HTTP 5") && attempt < maxAttempts:
                    lastError = error
                    try? await Task.sleep(nanoseconds: backoffNanos(forAttempt: attempt))
                    continue
                default:
                    throw error
                }
            } catch {
                throw error
            }
        }

        if let transitError = lastError as? TransitServiceError {
            throw transitError
        }
        if let urlError = lastError as? URLError {
            throw TransitServiceError.upstreamError("Network error: \(urlError.localizedDescription)")
        }
        throw TransitServiceError.providerUnavailable
    }

    private func performJSONRequest<T: Decodable>(request: URLRequest) async throws -> T {
        var request = request
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TransitServiceError.providerUnavailable
        }
        guard (200...299).contains(http.statusCode) else {
            throw TransitServiceError.upstreamError("HTTP \(http.statusCode)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TransitServiceError.upstreamError("Failed to decode provider response.")
        }
    }

    private func isRetryable(error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private func backoffNanos(forAttempt attempt: Int) -> UInt64 {
        let baseMs = 400
        let jitterMs = Int.random(in: 0...180)
        let factor = Int(pow(2.0, Double(max(0, attempt - 1))))
        let totalMs = min(3000, (baseMs * factor) + jitterMs)
        return UInt64(totalMs) * 1_000_000
    }

    private func estimateMonthlyRent(index: Int, rating: Double?) -> String {
        let base = 1500 + (index * 120)
        let qualityBoost = Int((rating ?? 4.0) * 60)
        let low = base + qualityBoost
        let high = low + 550
        return "$\(low) - $\(high)"
    }

    private func estimateNightlyRate(rating: Double?) -> String {
        let base = 120 + Int((rating ?? 4.0) * 20)
        return "$\(base) - $\(base + 90) / night"
    }

    private func touristConnectivityScore(avgDurationSeconds: Int, avgWalkingSeconds: Int) -> Int {
        let durationPenalty = Double(avgDurationSeconds) / 60.0 * 1.8
        let walkingPenalty = Double(avgWalkingSeconds) / 60.0 * 1.2
        let raw = 100.0 - durationPenalty - walkingPenalty
        return max(0, min(100, Int(raw.rounded())))
    }

    private func centroid(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        guard !coordinates.isEmpty else { return MockData.workplaceCoordinate }
        let sumLat = coordinates.reduce(0.0) { $0 + $1.latitude }
        let sumLon = coordinates.reduce(0.0) { $0 + $1.longitude }
        return CLLocationCoordinate2D(latitude: sumLat / Double(coordinates.count), longitude: sumLon / Double(coordinates.count))
    }

    private func isInAtlantaMarket(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let atlantaCenter = CLLocation(latitude: 33.7490, longitude: -84.3880)
        let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return point.distance(from: atlantaCenter) <= 56_000 // ~35 miles
    }

    private func resolveCityContext(_ cityName: String) async throws -> CityContext {
        let placemarks = try await CLGeocoder().geocodeAddressStringAsync(cityName)
        guard let first = placemarks.first, let coordinate = first.location?.coordinate else {
            throw TransitServiceError.invalidInput("Could not resolve city: \(cityName).")
        }
        let isAtlanta = cityName.caseInsensitiveCompare("Atlanta") == .orderedSame ||
            (first.locality?.caseInsensitiveCompare("Atlanta") == .orderedSame)
        let europeCountryCodes: Set<String> = [
            "AL", "AD", "AT", "BY", "BE", "BA", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE",
            "GR", "HU", "IS", "IE", "IT", "XK", "LV", "LI", "LT", "LU", "MT", "MD", "MC", "ME", "NL",
            "MK", "NO", "PL", "PT", "RO", "RU", "SM", "RS", "SK", "SI", "ES", "SE", "CH", "UA", "GB",
            "VA"
        ]
        let isInEurope = europeCountryCodes.contains(first.isoCountryCode ?? "")
        return CityContext(coordinate: coordinate, isAtlanta: isAtlanta, isInEurope: isInEurope)
    }

    private func discoverTouristHubs(near center: CLLocationCoordinate2D, apiKey: String) async throws -> [TouristHub] {
        let attractions = try await nearbyPlaces(
            location: center,
            radiusMeters: 10_000,
            keyword: "tourist attraction",
            type: "tourist_attraction",
            apiKey: apiKey
        )
        return attractions.prefix(3).map {
            TouristHub(name: $0.name, coordinate: $0.coordinate)
        }
    }

    private func orderHubsSequentially(around center: CLLocationCoordinate2D, hubs: [TouristHub]) -> [TouristHub] {
        guard !hubs.isEmpty else { return [] }
        var unvisited = hubs
        let startIndex = unvisited.enumerated().min(by: { distanceMeters(from: center, to: $0.element.coordinate) < distanceMeters(from: center, to: $1.element.coordinate) })?.offset ?? 0
        var ordered: [TouristHub] = [unvisited.remove(at: startIndex)]

        while !unvisited.isEmpty {
            guard let last = ordered.last else { break }
            let nextIndex = unvisited.enumerated().min(by: {
                distanceMeters(from: last.coordinate, to: $0.element.coordinate) < distanceMeters(from: last.coordinate, to: $1.element.coordinate)
            })?.offset ?? 0
            ordered.append(unvisited.remove(at: nextIndex))
        }
        return ordered
    }

    private func distanceMeters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    private func generateFallbackHubs(near center: CLLocationCoordinate2D) -> [TouristHub] {
        let hub1 = TouristHub(
            name: "City Center Landmark",
            coordinate: center
        )
        let hub2 = TouristHub(
            name: "Historic District",
            coordinate: CLLocationCoordinate2D(latitude: center.latitude + 0.015, longitude: center.longitude - 0.01)
        )
        let hub3 = TouristHub(
            name: "Main Museum Quarter",
            coordinate: CLLocationCoordinate2D(latitude: center.latitude - 0.012, longitude: center.longitude + 0.014)
        )
        return [hub1, hub2, hub3]
    }

    private func estimatedRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> LiveTransitRoute {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        let distanceMeters = fromLocation.distance(from: toLocation)

        // Approximate urban transit speed and first/last mile walking assumptions.
        let transitSeconds = Int((distanceMeters / 7.8).rounded()) // ~28km/h
        let walkingSeconds = max(180, Int((distanceMeters * 0.18 / 1.35).rounded()))
        let total = max(300, transitSeconds + walkingSeconds)

        return LiveTransitRoute(
            durationSeconds: total,
            walkingDurationSeconds: walkingSeconds,
            breakdown: "Transit estimate (live route unavailable)",
            polylineCoordinates: [from, to],
            segments: ["Walk 4 min", "Transit estimate", "Walk 3 min"]
        )
    }

    private func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        let bytes = Array(encoded.utf8)
        var index = 0
        var lat = 0
        var lng = 0

        while index < bytes.count {
            var b: Int
            var shift = 0
            var result = 0
            repeat {
                b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
            } while b >= 0x20 && index < bytes.count
            let dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += dlat

            shift = 0
            result = 0
            repeat {
                b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
            } while b >= 0x20 && index < bytes.count
            let dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lng += dlng

            coordinates.append(
                CLLocationCoordinate2D(latitude: Double(lat) / 1e5, longitude: Double(lng) / 1e5)
            )
        }

        return coordinates
    }
}

private struct CityContext {
    let coordinate: CLLocationCoordinate2D
    let isAtlanta: Bool
    let isInEurope: Bool
}

private enum RuntimeConfig {
    private static func parseBoolean(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y":
            return true
        case "0", "false", "no", "n":
            return false
        default:
            return nil
        }
    }

    static var googleAPIKey: String? {
        if let env = ProcessInfo.processInfo.environment["COMMUTEFLOW_GOOGLE_API_KEY"], !env.isEmpty {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "COMMUTEFLOW_GOOGLE_API_KEY") as? String, !plist.isEmpty {
            return plist
        }
        return nil
    }

    static var backendBaseURL: URL? {
        if let env = ProcessInfo.processInfo.environment["COMMUTEFLOW_BACKEND_BASE_URL"],
           let url = URL(string: env),
           !env.isEmpty {
            return url
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "COMMUTEFLOW_BACKEND_BASE_URL") as? String,
           let url = URL(string: plist),
           !plist.isEmpty {
            return url
        }
        return nil
    }

    static var shouldUseDirectGoogle: Bool {
#if DEBUG
        // In Debug we default to ON when key exists, unless explicitly disabled in env.
        if let envDecision = parseBoolean(ProcessInfo.processInfo.environment["COMMUTEFLOW_ALLOW_DIRECT_GOOGLE"]) {
            return envDecision
        }
        return true
#else
        // Production-safe default: disable direct provider calls from the client app.
        if let envDecision = parseBoolean(ProcessInfo.processInfo.environment["COMMUTEFLOW_ALLOW_DIRECT_GOOGLE"]) {
            return envDecision
        }
        if let plistString = Bundle.main.object(forInfoDictionaryKey: "COMMUTEFLOW_ALLOW_DIRECT_GOOGLE") as? String,
           let plistDecision = parseBoolean(plistString) {
            return plistDecision
        }
        if let plistBool = Bundle.main.object(forInfoDictionaryKey: "COMMUTEFLOW_ALLOW_DIRECT_GOOGLE") as? Bool {
            return plistBool
        }
        return false
#endif
    }
}

private struct BackendApartmentsRequest: Encodable {
    let workplaceName: String
    let workplaceLat: Double
    let workplaceLng: Double
    let withinMiles: Double
}

private struct BackendTravelRequest: Encodable {
    let cityName: String
    let hubs: [BackendHubPayload]
}

private struct BackendHubPayload: Encodable {
    let name: String
    let lat: Double
    let lng: Double
}

private struct BackendApartmentsResponse: Decodable {
    let workplaceName: String?
    let workplaceLat: Double?
    let workplaceLng: Double?
    let properties: [BackendProperty]
}

private struct BackendTravelResponse: Decodable {
    let properties: [BackendProperty]
}

private struct BackendProperty: Decodable {
    let kind: String
    let name: String
    let latitude: Double
    let longitude: Double
    let monthlyRentRange: String?
    let nightlyRateRange: String?
    let commuteTimeMinutes: Int
    let walkingMinutes: Int
    let commuteBreakdown: String
    let websiteURL: String
    let rating: Double?
    let ratingReviewCount: Int?
    let listingSource: String
    let touristConnectivityScore: Int?
    let polylineCoordinates: [BackendCoordinate]
    let journeySegments: [String]?
}

private struct BackendCoordinate: Decodable {
    let lat: Double
    let lng: Double
}

private struct LivePlace {
    let placeID: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let rating: Double?
    let userRatingsTotal: Int?
    let googleURL: URL?
}

private struct LiveTransitRoute {
    let durationSeconds: Int
    let walkingDurationSeconds: Int
    let breakdown: String
    let polylineCoordinates: [CLLocationCoordinate2D]
    let segments: [String]
}

private struct GooglePlacesNearbyResponse: Decodable {
    let status: String
    let results: [GooglePlaceResult]
}

private struct GooglePlaceResult: Decodable {
    let placeID: String
    let name: String
    let geometry: GoogleGeometry
    let rating: Double?
    let userRatingsTotal: Int?

    enum CodingKeys: String, CodingKey {
        case placeID = "place_id"
        case name
        case geometry
        case rating
        case userRatingsTotal = "user_ratings_total"
    }
}

private struct GoogleGeometry: Decodable {
    let location: GoogleCoordinate
}

private struct GoogleCoordinate: Decodable {
    let lat: Double
    let lng: Double
}

private struct GooglePlaceDetailsResponse: Decodable {
    let status: String
    let result: GooglePlaceDetailsResult?
}

private struct GooglePlaceDetailsResult: Decodable {
    let website: String?
    let url: String?
}

private struct GoogleDirectionsResponse: Decodable {
    let status: String
    let routes: [GoogleDirectionRoute]
}

private struct GoogleDirectionRoute: Decodable {
    let overviewPolyline: GooglePolyline
    let legs: [GoogleDirectionLeg]

    enum CodingKeys: String, CodingKey {
        case overviewPolyline = "overview_polyline"
        case legs
    }
}

private struct GooglePolyline: Decodable {
    let points: String
}

private struct GoogleDirectionLeg: Decodable {
    let duration: GoogleDuration
    let steps: [GoogleDirectionStep]
}

private struct GoogleDuration: Decodable {
    let value: Int
}

private struct GoogleDirectionStep: Decodable {
    let travelMode: String
    let duration: GoogleDuration?
    let transitDetails: GoogleTransitDetails?

    enum CodingKeys: String, CodingKey {
        case travelMode = "travel_mode"
        case duration
        case transitDetails = "transit_details"
    }
}

private struct GoogleTransitDetails: Decodable {
    let line: GoogleTransitLine?
    let headsign: String?
    let departureStop: GoogleTransitStop?
    let arrivalStop: GoogleTransitStop?

    enum CodingKeys: String, CodingKey {
        case line
        case headsign
        case departureStop = "departure_stop"
        case arrivalStop = "arrival_stop"
    }
}

private struct GoogleTransitLine: Decodable {
    let shortName: String?
    let name: String?
    let vehicle: GoogleTransitVehicle?

    enum CodingKeys: String, CodingKey {
        case shortName = "short_name"
        case name
        case vehicle
    }
}

private struct GoogleTransitVehicle: Decodable {
    let name: String?
}

private struct GoogleTransitStop: Decodable {
    let name: String?
}

private extension CLGeocoder {
    func geocodeAddressStringAsync(_ address: String) async throws -> [CLPlacemark] {
        try await withCheckedThrowingContinuation { continuation in
            self.geocodeAddressString(address) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: placemarks ?? [])
            }
        }
    }
}

private actor TransitCache {
    private var apartmentResults: [String: ApartmentSearchResult] = [:]

    func apartmentResult(for key: String) -> ApartmentSearchResult? {
        apartmentResults[key]
    }

    func setApartmentResult(_ value: ApartmentSearchResult, for key: String) {
        apartmentResults[key] = value
    }
}

enum MockData {
    static let workplaceName = "NCR Headquarters, Spring St NW"
    static let cityName = "Atlanta"

    static let workplaceCoordinate = CLLocationCoordinate2D(
        latitude: 33.7826,
        longitude: -84.3888
    )

    static let touristHubs: [TouristHub] = [
        TouristHub(
            name: "Ponce City Market",
            coordinate: CLLocationCoordinate2D(latitude: 33.7725, longitude: -84.3659)
        ),
        TouristHub(
            name: "Georgia Aquarium",
            coordinate: CLLocationCoordinate2D(latitude: 33.7634, longitude: -84.3951)
        ),
        TouristHub(
            name: "Mercedes-Benz Stadium",
            coordinate: CLLocationCoordinate2D(latitude: 33.7554, longitude: -84.4008)
        )
    ]

    static let atlantaApartments: [Property] = [
        Property(
            kind: .apartment,
            name: "The Standard at Midtown",
            coordinate: CLLocationCoordinate2D(latitude: 33.7802, longitude: -84.3873),
            monthlyRentRange: "$1,950 - $2,550",
            nightlyRateRange: nil,
            commuteTimeMinutes: 8,
            walkingMinutes: 8,
            commuteBreakdown: "8 min walk",
            websiteURL: URL(string: "https://thestandardatlanta.landmark-properties.com/")!,
            rating: 4.3,
            ratingReviewCount: 246,
            listingSource: .verified,
            touristConnectivityScore: nil,
            polylineCoordinates: [
                CLLocationCoordinate2D(latitude: 33.7802, longitude: -84.3873),
                CLLocationCoordinate2D(latitude: 33.7814, longitude: -84.3880),
                workplaceCoordinate
            ],
            journeySegments: ["Walk 8 min"]
        ),
        Property(
            kind: .apartment,
            name: "Skyhouse Buckhead",
            coordinate: CLLocationCoordinate2D(latitude: 33.8451, longitude: -84.3709),
            monthlyRentRange: "$1,800 - $2,400",
            nightlyRateRange: nil,
            commuteTimeMinutes: 22,
            walkingMinutes: 8,
            commuteBreakdown: "6 min walk -> MARTA Red Line -> 2 min walk",
            websiteURL: URL(string: "https://www.skyhousebuckhead.com/")!,
            rating: 4.2,
            ratingReviewCount: 331,
            listingSource: .verified,
            touristConnectivityScore: nil,
            polylineCoordinates: [
                CLLocationCoordinate2D(latitude: 33.8451, longitude: -84.3709),
                CLLocationCoordinate2D(latitude: 33.8487, longitude: -84.3670),
                CLLocationCoordinate2D(latitude: 33.7815, longitude: -84.3860),
                workplaceCoordinate
            ],
            journeySegments: ["Walk 6 min", "MARTA Red Line (Subway) 14 min", "Walk 2 min"]
        )
    ]

    static let atlantaTouristStays: [Property] = [
        Property(
            kind: .hotel,
            name: "Hyatt Centric Midtown Atlanta",
            coordinate: CLLocationCoordinate2D(latitude: 33.7820, longitude: -84.3842),
            monthlyRentRange: nil,
            nightlyRateRange: "$210 - $290 / night",
            commuteTimeMinutes: 15,
            walkingMinutes: 6,
            commuteBreakdown: "4 min walk -> MARTA Red/Gold Line -> 2 min walk",
            websiteURL: URL(string: "https://www.hyatt.com/en-US/hotel/georgia/hyatt-centric-midtown-atlanta/atlct")!,
            rating: 4.4,
            ratingReviewCount: 1180,
            listingSource: .verified,
            touristConnectivityScore: 92,
            polylineCoordinates: [
                CLLocationCoordinate2D(latitude: 33.7820, longitude: -84.3842),
                CLLocationCoordinate2D(latitude: 33.7818, longitude: -84.3860),
                CLLocationCoordinate2D(latitude: 33.7634, longitude: -84.3951)
            ],
            journeySegments: ["Walk 4 min", "MARTA Red Line (Subway) 9 min", "Walk 2 min"]
        ),
        Property(
            kind: .airbnb,
            name: "Old Fourth Ward Loft (Airbnb)",
            coordinate: CLLocationCoordinate2D(latitude: 33.7667, longitude: -84.3665),
            monthlyRentRange: nil,
            nightlyRateRange: "$145 - $190 / night",
            commuteTimeMinutes: 18,
            walkingMinutes: 10,
            commuteBreakdown: "7 min walk -> Streetcar/MARTA transfer -> 3 min walk",
            websiteURL: URL(string: "https://www.airbnb.com")!,
            rating: 4.8,
            ratingReviewCount: 94,
            listingSource: .verified,
            touristConnectivityScore: 84,
            polylineCoordinates: [
                CLLocationCoordinate2D(latitude: 33.7667, longitude: -84.3665),
                CLLocationCoordinate2D(latitude: 33.7678, longitude: -84.3735),
                CLLocationCoordinate2D(latitude: 33.7634, longitude: -84.3951)
            ],
            journeySegments: ["Walk 7 min", "Atlanta Streetcar 8 min", "Walk 3 min"]
        ),
        Property(
            kind: .hotel,
            name: "Omni Atlanta Hotel",
            coordinate: CLLocationCoordinate2D(latitude: 33.7575, longitude: -84.3963),
            monthlyRentRange: nil,
            nightlyRateRange: "$230 - $320 / night",
            commuteTimeMinutes: 11,
            walkingMinutes: 5,
            commuteBreakdown: "3 min walk -> Direct MARTA stop -> 2 min walk",
            websiteURL: URL(string: "https://www.omnihotels.com/hotels/atlanta-centennial-park")!,
            rating: 4.4,
            ratingReviewCount: 3876,
            listingSource: .verified,
            touristConnectivityScore: 95,
            polylineCoordinates: [
                CLLocationCoordinate2D(latitude: 33.7575, longitude: -84.3963),
                CLLocationCoordinate2D(latitude: 33.7600, longitude: -84.3969),
                CLLocationCoordinate2D(latitude: 33.7634, longitude: -84.3951)
            ],
            journeySegments: ["Walk 3 min", "MARTA Blue/Green Line (Subway) 6 min", "Walk 2 min"]
        )
    ]

    static func generatedApartments(near workplace: CLLocationCoordinate2D) -> [Property] {
        let templates: [(name: String, rent: String, commute: Int, walking: Int, breakdown: String, rating: Double, reviews: Int)] = [
            ("Westline Transit Lofts", "$1,650 - $2,150", 16, 7, "5 min walk -> Metro transit -> 2 min walk", 4.1, 128),
            ("Station Square Residences", "$1,820 - $2,480", 19, 9, "7 min walk -> Rapid transit -> 3 min walk", 4.3, 204),
            ("CityLink Apartments", "$1,540 - $1,980", 21, 10, "8 min walk -> Transit connector -> 3 min walk", 4.0, 96),
            ("Greenline Flats", "$1,730 - $2,260", 14, 6, "4 min walk -> Direct line -> 2 min walk", 4.4, 172)
        ]

        let offsets: [(latMeters: Double, lonMeters: Double)] = [
            (900, -700),
            (-1300, 1200),
            (1800, 300),
            (-700, -1500)
        ]

        return zip(templates, offsets).map { template, offset in
            let propertyCoordinate = offsetCoordinate(
                from: workplace,
                latMeters: offset.latMeters,
                lonMeters: offset.lonMeters
            )
            return Property(
                kind: .apartment,
                name: template.name,
                coordinate: propertyCoordinate,
                monthlyRentRange: template.rent,
                nightlyRateRange: nil,
                commuteTimeMinutes: template.commute,
                walkingMinutes: template.walking,
                commuteBreakdown: template.breakdown,
                websiteURL: URL(string: "https://www.apartments.com/")!,
                rating: template.rating,
                ratingReviewCount: template.reviews,
                listingSource: .generated,
                touristConnectivityScore: nil,
                polylineCoordinates: [
                    propertyCoordinate,
                    offsetCoordinate(from: propertyCoordinate, latMeters: offset.latMeters * -0.25, lonMeters: offset.lonMeters * -0.25),
                    workplace
                ],
                journeySegments: template.breakdown
                    .components(separatedBy: "->")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            )
        }
    }

    private static func offsetCoordinate(
        from coordinate: CLLocationCoordinate2D,
        latMeters: Double,
        lonMeters: Double
    ) -> CLLocationCoordinate2D {
        let latDelta = latMeters / 111_111.0
        let lonDelta = lonMeters / (111_111.0 * max(cos(coordinate.latitude * .pi / 180.0), 0.01))
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + latDelta,
            longitude: coordinate.longitude + lonDelta
        )
    }
}
