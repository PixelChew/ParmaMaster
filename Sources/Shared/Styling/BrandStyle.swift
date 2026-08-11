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

enum BrandMotion {
    static let standard: Animation = .snappy(duration: 0.35)
    static let tabTransitionDelay: Duration = .milliseconds(320)

    static var cardTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }

    static func perform(_ reduceMotion: Bool, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(standard, updates)
        }
    }
}

struct BrandScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
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
