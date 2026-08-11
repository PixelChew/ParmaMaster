import SwiftData
import SwiftUI

struct ParmaLogView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(PhotoStore.self) private var photoStore
    @Environment(BackupService.self) private var backupService
    @Environment(LocalParmaRepository.self) private var repository
    @Query private var entries: [ParmaEntry]
    @State private var sortField = EntrySortField.dateAdded
    @State private var sortDirection = SortDirection.descending
    @State private var entryToDelete: ParmaEntry?
    @State private var errorMessage: String?

    var body: some View {
        // Sorted exactly once per render (audit P-01/P-02 follow-up).
        let sortedEntries = EntrySorter.sorted(entries, by: sortField, direction: sortDirection)
        NavigationStack {
            Group {
                if entries.isEmpty {
                    EmptyStateView(
                        title: "Your Parma Log is empty",
                        systemImage: "book.pages",
                        message: "Each venue appears once, with older ratings kept in its history.",
                        actionTitle: "Log a Parma",
                        action: { router.log() }
                    )
                } else {
                    List {
                        ForEach(sortedEntries) { entry in
                            NavigationLink {
                                ParmaDetailsView(entry: entry)
                            } label: {
                                EntryCard(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    entryToDelete = entry
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .brandPageBackground()
            .brandedNavigationTitle("Parma Log")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    SortMenu(field: $sortField, direction: $sortDirection)
                    Button("Log a Parma", systemImage: "plus") { router.log() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                }
            }
            .confirmationDialog(
                "Delete this Parma entry?",
                isPresented: Binding(
                    get: { entryToDelete != nil },
                    set: { if !$0 { entryToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Entry", role: .destructive) { deleteEntry() }
                Button("Cancel", role: .cancel) { entryToDelete = nil }
            } message: {
                Text("The current rating, its history, notes and locally stored photo will be permanently removed.")
            }
            .alert("Couldn’t Delete Entry", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func deleteEntry() {
        guard let entryToDelete else { return }
        do {
            try repository.delete(entryToDelete, photoStore: photoStore, in: modelContext)
            backupService.markDirty()
            self.entryToDelete = nil
        } catch {
            errorMessage = "The entry could not be deleted. Please try again."
        }
    }
}
