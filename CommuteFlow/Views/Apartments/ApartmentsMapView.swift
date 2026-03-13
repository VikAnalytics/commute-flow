import MapKit
import SwiftUI

struct ApartmentsMapView: View {
    let workplaceName: String
    let workplaceCoordinate: CLLocationCoordinate2D
    let properties: [Property]

    @State private var position: MapCameraPosition

    init(workplaceName: String, workplaceCoordinate: CLLocationCoordinate2D, properties: [Property]) {
        self.workplaceName = workplaceName
        self.workplaceCoordinate = workplaceCoordinate
        self.properties = properties
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 33.792, longitude: -84.382),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
        _position = State(initialValue: .region(initialRegion))
    }

    var body: some View {
        Map(position: $position) {
            Annotation(workplaceName, coordinate: workplaceCoordinate) {
                VStack(spacing: 4) {
                    Image(systemName: "briefcase.fill")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.blue)
                        .clipShape(Circle())
                    Text("Work")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }

            ForEach(properties) { property in
                Marker(property.name, coordinate: property.coordinate)
                    .tint(property.kind == .apartment ? .teal : .orange)
                MapPolyline(property.routePolyline)
                    .stroke(.blue.opacity(0.7), lineWidth: 4)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }
}
