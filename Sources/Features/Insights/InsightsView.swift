import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct InsightsView: View {
    @Environment(AppRouter.self) private var router
    @Query private var entries: [ParmaEntry]
    @State private var selectedEntry: ParmaEntry?

    var body: some View {
        // Calculate once per render: the calculator decodes every entry's rating
        // JSON, so recomputing it per statistic hangs the UI on larger logs.
        let insights = ParmaInsightsCalculator.calculate(entries)
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    BrandedHeading(title: "Insights")
                        .padding(.top, 16)

                    if entries.isEmpty {
                        EmptyStateView(
                            title: "No parmas on the map yet",
                            systemImage: "map",
                            message: "Log a parma and its venue will appear here.",
                            actionTitle: "Log a Parma",
                            action: { router.log() }
                        )
                        .frame(minHeight: 320)
                    } else {
                        ParmaMapView(entries: entries, selectedEntry: $selectedEntry)
                        headlineStatistics(insights)
                        extremeSection(insights)
                        perfectScoresSection(insights)
                        componentAverages(insights)
                    }
                }
                .padding(.horizontal, BrandStyle.pagePadding)
                .padding(.bottom, 80)
            }
            .brandPageBackground()
        }
    }

    private func headlineStatistics(_ insights: ParmaInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("At a glance").font(BrandStyle.displayFont(29, relativeTo: .title))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatisticCard(
                    value: "\(insights.parmasLogged)",
                    label: "Parmas logged",
                    systemImage: "fork.knife",
                    subtitle: ratingsSubmittedSubtitle(insights)
                )
                StatisticCard(
                    value: insights.averageNormalisedScore.map { $0.tenPointEquivalent.insightScoreString } ?? "—",
                    label: "Average rating",
                    systemImage: "chart.bar"
                )
                StatisticCard(
                    value: insights.highestNormalisedScore.map { $0.tenPointEquivalent.insightScoreString } ?? "—",
                    label: "Highest rating",
                    systemImage: "arrow.up.right"
                )
                StatisticCard(
                    value: insights.lowestNormalisedScore.map { $0.tenPointEquivalent.insightScoreString } ?? "—",
                    label: "Lowest rating",
                    systemImage: "arrow.down.right"
                )
                Button {
                    router.showAreasList()
                } label: {
                    StatisticCard(
                        value: "\(insights.areasVisited)",
                        label: "Areas visited",
                        systemImage: "mappin.and.ellipse"
                    )
                }
                .buttonStyle(BrandScaleButtonStyle())
                .accessibilityHint("Shows areas list")
                StatisticCard(
                    value: "\(insights.parmasLoggedThisYear)",
                    label: "Parmas logged this year",
                    systemImage: "calendar"
                )
            }
        }
    }

    private func ratingsSubmittedSubtitle(_ insights: ParmaInsights) -> String {
        let count = insights.ratingsSubmitted
        return "\(count) rating\(count == 1 ? "" : "s") submitted"
    }

    private func extremeSection(_ insights: ParmaInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Standouts").font(BrandStyle.displayFont(29, relativeTo: .title))
            VenueInsightGroup(title: "Highest rated", entries: insights.highestEntries, action: present)
            VenueInsightGroup(title: "Lowest rated", entries: insights.lowestEntries, action: present)
        }
    }

    private func perfectScoresSection(_ insights: ParmaInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Perfect scores").font(BrandStyle.displayFont(29, relativeTo: .title))
                Spacer()
                Text("\(insights.perfectEntries.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("\(insights.perfectEntries.count) perfect scores")
            }
            if insights.perfectEntries.isEmpty {
                ContentUnavailableView("No perfect scores yet", systemImage: "star", description: Text("The 10/10 hunt continues."))
                    .frame(maxWidth: .infinity)
                    .brandCard()
            } else {
                VenueInsightGroup(title: nil, entries: insights.perfectEntries, action: present)
            }
        }
    }

    private func componentAverages(_ insights: ParmaInsights) -> some View {
        Group {
            if !insights.componentAverages.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Component averages").font(BrandStyle.displayFont(29, relativeTo: .title))
                    VStack(spacing: 10) {
                        ForEach(RatingCategory.allCases) { category in
                            HStack {
                                Text(category.rawValue)
                                Spacer()
                                Text(insights.componentAverages[category].map { $0.tenPointEquivalent.insightScoreString } ?? "No data")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .brandCard()
                }
            }
        }
    }

    private func present(_ entry: ParmaEntry) {
        router.presentDetails(entry)
    }
}

