import SwiftData
import SwiftUI

struct AreaSummary: Identifiable, Hashable, Sendable {
    let name: String
    let venueCount: Int
    let logCount: Int
    let mostRecentLog: Date

    var id: String { name }
}

enum AreaSortField: String, CaseIterable, Identifiable {
    case name = "Name"
    case count = "Count"
    case mostRecent = "Most Recent"
    var id: String { rawValue }
}

enum AreaAggregator {
    static func areas(from records: [InsightsEntryRecord]) -> [AreaSummary] {
        struct Bucket {
            var displayName: String
            var venueIDs: Set<UUID> = []
            var logCount = 0
            var mostRecentLog = Date.distantPast
        }

        var buckets: [String: Bucket] = [:]
        for record in records {
            guard let locality = AreaNameResolver.cleaned(record.locality) else { continue }
            let key = AreaNameResolver.normalisedKey(locality)

            var bucket = buckets[key] ?? Bucket(displayName: locality)
            bucket.venueIDs.insert(record.venueID)
            bucket.logCount += 1
            if record.currentRatingDate > bucket.mostRecentLog {
                bucket.mostRecentLog = record.currentRatingDate
            }
            buckets[key] = bucket
        }

        return buckets.map { _, bucket in
            AreaSummary(
                name: bucket.displayName,
                venueCount: bucket.venueIDs.count,
                logCount: bucket.logCount,
                mostRecentLog: bucket.mostRecentLog
            )
        }
    }

    static func sorted(_ areas: [AreaSummary], by field: AreaSortField, direction: SortDirection) -> [AreaSummary] {
        areas.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch field {
            case .name:
                comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            case .count:
                if lhs.venueCount == rhs.venueCount {
                    if lhs.logCount == rhs.logCount {
                        comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    } else {
                        comparison = lhs.logCount < rhs.logCount ? .orderedAscending : .orderedDescending
                    }
                } else {
                    comparison = lhs.venueCount < rhs.venueCount ? .orderedAscending : .orderedDescending
                }
            case .mostRecent:
                if lhs.mostRecentLog == rhs.mostRecentLog {
                    comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                } else {
                    comparison = lhs.mostRecentLog < rhs.mostRecentLog ? .orderedAscending : .orderedDescending
                }
            }
            return direction == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    static func records(in areaName: String, from records: [InsightsEntryRecord]) -> [InsightsEntryRecord] {
        let key = AreaNameResolver.normalisedKey(areaName)
        return records
            .filter { record in
                guard let locality = AreaNameResolver.cleaned(record.locality) else { return false }
                return AreaNameResolver.normalisedKey(locality) == key
            }
            .sorted { $0.currentRatingDate > $1.currentRatingDate }
    }
}

private struct AreaSortMenu: View {
    @Binding var field: AreaSortField
    @Binding var direction: SortDirection

    var body: some View {
        Menu {
            Section("Sort by") {
                Picker("Sort by", selection: $field) {
                    ForEach(AreaSortField.allCases) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
            }
            Section("Direction") {
                Picker("Direction", selection: $direction) {
                    ForEach(SortDirection.allCases) { direction in
                        Text(direction.rawValue).tag(direction)
                    }
                }
            }
        } label: {
            Label("Sort areas", systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Sort areas")
    }
}

struct AreasListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InsightsStore.self) private var insightsStore
    @State private var query = ""
    @State private var sortField = AreaSortField.name
    @State private var sortDirection = SortDirection.ascending
    @State private var selectedArea: AreaSummary?

    var body: some View {
        let allAreas = insightsStore.snapshot?.areas ?? []
        let filteredAreas = filtered(allAreas)
        NavigationStack {
            Group {
                if insightsStore.snapshot == nil {
                    ProgressView("Loading areas…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if allAreas.isEmpty {
                    EmptyStateView(
                        title: "No areas yet",
                        systemImage: "mappin.and.ellipse",
                        message: "Areas appear once venue localities are resolved from your logged parmas."
                    )
                } else if filteredAreas.isEmpty {
                    EmptyStateView(
                        title: "No results",
                        systemImage: "magnifyingglass",
                        message: "No area name matches “\(query)”."
                    )
                } else {
                    List(filteredAreas) { area in
                        Button {
                            withAnimation(BrandMotion.standard) {
                                selectedArea = area
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(area.name)
                                        .font(BrandStyle.displayFont(22, relativeTo: .title3))
                                        .foregroundStyle(.primary)
                                    Text(subtitle(for: area))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .brandCard()
                            .contentShape(.rect)
                        }
                        .buttonStyle(BrandScaleButtonStyle())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Shows entries in \(area.name)")
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .brandPageBackground()
            .brandedNavigationTitle("Areas")
            .searchable(text: $query, prompt: "Search areas")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AreaSortMenu(field: $sortField, direction: $sortDirection)
                }
            }
            .sheet(item: $selectedArea) { area in
                AreaEntriesView(areaName: area.name)
            }
            .task {
                await insightsStore.refresh()
            }
        }
    }

    private func filtered(_ areas: [AreaSummary]) -> [AreaSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = trimmed.isEmpty
            ? areas
            : areas.filter {
                $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        return AreaAggregator.sorted(matches, by: sortField, direction: sortDirection)
    }

    private func subtitle(for area: AreaSummary) -> String {
        let venues = area.venueCount == 1 ? "1 venue" : "\(area.venueCount) venues"
        let logs = area.logCount == 1 ? "1 log" : "\(area.logCount) logs"
        return "\(venues) · \(logs)"
    }
}

private struct AreaEntriesView: View {
    let areaName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(InsightsStore.self) private var insightsStore
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router

    var body: some View {
        let areaEntries = AreaAggregator.records(
            in: areaName,
            from: insightsStore.snapshot?.insights.entries ?? []
        )
        NavigationStack {
            Group {
                if areaEntries.isEmpty {
                    EmptyStateView(
                        title: "No entries here",
                        systemImage: "fork.knife",
                        message: "Entries in \(areaName) will appear here."
                    )
                } else {
                    List(areaEntries) { record in
                        Button {
                            present(record)
                        } label: {
                            InsightEntryRow(record: record)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .brandPageBackground()
            .brandedNavigationTitle(areaName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func present(_ record: InsightsEntryRecord) {
        let id = record.id
        var descriptor = FetchDescriptor<ParmaEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let entry = try? modelContext.fetch(descriptor).first {
            router.presentDetails(entry)
        }
    }
}
