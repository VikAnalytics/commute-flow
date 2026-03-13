import MapKit
import SwiftUI
import SwiftData

struct TravelView: View {
    @StateObject private var viewModel: TravelConnectivityViewModel
    @Environment(\.modelContext) private var modelContext
    @Query private var savedProperties: [SavedProperty]

    private var savedKeys: Set<String> {
        Set(savedProperties.map(\.propertyKey))
    }

    init(transitService: TransitProviding) {
        _viewModel = StateObject(
            wrappedValue: TravelConnectivityViewModel(transitService: transitService)
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    TravelMapView(hubs: viewModel.touristHubs, stays: viewModel.sortedStays)
                        .frame(height: geometry.size.height * 0.48)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("City Name")
                                    .font(.subheadline.weight(.semibold))
                                TextField("Enter city", text: $viewModel.cityName)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        Task {
                                            await viewModel.load()
                                        }
                                    }

                                Text("Major Hubs: Ponce City Market, Georgia Aquarium, Mercedes-Benz Stadium")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            .padding(.top, 14)

                            switch viewModel.loadState {
                            case .idle, .loaded:
                                ForEach(viewModel.sortedStays) { stay in
                                    PropertyCardView(
                                        property: stay,
                                        isSaved: savedKeys.contains(stay.stableKey),
                                        onToggleSaved: { toggleSaved(for: stay) }
                                    )
                                        .padding(.horizontal)
                                }
                            case .loading:
                                ProgressView("Calculating tourist connectivity...")
                                    .padding(.horizontal)
                                    .padding(.top, 12)
                            case let .failed(message):
                                ContentUnavailableView {
                                    Label("Unable to Load Stays", systemImage: "exclamationmark.triangle")
                                } description: {
                                    Text(message)
                                } actions: {
                                    Button("Retry") {
                                        Task {
                                            await viewModel.load()
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .background(.thinMaterial)
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("Travel Connectivity")
            .task {
                if viewModel.loadState == .idle {
                    await viewModel.load()
                }
            }
        }
    }

    private func toggleSaved(for property: Property) {
        if let existing = savedProperties.first(where: { $0.propertyKey == property.stableKey }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(SavedProperty(from: property))
        }
    }
}
