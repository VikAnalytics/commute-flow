import MapKit
import SwiftUI

struct ApartmentsView: View {
    @StateObject private var viewModel: ApartmentSearchViewModel

    init(transitService: TransitProviding) {
        _viewModel = StateObject(
            wrappedValue: ApartmentSearchViewModel(transitService: transitService)
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ApartmentsMapView(
                        workplaceName: viewModel.workplaceName,
                        workplaceCoordinate: viewModel.workplaceCoordinate,
                        properties: viewModel.sortedApartments
                    )
                    .frame(height: geometry.size.height * 0.48)

                    ApartmentsListPanel(viewModel: viewModel)
                        .frame(maxHeight: .infinity)
                        .background(.thinMaterial)
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("CommuteFlow")
            .task {
                if viewModel.loadState == .idle {
                    await viewModel.loadApartments()
                }
            }
        }
    }
}
