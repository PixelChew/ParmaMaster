import SwiftUI

struct EntryCard: View {
    let entry: ParmaEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.venueName)
                    .font(BrandStyle.displayFont(22, relativeTo: .title3))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(componentSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            ScoreDisplay(
                score: entry.currentRating.total,
                maximum: entry.currentRating.maximum,
                mode: entry.currentRating.overallDisplayMode,
                size: 32
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard()
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Parma details")
    }

    private var componentSummary: String {
        entry.currentRating.enabledComponents.compactMap { component in
            guard let score = component.score else { return nil }
            return "\(component.category.rawValue) \(score.displayString)/\(component.maximum.displayString)"
        }.joined(separator: " · ")
    }
}
