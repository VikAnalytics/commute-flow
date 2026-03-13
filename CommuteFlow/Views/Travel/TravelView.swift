import MapKit
import SwiftUI
import SwiftData

struct TravelView: View {
    @StateObject private var viewModel: TravelConnectivityViewModel
    @StateObject private var cityAutocomplete = CityAutocompleteViewModel()
    @State private var selectedStayID: Property.ID?
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
                    TravelMapView(
                        cityCoordinate: viewModel.cityCoordinate,
                        hubs: viewModel.touristHubs,
                        stays: viewModel.sortedStays,
                        selectedStayID: $selectedStayID
                    )
                        .frame(height: geometry.size.height * 0.48)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("City Name")
                                    .font(.subheadline.weight(.semibold))
                                TextField(
                                    "Enter city",
                                    text: Binding(
                                        get: { viewModel.cityName },
                                        set: { newValue in
                                            viewModel.cityName = newValue
                                            cityAutocomplete.updateQuery(newValue)
                                        }
                                    )
                                )
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        Task {
                                            await viewModel.load()
                                            cityAutocomplete.clear()
                                        }
                                    }

                                if !cityAutocomplete.suggestions.isEmpty {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(cityAutocomplete.suggestions.prefix(6), id: \.self) { suggestion in
                                            Button {
                                                viewModel.cityName = suggestion
                                                cityAutocomplete.clear()
                                                Task { await viewModel.load() }
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: "building.2.crop.circle")
                                                        .foregroundStyle(.secondary)
                                                    Text(suggestion)
                                                        .font(.subheadline)
                                                        .multilineTextAlignment(.leading)
                                                    Spacer()
                                                }
                                                .padding(.vertical, 10)
                                            }
                                            .buttonStyle(.plain)

                                            Divider()
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color(uiColor: .secondarySystemBackground))
                                    )
                                }

                                if viewModel.touristHubs.isEmpty {
                                    Text("Tourist hubs are auto-discovered for the selected city.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Major Hubs (ordered)")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        ForEach(Array(viewModel.touristHubs.enumerated()), id: \.element.id) { index, hub in
                                            Text("\(index + 1). \(hub.name)")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                HStack {
                                    Text("Sort")
                                        .font(.footnote.weight(.semibold))
                                    Spacer()
                                    Picker("Sort", selection: $viewModel.sortOption) {
                                        ForEach(TravelConnectivityViewModel.TravelSortOption.allCases) { option in
                                            Text(option.rawValue).tag(option)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Min Tourist Score")
                                            .font(.footnote.weight(.semibold))
                                        Spacer()
                                        Text("\(Int(viewModel.minTouristScore.rounded()))")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(value: $viewModel.minTouristScore, in: 0...100, step: 1)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Max Price / night")
                                            .font(.footnote.weight(.semibold))
                                        Spacer()
                                        Text("$\(Int(viewModel.maxNightlyPrice.rounded()))")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(value: $viewModel.maxNightlyPrice, in: 80...600, step: 10)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 14)

                            switch viewModel.loadState {
                            case .idle, .loaded:
                                if viewModel.sortedStays.isEmpty {
                                    ContentUnavailableView {
                                        Label("No Stays Match Filters", systemImage: "slider.horizontal.3")
                                    } description: {
                                        Text("Try lowering minimum tourist score or increasing max nightly price.")
                                    }
                                    .padding(.horizontal)
                                } else {
                                    Text("Tip: Tap a card to view route details.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal)
                                }

                                ForEach(viewModel.sortedStays) { stay in
                                    PropertyCardView(
                                        property: stay,
                                        isSaved: savedKeys.contains(stay.stableKey),
                                        showJourneyDetails: selectedStayID == stay.id,
                                        showCommuteBreakdownInline: selectedStayID == stay.id,
                                        onToggleSaved: { toggleSaved(for: stay) }
                                    )
                                        .onTapGesture {
                                            selectedStayID = (selectedStayID == stay.id) ? nil : stay.id
                                        }
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

@MainActor
final class CityAutocompleteViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [String] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
    }

    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        suggestions = []
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let cityLikeValues = completer.results.compactMap { result -> String? in
            let parts = [result.title, result.subtitle]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: ", ")
        }
        suggestions = Array(NSOrderedSet(array: cityLikeValues).array as? [String] ?? [])
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
