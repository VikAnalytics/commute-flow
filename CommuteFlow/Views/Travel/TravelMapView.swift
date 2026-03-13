import MapKit
import SwiftUI

struct TravelMapView: View {
    let hubs: [TouristHub]
    let stays: [Property]

    @State private var position: MapCameraPosition

    init(hubs: [TouristHub], stays: [Property]) {
        self.hubs = hubs
        self.stays = stays
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 33.765, longitude: -84.389),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
        _position = State(initialValue: .region(initialRegion))
    }

    var body: some View {
        Map(position: $position) {
            ForEach(hubs) { hub in
                Annotation(hub.name, coordinate: hub.coordinate) {
                    VStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.red)
                            .clipShape(Circle())
                        Text("Hub")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                }
            }

            ForEach(stays) { stay in
                Marker(stay.name, coordinate: stay.coordinate)
                    .tint(.mint)
                MapPolyline(stay.routePolyline)
                    .stroke(.purple.opacity(0.75), lineWidth: 4)
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
    }
}
