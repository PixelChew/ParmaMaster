import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Theme") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                ColorPicker("Accent colour", selection: Binding(
                    get: { settings.accentColor },
                    set: { color in
                        if let hex = color.hexRGB { settings.accentHex = hex }
                    }
                ), supportsOpacity: false)

                Button("Reset to Parma Orange", systemImage: "arrow.counterclockwise") {
                    settings.accentHex = BrandStyle.defaultAccentHex
                }
                .disabled(settings.accentHex.caseInsensitiveCompare(BrandStyle.defaultAccentHex) == .orderedSame)
            } header: {
                Text("Accent")
            } footer: {
                Text("Accent applies to controls and scores. Text and status meaning never depend on colour alone.")
            }
        }
        .brandedNavigationTitle("Appearance")
    }
}
