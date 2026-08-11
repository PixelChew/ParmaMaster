import Foundation
import Observation

private struct RerunSuggestionState: Codable, Equatable {
    var hiddenUntil: Date?
    var suggestedEntryID: UUID?
    var suggestedRatingDate: Date?
}

@MainActor
@Observable
final class RerunSuggestionService {
    private static let storageKey = "ParmaMaster.RerunSuggestion"

    private let defaults: UserDefaults
    private let calendar: Calendar
    private var state: RerunSuggestionState

    private(set) var suggestedEntry: ParmaEntry?
    private(set) var gapDescription = ""
    private(set) var shouldShowCard = false

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        state = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(RerunSuggestionState.self, from: $0) }
            ?? RerunSuggestionState()
    }

    /// Recomputes eligibility, stable random pick, auto-hide after re-log, and `shouldShowCard`.
    func update(
        entries: [ParmaEntry],
        settings: AppSettings,
        hasLocationCandidate: Bool,
        now: Date = .now
    ) {
        autoHideIfSuggestedWasRelogged(entries: entries, hideMonths: settings.rerunHideMonths, now: now)

        let eligible = eligibleEntries(
            from: entries,
            staleMonths: settings.rerunStaleMonths,
            now: now
        )

        if let currentID = state.suggestedEntryID,
           let current = eligible.first(where: { $0.id == currentID }) {
            suggestedEntry = current
        } else if let pick = eligible.randomElement() {
            suggestedEntry = pick
            state.suggestedEntryID = pick.id
            state.suggestedRatingDate = pick.currentRatingDate
            persist()
        } else {
            clearSuggestion()
        }

        if let suggestedEntry {
            gapDescription = Self.formatGap(from: suggestedEntry.currentRatingDate, to: now, calendar: calendar)
        } else {
            gapDescription = ""
        }

        shouldShowCard = settings.rerunSuggestionsEnabled
            && !isHidden(at: now)
            && suggestedEntry != nil
            && !hasLocationCandidate
    }

    func dismiss(hideMonths: Int, now: Date = .now) {
        hide(forMonths: hideMonths, now: now)
        shouldShowCard = false
    }

    func dismiss(settings: AppSettings, now: Date = .now) {
        dismiss(hideMonths: settings.rerunHideMonths, now: now)
    }

    /// Months/years gap copy, e.g. `"5 months"`, `"1 year"`.
    static func formatGap(
        from ratingDate: Date,
        to now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month], from: ratingDate, to: now)
        let totalMonths = max(0, (components.year ?? 0) * 12 + (components.month ?? 0))
        if totalMonths >= 12 {
            let years = totalMonths / 12
            return years == 1 ? "1 year" : "\(years) years"
        }
        let months = max(totalMonths, 1)
        return months == 1 ? "1 month" : "\(months) months"
    }

    // MARK: - Private

    private func eligibleEntries(
        from entries: [ParmaEntry],
        staleMonths: Int,
        now: Date
    ) -> [ParmaEntry] {
        guard let threshold = calendar.date(byAdding: .month, value: -staleMonths, to: now) else {
            return []
        }
        return entries.filter { entry in
            guard entry.venue?.excludedFromRerun != true else { return false }
            return entry.currentRatingDate <= threshold
        }
    }

    private func autoHideIfSuggestedWasRelogged(
        entries: [ParmaEntry],
        hideMonths: Int,
        now: Date
    ) {
        guard let suggestedID = state.suggestedEntryID,
              let recordedDate = state.suggestedRatingDate,
              let entry = entries.first(where: { $0.id == suggestedID }),
              entry.currentRatingDate > recordedDate
        else { return }

        hide(forMonths: hideMonths, now: now)
    }

    private func hide(forMonths months: Int, now: Date) {
        state.hiddenUntil = calendar.date(byAdding: .month, value: months, to: now) ?? now
        persist()
    }

    private func isHidden(at now: Date) -> Bool {
        guard let hiddenUntil = state.hiddenUntil else { return false }
        return hiddenUntil > now
    }

    private func clearSuggestion() {
        suggestedEntry = nil
        if state.suggestedEntryID != nil || state.suggestedRatingDate != nil {
            state.suggestedEntryID = nil
            state.suggestedRatingDate = nil
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
