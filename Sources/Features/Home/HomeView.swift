import Observation
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(HomeGreetingSession.self) private var homeGreeting
    @Environment(PubDetectionService.self) private var pubDetection
    @Query private var entries: [ParmaEntry]

    private var recentEntries: [ParmaEntry] {
        entries.sorted { $0.currentRatingDate > $1.currentRatingDate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    BrandedHeading(title: homeGreeting.message)
                        .padding(.top, 16)

                    if let candidate = pubDetection.currentCandidate {
                        let existing = EntryRepository.findExisting(for: candidate, in: entries)
                        VenueSuggestionCard(candidate: candidate, existingEntry: existing)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Recent entries")
                            .font(BrandStyle.displayFont(31, relativeTo: .title))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if !recentEntries.isEmpty {
                            Button("View log", systemImage: "chevron.right") {
                                router.selectedTab = .log
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
                                router.presentedDetails = entry
                            } label: {
                                EntryCard(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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
        }
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
                    StoredPhotoView(filename: existingEntry.photoFilename)
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
            if let existingEntry { router.presentedDetails = existingEntry }
        }
        .accessibilityElement(children: .contain)
    }
}
