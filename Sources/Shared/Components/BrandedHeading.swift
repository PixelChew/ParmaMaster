import SwiftUI

struct BrandedHeading: View {
    let title: String
    var size: CGFloat = 41

    var body: some View {
        Text(title)
            .font(BrandStyle.displayFont(size, relativeTo: .largeTitle))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
