import MapKit
import SwiftUI

struct TravelMapView: View {
    let cityCoordinate: CLLocationCoordinate2D
    let hubs: [TouristHub]
    let stays: [Property]
    @Binding var selectedStayID: Property.ID?

    @State private var position: MapCameraPosition

    init(
        cityCoordinate: CLLocationCoordinate2D,
        hubs: [TouristHub],
        stays: [Property],
        selectedStayID: Binding<Property.ID?>
    ) {
        self.cityCoordinate = cityCoordinate
        self.hubs = hubs
        self.stays = stays
        _selectedStayID = selectedStayID
        let initialRegion = MKCoordinateRegion(
            center: cityCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
        _position = State(initialValue: .region(initialRegion))
    }

    var body: some View {
        Map(position: $position, selection: $selectedStayID) {
            ForEach(hubs) { hub in
                Annotation(hub.name, coordinate: hub.coordinate) {
                    VStack(spacing: 4) {
                        Image(systemName: "star.circle.fill")
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.red)
                            .clipShape(Circle())
                        Text(hub.name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                }
            }

            ForEach(stays) { stay in
                Annotation(stay.name, coordinate: stay.coordinate) {
                    VStack(spacing: 4) {
                        Image(systemName: "bed.double.circle.fill")
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(selectedStayID == stay.id ? .blue : .mint)
                            .clipShape(Circle())
                        Text("Stay")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                }
                .tag(stay.id)
            }

            if let selectedStay = stays.first(where: { $0.id == selectedStayID }), !hubs.isEmpty {
                let waypoints = [selectedStay.coordinate] + hubs.map(\.coordinate)
                ForEach(Array(waypoints.dropLast().enumerated()), id: \.offset) { index, origin in
                    let destination = waypoints[index + 1]
                    let legLine = MKPolyline(coordinates: [origin, destination], count: 2)
                    MapPolyline(legLine)
                        .stroke(index == 0 ? .blue.opacity(0.95) : .purple.opacity(0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }

                if !selectedStay.polylineCoordinates.isEmpty {
                    let propertyLine = MKPolyline(
                        coordinates: selectedStay.polylineCoordinates,
                        count: selectedStay.polylineCoordinates.count
                    )
                    MapPolyline(propertyLine)
                        .stroke(.teal.opacity(0.8), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [8, 6]))
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .onAppear {
            if selectedStayID == nil, let first = stays.first {
                selectedStayID = first.id
            }
            recenterMap()
        }
        .onChange(of: hubs.count) { _, _ in
            recenterMap()
        }
        .onChange(of: cityCoordinate.latitude) { _, _ in
            recenterMap()
        }
        .onChange(of: cityCoordinate.longitude) { _, _ in
            recenterMap()
        }
        .onChange(of: selectedStayID) { _, _ in
            recenterMap()
        }
    }

    private func recenterMap() {
        if let selectedStay = stays.first(where: { $0.id == selectedStayID }) {
            let focusedCoordinates = [selectedStay.coordinate] + hubs.map(\.coordinate)
            if !focusedCoordinates.isEmpty {
                position = .region(boundingRegion(for: focusedCoordinates))
                return
            }
        }

        let allCoordinates = [cityCoordinate] + hubs.map(\.coordinate) + stays.map(\.coordinate)
        if !allCoordinates.isEmpty {
            position = .region(boundingRegion(for: allCoordinates))
        }
    }

    private func boundingRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min() ?? cityCoordinate.latitude
        let maxLat = lats.max() ?? cityCoordinate.latitude
        let minLon = lons.min() ?? cityCoordinate.longitude
        let maxLon = lons.max() ?? cityCoordinate.longitude

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )
        let latDelta = max(0.08, (maxLat - minLat) * 1.6)
        let lonDelta = max(0.08, (maxLon - minLon) * 1.6)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }
}
