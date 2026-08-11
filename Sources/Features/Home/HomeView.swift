import Observation
import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(HomeGreetingSession.self) private var homeGreeting
    @Environment(PubDetectionService.self) private var pubDetection
    @Environment(LocalParmaRepository.self) private var repository
    @Environment(RerunSuggestionService.self) private var rerunService
    // Store-sorted so the render pass never re-sorts the whole log.
    @Query(sort: \ParmaEntry.currentRatingDate, order: .reverse) private var entries: [ParmaEntry]

    /// How many recent entries to show, keyed only to screen height — never reduced
    /// because greeting, stats, or suggestion cards are on screen.
    private var recentEntriesLimit: Int {
        HomeLayout.recentEntriesLimit(forScreenHeight: WindowSceneMetrics.screenHeight)
    }

    private var recentEntries: [ParmaEntry] {
        Array(entries.prefix(recentEntriesLimit))
    }

    private var areasVisitedCount: Int {
        Set(
            entries.compactMap { entry -> String? in
                guard let locality = AreaNameResolver.cleaned(entry.venue?.locality) else { return nil }
                return AreaNameResolver.normalisedKey(locality)
            }
        ).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    BrandedHeading(title: homeGreeting.message)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 16)

                    if let candidate = pubDetection.currentCandidate {
                        let existing = repository.findExisting(for: candidate, in: entries)
                        VenueSuggestionCard(candidate: candidate, existingEntry: existing)
                            .transition(BrandMotion.cardTransition)
                    }

                    if entries.count >= 2 {
                        HomeStatsRow(
                            parmasLogged: entries.count,
                            areasVisited: areasVisitedCount,
                            onParmasTap: { router.selectTab(.log) },
                            onAreasTap: { router.showAreasList() }
                        )
                        .transition(BrandMotion.cardTransition)
                    }

                    if rerunService.shouldShowCard,
                       pubDetection.currentCandidate == nil,
                       let suggestedEntry = rerunService.suggestedEntry {
                        RerunSuggestionCard(
                            entry: suggestedEntry,
                            gapDescription: rerunService.gapDescription,
                            onRateAgain: { router.rateAgain(suggestedEntry) },
                            onDismiss: { rerunService.dismiss(settings: settings) }
                        )
                        .transition(BrandMotion.cardTransition)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Recent entries")
                            .font(BrandStyle.displayFont(31, relativeTo: .title))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if !recentEntries.isEmpty {
                            Button("View log", systemImage: "chevron.right") {
                                router.selectTab(.log)
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("View Parma Log")
                        }
                    }

                    if recentEntries.isEmpty {
                        EmptyStateView(
                            title: "No parmas yet",
                            systemImage: "fork.knife",
                            message: "Search Apple Maps for a pub and log your first parma.",
                            actionTitle: "Log a Parma",
                            action: { router.log() }
                        )
                        .frame(minHeight: 260)
                    } else {
                        ForEach(recentEntries) { entry in
                            Button {
                                router.presentDetails(entry)
                            } label: {
                                EntryCard(entry: entry)
                            }
                            .buttonStyle(BrandScaleButtonStyle())
                        }
                    }
                }
                .animation(BrandMotion.standard, value: pubDetection.currentCandidate?.id)
                .animation(BrandMotion.standard, value: rerunService.shouldShowCard)
                .animation(BrandMotion.standard, value: entries.count >= 2)
                .padding(.horizontal, BrandStyle.pagePadding)
                .padding(.bottom, 96)
            }
            .brandPageBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log a Parma", systemImage: "plus") { router.log() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Log a Parma")
                }
            }
            .onAppear {
                refreshRerunSuggestion()
            }
            .onChange(of: entries.count) { _, _ in
                refreshRerunSuggestion()
            }
            .onChange(of: pubDetection.currentCandidate?.id) { _, _ in
                refreshRerunSuggestion()
            }
            .onChange(of: settings.rerunSuggestionsEnabled) { _, _ in
                refreshRerunSuggestion()
            }
            .onChange(of: settings.rerunStaleMonths) { _, _ in
                refreshRerunSuggestion()
            }
            .onChange(of: settings.rerunHideMonths) { _, _ in
                refreshRerunSuggestion()
            }
        }
    }

    private func refreshRerunSuggestion() {
        rerunService.update(
            entries: Array(entries),
            settings: settings,
            hasLocationCandidate: pubDetection.currentCandidate != nil
        )
    }
}

/// Home layout constants derived from device screen size only.
private enum HomeLayout {
    /// Pro Max / Plus (~932 pt): four entries fit without scrolling the baseline home layout.
    /// Standard 6.1" (~844–852 pt): three. Mini (~812 pt) and SE (~667 pt): two.
    static func recentEntriesLimit(forScreenHeight height: CGFloat) -> Int {
        switch height {
        case 900...: 4
        case 820..<900: 3
        default: 2
        }
    }
}

