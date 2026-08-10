import SwiftUI

enum BrandStyle {
    static let cardRadius: CGFloat = 20
    static let pagePadding: CGFloat = 24
    static let photoAspectRatio: CGFloat = 367.0 / 155.0
    static let defaultAccentHex = "#FF6A00"

    static func displayFont(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom("DMSerifDisplay-Regular", size: size, relativeTo: style)
    }
}

extension View {
    func brandCard(emphasised: Bool = false) -> some View {
        padding()
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: BrandStyle.cardRadius))
            .overlay {
                if emphasised {
                    RoundedRectangle(cornerRadius: BrandStyle.cardRadius)
                        .stroke(Color.accentColor, lineWidth: 3)
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 7, y: 3)
    }

    func brandPageBackground() -> some View {
        background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    /// Keeps the native navigation bar semantics and controls while replacing
    /// its system-font title with the DM Serif heading used in the Figma file.
    func brandedNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                BrandedHeading(title: title)
                    .padding(.horizontal, BrandStyle.pagePadding)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .background(Color(.systemGroupedBackground))
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("")
                        .accessibilityHidden(true)
                }
            }
    }
}