private struct StatisticCard: View {
    let value: String
    let label: String
    let systemImage: String
    var subtitle: String? = nil

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
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .brandCard()
        .accessibilityElement(children: .combine)
    }
}

private struct VenueInsightGroup: View {
    let title: String?
    let entries: [ParmaEntry]
    var showsVisits = false
    let action: (ParmaEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            ForEach(entries) { entry in
                Button { action(entry) } label: {
                    HStack(spacing: 12) {
                        StoredPhotoView(filename: entry.photoFilename)
                            .frame(width: 86, height: 68)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.venueName).font(.headline).foregroundStyle(.primary).lineLimit(2)
                            Text(entry.currentRatingDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                            if showsVisits {
                                Text("\(entry.revisions.count + 1) ratings")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        ScoreDisplay(score: entry.currentRating.total, maximum: entry.currentRating.maximum, mode: entry.currentRating.overallDisplayMode, size: 24)
                            .fixedSize()
                    }
                }
                .buttonStyle(BrandScaleButtonStyle())
                .accessibilityHint("Opens Parma details")
                if entry.id != entries.last?.id { Divider() }
            }
        }
        .brandCard()
    }
}

private struct ParmaMapView: View {
    let entries: [ParmaEntry]
    @Binding var selectedEntry: ParmaEntry?
    @State private var position: MapCameraPosition = .automatic

    private var mappableEntries: [ParmaEntry] { entries.filter { CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) && !($0.latitude == 0 && $0.longitude == 0) } }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $position) {
                ForEach(mappableEntries) { entry in
                    Annotation(entry.venueName, coordinate: CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude), anchor: .bottom) {
                        Button {
                            withAnimation(.snappy) { selectedEntry = entry }
                        } label: {
                            Text(entry.currentRating.normalisedScore.tenPointEquivalent.rounded(scale: 1).displayString)
                                .font(.caption.bold().monospacedDigit())
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel("\(entry.venueName), \(entry.currentRating.normalisedScore.tenPointEquivalent.insightScoreString) equivalent")
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(height: 280)
            .onAppear { frameEntries() }
            .onChange(of: mappableEntries.map(\.id)) { _, _ in frameEntries() }

            if let selectedEntry {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedEntry.venueName).font(.headline).lineLimit(1)
                        Text("\(selectedEntry.currentRating.total.displayString)/\(selectedEntry.currentRating.maximum.displayString) · \(selectedEntry.currentRatingDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("View Entry") { routerPresent(selectedEntry) }.buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(BrandMotion.standard, value: selectedEntry?.id)
        .clipShape(.rect(cornerRadius: BrandStyle.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: BrandStyle.cardRadius).stroke(Color.primary.opacity(0.08)))
        .accessibilityElement(children: .contain)
    }

    @Environment(AppRouter.self) private var router
    private func routerPresent(_ entry: ParmaEntry) { router.presentDetails(entry) }

    private func frameEntries() {
        guard !mappableEntries.isEmpty else { return }
        if mappableEntries.count == 1, let entry = mappableEntries.first {
            position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude), span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
            return
        }
        let latitudes = mappableEntries.map(\.latitude)
        let longitudes = mappableEntries.map(\.longitude)
        let latitudeSpan = max((latitudes.max()! - latitudes.min()!) * 1.35, 0.02)
        let longitudeSpan = max((longitudes.max()! - longitudes.min()!) * 1.35, 0.02)
        position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (latitudes.max()! + latitudes.min()!) / 2, longitude: (longitudes.max()! + longitudes.min()!) / 2), span: MKCoordinateSpan(latitudeDelta: min(latitudeSpan, 180), longitudeDelta: min(longitudeSpan, 180))))
    }
}
