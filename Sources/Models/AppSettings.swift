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

enum LocationReminderDelay: Int, CaseIterable, Identifiable, Sendable {
    case ten = 10
    case twenty = 20
    case thirty = 30
    case fortyFive = 45
    case sixty = 60

    static let defaultValue: Self = .thirty

    var id: Int { rawValue }

    var timeInterval: TimeInterval { TimeInterval(rawValue * 60) }

    var displayName: String {
        rawValue == 60 ? "1 hour" : "\(rawValue) minutes"
    }

    static func value(for minutes: Int) -> Self {
        Self(rawValue: minutes) ?? defaultValue
    }
}

struct AppSettingsSnapshot: Codable, Hashable, Sendable {
    var hasCompletedOnboarding = false
    var theme = AppTheme.system
    var accentHex = BrandStyle.defaultAccentHex
    var ratingConfiguration = RatingConfiguration.default
    var photoFeatureEnabled = true
    var locationUseEnabled = false
    var locationRemindersEnabled = false
    var locationReminderDelayMinutes = LocationReminderDelay.defaultValue.rawValue
    var automaticBackupsEnabled = false
    var rerunSuggestionsEnabled = true
    var rerunStaleMonths = 5
    var rerunHideMonths = 1

    enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding
        case theme
        case accentHex
        case ratingConfiguration
        case photoFeatureEnabled
        case locationUseEnabled
        case locationRemindersEnabled
        case locationReminderDelayMinutes
        case automaticBackupsEnabled
        case rerunSuggestionsEnabled
        case rerunStaleMonths
        case rerunHideMonths
    }

    init(
        hasCompletedOnboarding: Bool = false,
        theme: AppTheme = .system,
        accentHex: String = BrandStyle.defaultAccentHex,
        ratingConfiguration: RatingConfiguration = .default,
        photoFeatureEnabled: Bool = true,
        locationUseEnabled: Bool = false,
        locationRemindersEnabled: Bool = false,
        locationReminderDelayMinutes: Int = LocationReminderDelay.defaultValue.rawValue,
        automaticBackupsEnabled: Bool = false,
        rerunSuggestionsEnabled: Bool = true,
        rerunStaleMonths: Int = 5,
        rerunHideMonths: Int = 1
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.theme = theme
        self.accentHex = accentHex
        self.ratingConfiguration = ratingConfiguration
        self.photoFeatureEnabled = photoFeatureEnabled
        self.locationUseEnabled = locationUseEnabled
        self.locationRemindersEnabled = locationRemindersEnabled
        self.locationReminderDelayMinutes = LocationReminderDelay.value(for: locationReminderDelayMinutes).rawValue
        self.automaticBackupsEnabled = automaticBackupsEnabled
        self.rerunSuggestionsEnabled = rerunSuggestionsEnabled
        self.rerunStaleMonths = rerunStaleMonths
        self.rerunHideMonths = rerunHideMonths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        accentHex = try container.decodeIfPresent(String.self, forKey: .accentHex) ?? BrandStyle.defaultAccentHex
        ratingConfiguration = try container.decodeIfPresent(RatingConfiguration.self, forKey: .ratingConfiguration) ?? .default
        photoFeatureEnabled = try container.decodeIfPresent(Bool.self, forKey: .photoFeatureEnabled) ?? true
        locationUseEnabled = try container.decodeIfPresent(Bool.self, forKey: .locationUseEnabled) ?? false
        locationRemindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .locationRemindersEnabled) ?? false
        locationReminderDelayMinutes = LocationReminderDelay.value(for: try container.decodeIfPresent(Int.self, forKey: .locationReminderDelayMinutes) ?? LocationReminderDelay.defaultValue.rawValue).rawValue
        automaticBackupsEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticBackupsEnabled) ?? false
        rerunSuggestionsEnabled = try container.decodeIfPresent(Bool.self, forKey: .rerunSuggestionsEnabled) ?? true
        rerunStaleMonths = try container.decodeIfPresent(Int.self, forKey: .rerunStaleMonths) ?? 5
        rerunHideMonths = try container.decodeIfPresent(Int.self, forKey: .rerunHideMonths) ?? 1
    }
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
    var locationReminderDelayMinutes: Int { didSet { persist() } }
    var automaticBackupsEnabled: Bool { didSet { persist() } }
    var rerunSuggestionsEnabled: Bool { didSet { persist() } }
    var rerunStaleMonths: Int { didSet { persist() } }
    var rerunHideMonths: Int { didSet { persist() } }

    @ObservationIgnored var changeHandler: (() -> Void)?
    @ObservationIgnored private var isLoading = true
    @ObservationIgnored private var persistTask: Task<Void, Never>?

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
        locationReminderDelayMinutes = stored.locationReminderDelayMinutes
        automaticBackupsEnabled = stored.automaticBackupsEnabled
        rerunSuggestionsEnabled = stored.rerunSuggestionsEnabled
        rerunStaleMonths = stored.rerunStaleMonths
        rerunHideMonths = stored.rerunHideMonths
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
            locationReminderDelayMinutes: locationReminderDelayMinutes,
            automaticBackupsEnabled: automaticBackupsEnabled,
            rerunSuggestionsEnabled: rerunSuggestionsEnabled,
            rerunStaleMonths: rerunStaleMonths,
            rerunHideMonths: rerunHideMonths
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
        locationReminderDelayMinutes = LocationReminderDelay.value(for: snapshot.locationReminderDelayMinutes).rawValue
        automaticBackupsEnabled = snapshot.automaticBackupsEnabled
        rerunSuggestionsEnabled = snapshot.rerunSuggestionsEnabled
        rerunStaleMonths = snapshot.rerunStaleMonths
        rerunHideMonths = snapshot.rerunHideMonths
        isLoading = false
        // Restores/resets must never be lost to the debounce window.
        persistTask?.cancel()
        persistTask = nil
        persistNow()
    }

    func reset() {
        defaults.removeObject(forKey: Self.storageKey)
        apply(AppSettingsSnapshot())
    }

    /// Writes any pending change immediately. RootView calls this when the app
    /// backgrounds so a mid-debounce change is not lost to suspension.
    func flushPendingPersist() {
        guard persistTask != nil else { return }
        persistTask?.cancel()
        persistTask = nil
        persistNow()
    }

    /// Coalesces the encode + UserDefaults write so rapid-fire changes (e.g. a
    /// ColorPicker drag) cause one write instead of a storm (audit P-09).
    private func persist() {
        guard !isLoading else { return }
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.persistTask = nil
            self.persistNow()
        }
    }

    private func persistNow() {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.storageKey)
        }
        changeHandler?()
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
