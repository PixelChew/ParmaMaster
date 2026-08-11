import SwiftData
import SwiftUI

struct AreaSummary: Identifiable, Hashable {
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
    static func areas(from entries: [ParmaEntry]) -> [AreaSummary] {
        struct Bucket {
            var displayName: String
            var venueIDs: Set<UUID> = []
            var logCount = 0
            var mostRecentLog = Date.distantPast
        }

        var buckets: [String: Bucket] = [:]
        for entry in entries {
            guard let locality = AreaNameResolver.cleaned(entry.venue?.locality) else { continue }
            let key = AreaNameResolver.normalisedKey(locality)

            var bucket = buckets[key] ?? Bucket(displayName: locality)
            if let venueID = entry.venue?.id {
                bucket.venueIDs.insert(venueID)
            }
            bucket.logCount += 1
            if entry.currentRatingDate > bucket.mostRecentLog {
                bucket.mostRecentLog = entry.currentRatingDate
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
    @Query private var entries: [ParmaEntry]
    @State private var query = ""
    @State private var sortField = AreaSortField.name
    @State private var sortDirection = SortDirection.ascending
    @State private var selectedArea: AreaSummary?

    var body: some View {
        // Aggregated once per render; the empty check and search filter share it (audit per-surface note).
        let allAreas = AreaAggregator.areas(from: entries)
        let filteredAreas = filtered(allAreas)
        NavigationStack {
            Group {
                if allAreas.isEmpty {
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

/// Slide-up list of entries logged within a single area. Tapping an entry pushes
/// the standard Parma details screen.
private struct AreaEntriesView: View {
    let areaName: String
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [ParmaEntry]

    var body: some View {
        // Filtered and sorted once per render (audit per-surface note).
        let areaEntries = entries
            .filter { entry in
                guard let locality = AreaNameResolver.cleaned(entry.venue?.locality) else { return false }
                return AreaNameResolver.normalisedKey(locality) == AreaNameResolver.normalisedKey(areaName)
            }
            .sorted { $0.currentRatingDate > $1.currentRatingDate }
        NavigationStack {
            Group {
                if areaEntries.isEmpty {
                    EmptyStateView(
                        title: "No entries here",
                        systemImage: "fork.knife",
                        message: "Entries in \(areaName) will appear here."
                    )
                } else {
                    List(areaEntries) { entry in
                        NavigationLink {
                            ParmaDetailsView(entry: entry)
                        } label: {
                            EntryCard(entry: entry)
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
}
