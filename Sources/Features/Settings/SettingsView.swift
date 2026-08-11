import SwiftUI

struct SettingsView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

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

                Section {
                    EmptyView()
                } footer: {
                    Text("ParmaMaster Version V\(appVersion)\n© Hamish Ferguson 2026")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
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
