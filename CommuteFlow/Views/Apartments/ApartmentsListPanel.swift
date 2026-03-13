import MapKit
import SwiftUI
import SwiftData

struct ApartmentsListPanel: View {
    @ObservedObject var viewModel: ApartmentSearchViewModel
    @StateObject private var autocomplete = AddressAutocompleteViewModel()
    @State private var selectedApartmentID: Property.ID?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecentSearch.lastUsedAt, order: .reverse) private var recentSearches: [RecentSearch]
    @Query private var savedProperties: [SavedProperty]

    private var savedKeys: Set<String> {
        Set(savedProperties.map(\.propertyKey))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Workplace Address")
                        .font(.subheadline.weight(.semibold))
                    TextField(
                        "Enter workplace address",
                        text: Binding(
                            get: { viewModel.workplaceAddress },
                            set: { newValue in
                                viewModel.workplaceAddress = newValue
                                autocomplete.updateQuery(newValue)
                            }
                        )
                    )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task {
                                await viewModel.loadApartments()
                                autocomplete.clear()
                                saveRecentSearchIfNeeded(viewModel.workplaceAddress)
                            }
                        }

                    if !autocomplete.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(autocomplete.suggestions.prefix(5), id: \.self) { suggestion in
                                Button {
                                    viewModel.workplaceAddress = suggestion
                                    autocomplete.clear()
                                    Task {
                                        await viewModel.loadApartments()
                                        saveRecentSearchIfNeeded(suggestion)
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "mappin.and.ellipse")
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
                    } else if autocomplete.shouldShowRecents, !recentSearches.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Searches")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(recentSearches.prefix(5), id: \.query) { search in
                                Button {
                                    viewModel.workplaceAddress = search.query
                                    Task {
                                        await viewModel.loadApartments()
                                        saveRecentSearchIfNeeded(search.query)
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundStyle(.secondary)
                                        Text(search.query)
                                            .font(.subheadline)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack {
                        Text("Sort")
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        Picker("Sort By", selection: $viewModel.sortOption) {
                            ForEach(PropertySortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max Commute")
                                .font(.footnote.weight(.semibold))
                            Spacer()
                            Text("\(Int(viewModel.maxCommuteMinutes.rounded())) min")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $viewModel.maxCommuteMinutes, in: 10...60, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max Monthly Rent")
                                .font(.footnote.weight(.semibold))
                            Spacer()
                            Text("$\(Int(viewModel.maxMonthlyRent.rounded()))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $viewModel.maxMonthlyRent, in: 1200...4000, step: 50)
                    }

                    if viewModel.hasCustomFilters {
                        VStack(alignment: .leading, spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    if viewModel.sortOption != ApartmentSearchViewModel.defaultSortOption {
                                        filterChip(text: viewModel.sortOption.rawValue)
                                    }

                                    if Int(viewModel.maxCommuteMinutes.rounded()) != Int(ApartmentSearchViewModel.defaultMaxCommuteMinutes.rounded()) {
                                        filterChip(text: "<= \(Int(viewModel.maxCommuteMinutes.rounded())) min")
                                    }

                                    if Int(viewModel.maxMonthlyRent.rounded()) != Int(ApartmentSearchViewModel.defaultMaxMonthlyRent.rounded()) {
                                        filterChip(text: "<= $\(Int(viewModel.maxMonthlyRent.rounded()))")
                                    }
                                }
                            }

                            HStack {
                                Spacer()
                                Button("Reset Filters") {
                                    viewModel.resetFilters()
                                }
                                .font(.footnote.weight(.semibold))
                            }
                        }
                    }

                }
                .padding(.horizontal)
                .padding(.top, 14)

                switch viewModel.loadState {
                case .idle, .loaded:
                    if viewModel.sortedApartments.isEmpty {
                        ContentUnavailableView {
                            Label("No Apartments Match Filters", systemImage: "slider.horizontal.3")
                        } description: {
                            Text("Try increasing max commute or max monthly rent.")
                        }
                        .padding(.horizontal)
                    } else {
                        Text("Tip: Tap a card to view route details.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        ForEach(viewModel.sortedApartments) { apartment in
                            PropertyCardView(
                                property: apartment,
                                isSaved: savedKeys.contains(apartment.stableKey),
                                showJourneyDetails: selectedApartmentID == apartment.id,
                                showCommuteBreakdownInline: selectedApartmentID == apartment.id,
                                onToggleSaved: { toggleSaved(for: apartment) }
                            )
                                .onTapGesture {
                                    selectedApartmentID = (selectedApartmentID == apartment.id) ? nil : apartment.id
                                }
                                .padding(.horizontal)
                        }
                    }
                case .loading:
                    ProgressView("Finding apartments near transit...")
                        .padding(.horizontal)
                        .padding(.top, 12)
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Unable to Load Apartments", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") {
                            Task {
                                await viewModel.loadApartments()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func saveRecentSearchIfNeeded(_ query: String) {
        guard case .loaded = viewModel.loadState else { return }
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        if let existing = recentSearches.first(where: { $0.query.caseInsensitiveCompare(normalized) == .orderedSame }) {
            existing.lastUsedAt = .now
        } else {
            modelContext.insert(RecentSearch(query: normalized))
        }
    }

    private func toggleSaved(for property: Property) {
        if let existing = savedProperties.first(where: { $0.propertyKey == property.stableKey }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(SavedProperty(from: property))
        }
    }

    @ViewBuilder
    private func filterChip(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
            )
    }
}

@MainActor
final class AddressAutocompleteViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [String] = []

    private let completer = MKLocalSearchCompleter()
    private(set) var latestQuery: String = ""

    var shouldShowRecents: Bool {
        latestQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateQuery(_ query: String) {
        latestQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            suggestions = []
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        suggestions = []
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let values = completer.results.map { result in
            let subtitle = result.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return subtitle.isEmpty ? result.title : "\(result.title), \(subtitle)"
        }
        suggestions = Array(NSOrderedSet(array: values).array as? [String] ?? [])
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
