import Foundation
import Observation
import SwiftUI
import UIKit

enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppSettingsSnapshot: Codable, Hashable, Sendable {
    var hasCompletedOnboarding = false
    var theme = AppTheme.system
    var accentHex = "#FF6A00"
    var ratingConfiguration = RatingConfiguration.default
    var photoFeatureEnabled = true
    var locationUseEnabled = false
    var locationRemindersEnabled = false
    var automaticBackupsEnabled = false
}

@MainActor
@Observable
final class AppSettings {
    private static let storageKey = "ParmaMaster.Settings.v1"
    private let defaults: UserDefaults

    var hasCompletedOnboarding: Bool { didSet { persist() } }
    var theme: AppTheme { didSet { persist() } }
    var accentHex: String { didSet { persist() } }
    var ratingConfiguration: RatingConfiguration { didSet { persist() } }
    var photoFeatureEnabled: Bool { didSet { persist() } }
    var locationUseEnabled: Bool { didSet { persist() } }
    var locationRemindersEnabled: Bool { didSet { persist() } }
    var automaticBackupsEnabled: Bool { didSet { persist() } }

    @ObservationIgnored var changeHandler: (() -> Void)?
    @ObservationIgnored private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(AppSettingsSnapshot.self, from: $0) }
            ?? AppSettingsSnapshot()
        hasCompletedOnboarding = stored.hasCompletedOnboarding
        theme = stored.theme
        accentHex = stored.accentHex
        ratingConfiguration = stored.ratingConfiguration
        photoFeatureEnabled = stored.photoFeatureEnabled
        locationUseEnabled = stored.locationUseEnabled
        locationRemindersEnabled = stored.locationRemindersEnabled
        automaticBackupsEnabled = stored.automaticBackupsEnabled
        isLoading = false
    }

    var accentColor: Color {
        Color(hex: accentHex) ?? Color("AccentColor")
    }

    var snapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(
            hasCompletedOnboarding: hasCompletedOnboarding,
            theme: theme,
            accentHex: accentHex,
            ratingConfiguration: ratingConfiguration,
            photoFeatureEnabled: photoFeatureEnabled,
            locationUseEnabled: locationUseEnabled,
            locationRemindersEnabled: locationRemindersEnabled,
            automaticBackupsEnabled: automaticBackupsEnabled
        )
    }

    func apply(_ snapshot: AppSettingsSnapshot) {
        isLoading = true
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        theme = snapshot.theme
        accentHex = snapshot.accentHex
        ratingConfiguration = snapshot.ratingConfiguration.isValid ? snapshot.ratingConfiguration : .default
        photoFeatureEnabled = snapshot.photoFeatureEnabled
        locationUseEnabled = snapshot.locationUseEnabled
        locationRemindersEnabled = snapshot.locationUseEnabled && snapshot.locationRemindersEnabled
        automaticBackupsEnabled = snapshot.automaticBackupsEnabled
        isLoading = false
        persist()
    }

    func reset() {
        defaults.removeObject(forKey: Self.storageKey)
        apply(AppSettingsSnapshot())
    }

    private func persist() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.storageKey)
        }
        changeHandler?()
    }
}

@MainActor
@Observable
final class CurrentUserProfile {
    private static let displayNameKey = "ParmaMaster.CurrentUser.DisplayName"
    private let defaults: UserDefaults

    var displayName: String {
        didSet {
            let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(cleaned.isEmpty ? "Hamish" : cleaned, forKey: Self.displayNameKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        displayName = defaults.string(forKey: Self.displayNameKey) ?? "Hamish"
    }
}

extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexRGB: String? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}
