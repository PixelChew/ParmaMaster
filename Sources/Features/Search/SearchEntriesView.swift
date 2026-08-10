import SwiftData
import SwiftUI

struct SearchEntriesView: View {
    @Query private var entries: [ParmaEntry]
    @State private var query = ""
    @State private var sortField = EntrySortField.dateAdded
    @State private var sortDirection = SortDirection.descending

    private var filteredEntries: [ParmaEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = trimmed.isEmpty ? entries : entries.filter { entry in
            [entry.venueName, entry.formattedAddress, entry.searchableNotes]
                .contains { $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return EntrySorter.sorted(matches, by: sortField, direction: sortDirection)
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    EmptyStateView(
                        title: "Nothing to search yet",
                        systemImage: "magnifyingglass",
                        message: "Logged venues will be searchable by name, address and notes."
                    )
                } else if filteredEntries.isEmpty {
                    EmptyStateView(
                        title: "No results",
                        systemImage: "magnifyingglass",
                        message: "No venue, address or note matches “\(query)”."
                    )
                } else {
                    List(filteredEntries) { entry in
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
            .brandedNavigationTitle("Search")
            .searchable(text: $query, prompt: "Venue, address or notes")
            .searchSuggestions {
                if query.isEmpty {
                    Text("Try a pub name, suburb or a word from your notes")
                        .searchCompletion("")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SortMenu(field: $sortField, direction: $sortDirection)
                }
            }
        }
    }
}
