import SwiftUI

struct ComponentScoreRow: View {
    let component: ComponentRatingSnapshot

    var body: some View {
        HStack(alignment: .center) {
            Text(component.category.rawValue)
                .font(BrandStyle.displayFont(25, relativeTo: .title3))
            Spacer(minLength: 12)
            ScoreDisplay(score: component.score, maximum: component.maximum, mode: component.displayMode)
        }
        .brandCard()
        .accessibilityElement(children: .combine)
    }
}
