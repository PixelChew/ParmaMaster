import SwiftData
import SwiftUI

struct ParmaDetailsView: View {
    let entry: ParmaEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(PhotoStore.self) private var photoStore
    @Environment(BackupService.self) private var backupService
    @Environment(LocalParmaRepository.self) private var repository
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        // Hoisted so rating reads and revision sorting run once per render.
        let rating = entry.currentRating
        let revisions = entry.sortedRevisions
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                StoredPhotoView(filename: entry.photoFilename)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(BrandStyle.photoAspectRatio, contentMode: .fit)

                Text(entry.formattedAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if entry.venue?.excludedFromRerun == true {
                    Label("Not shown in re-run suggestions", systemImage: "eye.slash")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                        .accessibilityLabel("This place is not shown in re-run suggestions")
                }

                Text("Your ranking")
                    .font(BrandStyle.displayFont(35, relativeTo: .title))
                    .accessibilityAddTraits(.isHeader)

                ScoreDisplay(
                    score: rating.total,
                    maximum: rating.maximum,
                    mode: rating.overallDisplayMode,
                    size: 51
                )

                ForEach(rating.enabledComponents) { component in
                    ComponentScoreRow(component: component)
                }

                if !entry.notes.characters.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes").font(.headline)
                        Text(entry.notes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .brandCard()
                }

                if !revisions.isEmpty {
                    HistorySection(revisions: revisions)
                }

                Button("Delete Entry", systemImage: "trash", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .tint(.red)
                .padding(.top, 8)
            }
            .padding(.horizontal, BrandStyle.pagePadding)
            .padding(.bottom, 80)
        }
        .brandPageBackground()
        .brandedNavigationTitle(entry.venueName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit Entry", systemImage: "pencil") { router.edit(entry) }
                    Button("Rate Again", systemImage: "arrow.clockwise") { router.rateAgain(entry) }
                    if let venue = entry.venue {
                        Button(
                            venue.excludedFromRerun
                                ? "Include in re-run suggestions"
                                : "Do not suggest this place for a re-run",
                            systemImage: venue.excludedFromRerun ? "arrow.triangle.2.circlepath" : "eye.slash"
                        ) {
                            toggleRerunExclusion(for: venue)
                        }
                    }
                } label: {
                    Text("Edit")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .confirmationDialog("Delete \(entry.venueName)?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Entry", role: .destructive) { deleteEntry() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the entry, all rating history, notes and its locally stored photo.")
        }
        .alert("Couldn’t Update Entry", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func toggleRerunExclusion(for venue: Venue) {
        venue.excludedFromRerun.toggle()
        do {
            try modelContext.save()
            backupService.markDirty()
        } catch {
            venue.excludedFromRerun.toggle()
            errorMessage = "The re-run preference could not be saved. Please try again."
        }
    }

    private func deleteEntry() {
        do {
            try repository.delete(entry, photoStore: photoStore, in: modelContext)
            backupService.markDirty()
            router.dismissDetails()
            dismiss()
        } catch {
            errorMessage = "The entry could not be deleted. Please try again."
        }
    }
}

private struct HistorySection: View {
    let revisions: [RatingRevision]
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(BrandStyle.displayFont(31, relativeTo: .title))
                .accessibilityAddTraits(.isHeader)
            ForEach(revisions) { revision in
                let rating = revision.rating
                DisclosureGroup(isExpanded: Binding(
                    get: { expanded.contains(revision.id) },
                    set: { isExpanded in
                        if isExpanded { expanded.insert(revision.id) }
                        else { expanded.remove(revision.id) }
                    }
                )) {
                    VStack(spacing: 10) {
                        ForEach(rating.enabledComponents) { component in
                            HStack {
                                Text(component.category.rawValue)
                                Spacer()
                                Text(component.score.map { "\($0.displayString)/\(component.maximum.displayString)" } ?? "—")
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(revision.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                            Text("Previous rating")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ScoreDisplay(
                            score: rating.total,
                            maximum: rating.maximum,
                            mode: rating.overallDisplayMode,
                            size: 26
                        )
                    }
                }
                .brandCard()
            }
        }
    }
}
