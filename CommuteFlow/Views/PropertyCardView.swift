import SwiftUI

struct PropertyCardView: View {
    let property: Property
    var isSaved: Bool = false
    var showJourneyDetails: Bool = false
    var showCommuteBreakdownInline: Bool = true
    var onToggleSaved: (() -> Void)?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(property.name)
                    .font(.headline)
                Spacer()
                Text(property.priceDisplay)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let onToggleSaved {
                    Button {
                        onToggleSaved()
                    } label: {
                        Image(systemName: isSaved ? "heart.fill" : "heart")
                            .foregroundStyle(isSaved ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSaved ? "Remove from saved" : "Save property")
                }
            }

            Text(property.listingSourceBadgeTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(property.listingSource == .verified ? .green : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(property.listingSource == .verified ? .green.opacity(0.14) : Color(uiColor: .secondarySystemFill))
                )

            Label("\(property.commuteTimeMinutes) mins", systemImage: "clock")
                .font(.subheadline.weight(.medium))

            if showCommuteBreakdownInline && (!showJourneyDetails || property.journeySegments.isEmpty) {
                Label(property.commuteBreakdown, systemImage: "figure.walk.motion")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if showJourneyDetails, !property.journeySegments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Journey")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(property.journeySegments.enumerated()), id: \.offset) { index, segment in
                        Text("\(index + 1). \(segment)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let ratingSummary = property.ratingSummary {
                Label("Rating: \(ratingSummary)", systemImage: "star.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.yellow)
            }

            if let score = property.touristConnectivityScore {
                Label("Tourist Connectivity Score: \(score)/100", systemImage: "star.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            Button(property.primaryActionTitle) {
                openURL(property.websiteURL)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}