/// Screen metrics via the active window scene — Apple's replacement for `UIScreen.main`.
private enum WindowSceneMetrics {
    @MainActor
    static var screenHeight: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return scene?.screen.bounds.height ?? 0
    }
}

@MainActor
@Observable
final class HomeGreetingSession {
    let message: String

    init() {
        message = HomeGreeting.message()
    }
}

enum HomeGreeting {
    /// Greetings are intentionally name-free — do not reintroduce personalised
    /// variants such as "Welcome back, {name}." from older branches.
    static func message(
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        candidates(at: date, calendar: calendar).randomElement()!
    }

    static func candidates(at date: Date, calendar: Calendar) -> [String] {
        let hour = calendar.component(.hour, from: date)
        let day = calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]

        var greetings = [
            "It's always a good time for a parma.",
            "Welcome back.",
            "Time for a parma?",
            "Parma or parmi?",
            "How do you say it?",
            "Time to rank.",
            "\(day) parma day."
        ]

        switch hour {
        case 5..<12:
            greetings.append("Good morning.")
        case 12..<17:
            greetings.append("Good afternoon.")
        case 17..<22:
            greetings.append("Good evening.")
        default:
            break
        }

        if (17..<21).contains(hour) {
            greetings += ["Parma dinner?", "Winner winna parma dinner"]
        }

        if (0..<5).contains(hour) {
            greetings.append("Up late?")
        }

        if hour >= 22 {
            greetings.append("Late night parma?")
        }

        return greetings
    }
}

private struct HomeStatsRow: View {
    let parmasLogged: Int
    let areasVisited: Int
    let onParmasTap: () -> Void
    let onAreasTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onParmasTap) {
                HomeStatCard(
                    value: "\(parmasLogged)",
                    label: "Parmas logged",
                    systemImage: "fork.knife"
                )
            }
            .buttonStyle(BrandScaleButtonStyle())
            .accessibilityHint("Opens Parma Log")

            Button(action: onAreasTap) {
                HomeStatCard(
                    value: "\(areasVisited)",
                    label: "Areas visited",
                    systemImage: "mappin.and.ellipse"
                )
            }
            .buttonStyle(BrandScaleButtonStyle())
            .accessibilityHint("Opens areas list")
        }
    }
}

private struct HomeStatCard: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2.weight(.medium))
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(BrandStyle.displayFont(34, relativeTo: .title))
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .brandCard()
        .accessibilityElement(children: .combine)
    }
}

private struct RerunSuggestionCard: View {
    let entry: ParmaEntry
    let gapDescription: String
    let onRateAgain: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(entry.venueName)
                    .font(BrandStyle.displayFont(22, relativeTo: .title3))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss re-run suggestion")
            }

            Text("You haven't visited this place in \(gapDescription). Time for a re-run?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Rate again", action: onRateAgain)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard()
        .accessibilityElement(children: .contain)
    }
}

private struct VenueSuggestionCard: View {
    let candidate: VenueCandidate
    let existingEntry: ParmaEntry?
    @Environment(AppRouter.self) private var router
    @Environment(PubDetectionService.self) private var pubDetection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existingEntry == nil ? "Welcome to \(candidate.name)" : "Back at \(candidate.name)")
                .font(BrandStyle.displayFont(22, relativeTo: .title3))
                .lineLimit(2)

            HStack(alignment: .top, spacing: 14) {
                if let existingEntry {
                    StoredPhotoView(filename: existingEntry.photoFilename, useThumbnail: true)
                        .frame(width: 108, height: 110)
                    VStack(alignment: .leading, spacing: 10) {
                        ScoreDisplay(
                            score: existingEntry.currentRating.total,
                            maximum: existingEntry.currentRating.maximum,
                            mode: existingEntry.currentRating.overallDisplayMode,
                            size: 30
                        )
                        Text(existingEntry.currentRating.enabledComponents.compactMap { component in
                            component.score.map { "\(component.category.rawValue) \($0.displayString)/\(component.maximum.displayString)" }
                        }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Button("Edit") { router.edit(existingEntry) }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                    }
                } else {
                    ZStack {
                        Color(.tertiarySystemFill)
                        Image(systemName: "building.2")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 108, height: 110)
                    .clipShape(.rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Looks like you haven’t been here yet!")
                            .font(.headline)
                        HStack {
                            Button("Log entry") { router.log(venue: candidate) }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.capsule)
                            Button("Skip") { pubDetection.skipCurrentVisit() }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .tint(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard(emphasised: true)
        .contentShape(.rect)
        .onTapGesture {
            if let existingEntry { router.presentDetails(existingEntry) }
        }
        .accessibilityElement(children: .contain)
    }
}
