import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingsRow(title: "Appearance", symbol: "paintpalette")
                }

                NavigationLink {
                    LoggerSettingsView()
                } label: {
                    SettingsRow(title: "Parma Logging", symbol: "book.pages")
                }

                NavigationLink {
                    BehaviourSettingsView()
                } label: {
                    SettingsRow(title: "Behaviour", symbol: "gearshape")
                }

                NavigationLink {
                    BackupResetSettingsView()
                } label: {
                    SettingsRow(title: "Backup & Reset", symbol: "arrow.clockwise")
                }
            }
            .listStyle(.insetGrouped)
            .brandedNavigationTitle("Settings")
        }
    }
}

private struct SettingsRow: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title)
                .font(.body)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 5)
    }
}
