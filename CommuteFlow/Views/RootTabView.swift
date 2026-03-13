import SwiftData
import SwiftUI

struct RootTabView: View {
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var body: some View {
        TabView {
            ApartmentsView(transitService: dependencies.transitService)
                .tabItem {
                    Label("Apartments", systemImage: "building.2.crop.circle")
                }

            TravelView(transitService: dependencies.transitService)
                .tabItem {
                    Label("Travel", systemImage: "tram.fill.tunnel")
                }

            SavedPropertiesView()
                .tabItem {
                    Label("Saved", systemImage: "heart.fill")
                }
        }
    }
}

struct SavedPropertiesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedProperty.savedAt, order: .reverse) private var savedProperties: [SavedProperty]

    var body: some View {
        NavigationStack {
            Group {
                if savedProperties.isEmpty {
                    ContentUnavailableView(
                        "No Saved Properties",
                        systemImage: "heart",
                        description: Text("Tap the heart icon on any property card to save it here.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(savedProperties, id: \.propertyKey) { saved in
                                PropertyCardView(
                                    property: saved.property,
                                    isSaved: true,
                                    onToggleSaved: { modelContext.delete(saved) }
                                )
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Saved")
        }
    }
}
