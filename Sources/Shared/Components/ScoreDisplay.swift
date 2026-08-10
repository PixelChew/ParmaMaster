import SwiftUI

struct ScoreDisplay: View {
    let score: Decimal?
    let maximum: Decimal
    let mode: RatingDisplayMode
    var size: CGFloat = 34

    var body: some View {
        Group {
            if mode == .stars, maximum <= 10, maximum.rounded(scale: 0) == maximum {
                VStack(alignment: .trailing, spacing: 4) {
                    StarRatingView(score: score ?? 0, maximum: Int(truncating: NSDecimalNumber(decimal: maximum)))
                    Text(score.map { "\($0.displayString)/\(maximum.displayString)" } ?? "—/\(maximum.displayString)")
                        .font(.caption.monospacedDigit())
                }
            } else {
                Text(score.map { "\($0.displayString)/\(maximum.displayString)" } ?? "—/\(maximum.displayString)")
                    .font(BrandStyle.displayFont(size, relativeTo: .title))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel(score.map { "\($0.displayString) out of \(maximum.displayString)" } ?? "Not rated, out of \(maximum.displayString)")
    }
}

struct StarRatingView: View {
    let score: Decimal
    let maximum: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<maximum, id: \.self) { index in
                let lower = Decimal(index)
                Image(systemName: symbol(for: lower))
                    .imageScale(.small)
            }
        }
        .accessibilityHidden(true)
    }

    private func symbol(for lower: Decimal) -> String {
        if score >= lower + 1 { return "star.fill" }
        if score >= lower + Decimal(string: "0.5")! { return "star.leadinghalf.filled" }
        return "star"
    }
}
