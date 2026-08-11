import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LoggerView: View {
    let request: LoggerRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(PhotoStore.self) private var photoStore
    @Environment(BackupService.self) private var backupService
    @Environment(LocalParmaRepository.self) private var repository

    @State private var mode: LoggerMode
    @State private var editingEntry: ParmaEntry?
    @State private var venue: VenueCandidate?
    @State private var rating = RatingSnapshot.blank(configuration: .default)
    @State private var inputs: [RatingCategory: String] = [:]
    @State private var notes = AttributedString()
    @State private var existingPhotoFilename: String?
    @State private var pendingPhotoData: Data?
    @State private var removeExistingPhoto = false
    @State private var isConfigured = false
    @State private var showLocationPicker = false
    @State private var showLoggerSettings = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var duplicateEntry: ParmaEntry?
    @State private var entryToView: ParmaEntry?
    @State private var errorMessage: String?
    @State private var savedTrigger = 0

    init(request: LoggerRequest) {
        self.request = request
        _mode = State(initialValue: request.mode)
        _editingEntry = State(initialValue: request.entry)
        _venue = State(initialValue: request.venue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Button {
                        showLocationPicker = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(venue?.name ?? "Add location")
                                    .font(BrandStyle.displayFont(35, relativeTo: .title))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Image(systemName: "map")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                Spacer(minLength: 0)
                            }
                            if let venue {
                                Text(venue.formattedAddress)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Search Apple Maps for a venue")

                    if settings.photoFeatureEnabled || existingPhotoFilename != nil || pendingPhotoData != nil {
                        PhotoEditorCard(
                            existingFilename: removeExistingPhoto ? nil : existingPhotoFilename,
                            pendingData: pendingPhotoData,
                            showPhotoPicker: $showPhotoPicker,
                            showFileImporter: $showFileImporter,
                            showCamera: $showCamera,
                            onRemove: removePhoto
                        )
                    }

                    Text("Your ranking")
                        .font(BrandStyle.displayFont(35, relativeTo: .title))
                        .accessibilityAddTraits(.isHeader)

                    ScoreDisplay(
                        score: liveTotal,
                        maximum: rating.maximum,
                        mode: rating.overallDisplayMode,
                        size: 51
                    )
                    .animation(.snappy, value: liveTotal)

                    ForEach(rating.enabledComponents) { component in
                        RatingInputRow(
                            component: component,
                            text: inputBinding(for: component)
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes").font(.headline)
                        TextEditor(text: $notes)
                            .frame(minHeight: 150)
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel("Rich text notes")
                    }
                    .brandCard()

                    if !validationMessages.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(validationMessages, id: \.self) { message in
                                Label(message, systemImage: "exclamationmark.circle")
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, BrandStyle.pagePadding)
                .padding(.bottom, 80)
            }
            .brandPageBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("Options") { showLoggerSettings = true }
                    Button("Save", systemImage: "checkmark") { save() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                        .accessibilityLabel("Save Parma entry")
                }
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView { selected in
                    selectVenue(selected)
                }
            }
            .sheet(isPresented: $showLoggerSettings) {
                NavigationStack { LoggerSettingsView() }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoSelection, matching: .images)
            .onChange(of: photoSelection) { _, selection in
                guard let selection else { return }
                Task {
                    do {
                        pendingPhotoData = try await selection.loadTransferable(type: Data.self)
                        removeExistingPhoto = false
                    } catch {
                        errorMessage = "That photo could not be loaded. Try another image."
                    }
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
                importFile(result)
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { data in
                    pendingPhotoData = data
                    removeExistingPhoto = false
                }
            }
            .sheet(item: $entryToView) { entry in
                NavigationStack {
                    ParmaDetailsView(entry: entry)
                }
            }
            .alert("Venue Already Logged", isPresented: Binding(
                get: { duplicateEntry != nil },
                set: { if !$0 { duplicateEntry = nil } }
            )) {
                Button("Rate Again") { switchToRateAgain() }
                Button("View Entry") {
                    entryToView = duplicateEntry
                    duplicateEntry = nil
                }
                Button("Cancel", role: .cancel) { duplicateEntry = nil }
            } message: {
                Text("You already have an entry for this venue. Rate it again to save the new score in History instead of creating a duplicate.")
            }
            .alert("Couldn’t Save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
            .sensoryFeedback(.success, trigger: savedTrigger)
            .onAppear { configureIfNeeded() }
        }
    }

    private var title: String {
        switch mode {
        case .new: "Log Parma"
        case .edit: "Edit Parma"
        case .rateAgain: "Rate Again"
        }
    }

    private var parsedRating: RatingSnapshot {
        var updated = rating
        for index in updated.components.indices {
            let category = updated.components[index].category
            updated.components[index].score = Decimal.parseUserInput(inputs[category] ?? "")
        }
        return updated
    }

    private var liveTotal: Decimal? {
        let snapshot = parsedRating
        return snapshot.hasValidScores ? snapshot.total : nil
    }

    private var validationMessages: [String] {
        rating.enabledComponents.compactMap { component in
            let text = inputs[component.category] ?? ""
            guard !text.isEmpty else { return "Enter a \(component.category.rawValue) rating." }
            guard let score = Decimal.parseUserInput(text), score.isFinite else {
                return "\(component.category.rawValue) must be a valid number."
            }
            guard score >= 0, score <= component.maximum else {
                return "\(component.category.rawValue) must be between 0 and \(component.maximum.displayString)."
            }
            return nil
        }
    }

    private var canSave: Bool {
        venue != nil && parsedRating.hasValidScores
    }

    private func inputBinding(for component: ComponentRatingSnapshot) -> Binding<String> {
        Binding(
            get: { inputs[component.category] ?? "" },
            set: { candidate in
                inputs[component.category] = RatingInputPolicy.boundedText(
                    candidate,
                    maximum: component.maximum
                )
            }
        )
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        if let entry = request.entry {
            venue = VenueCandidate(
                mapItemIdentifier: entry.mapItemIdentifier,
                name: entry.venueName,
                formattedAddress: entry.formattedAddress,
                latitude: entry.latitude,
                longitude: entry.longitude,
                locality: entry.venue?.locality
            )
            notes = entry.notes
            existingPhotoFilename = entry.photoFilename
            if request.mode == .edit {
                rating = entry.currentRating
                inputs = Dictionary(uniqueKeysWithValues: entry.currentRating.components.compactMap { component in
                    component.score.map { score in (component.category, score.displayString) }
                })
            } else {
                loadBlankCurrentConfiguration()
            }
        } else {
            loadBlankCurrentConfiguration()
        }
    }

    private func loadBlankCurrentConfiguration() {
        rating = .blank(configuration: settings.ratingConfiguration)
        inputs = [:]
    }

    private func selectVenue(_ selected: VenueCandidate) {
        venue = selected
        if mode == .new,
           let existing = ((try? repository.findExisting(for: selected, in: modelContext)) ?? nil) {
            duplicateEntry = existing
        }
    }

    private func switchToRateAgain() {
        guard let duplicateEntry else { return }
        editingEntry = duplicateEntry
        mode = .rateAgain
        notes = duplicateEntry.notes
        existingPhotoFilename = duplicateEntry.photoFilename
        loadBlankCurrentConfiguration()
        self.duplicateEntry = nil
    }

    private func removePhoto() {
        pendingPhotoData = nil
        removeExistingPhoto = true
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            pendingPhotoData = try Data(contentsOf: url)
            removeExistingPhoto = false
        } catch {
            errorMessage = "That image file could not be opened."
        }
    }

    private func save() {
        guard let venue, parsedRating.hasValidScores else { return }
        // Duplicate check must run at save time, not just at venue selection:
        // Logger can open with a venue pre-filled (Home card, notification deep
        // link), and `create` returns the existing entry without saving, which
        // would silently discard the new rating, notes, and photo.
        if editingEntry == nil,
           let existing = ((try? repository.findExisting(for: venue, in: modelContext)) ?? nil) {
            duplicateEntry = existing
            return
        }
        do {
            let oldFilename = editingEntry?.photoFilename
            var finalFilename = removeExistingPhoto ? nil : oldFilename
            if let pendingPhotoData {
                finalFilename = try photoStore.save(imageData: pendingPhotoData, replacing: oldFilename)
            } else if removeExistingPhoto, let oldFilename {
                try? photoStore.delete(filename: oldFilename)
            }

            if let editingEntry {
                try repository.update(
                    editingEntry,
                    venue: venue,
                    rating: parsedRating,
                    notes: notes,
                    photoFilename: finalFilename,
                    deliberateRerating: mode == .rateAgain,
                    in: modelContext
                )
            } else {
                try repository.create(
                    venue: venue,
                    rating: parsedRating,
                    notes: notes,
                    photoFilename: finalFilename,
                    in: modelContext
                )
            }
            backupService.markDirty()
            savedTrigger += 1
            dismiss()
        } catch {
            errorMessage = "The entry could not be saved. Check the ratings and try again."
        }
    }
}

private struct RatingInputRow: View {
    let component: ComponentRatingSnapshot
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(component.category.rawValue)
                    .font(BrandStyle.displayFont(25, relativeTo: .title3))
                Spacer()
                if component.displayMode == .numeric {
                    TextField("Rating", text: $text)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title2.monospacedDigit())
                        .frame(minWidth: 72, idealWidth: 90, maxWidth: 120)
                        .accessibilityLabel("\(component.category.rawValue) rating")
                    Text("/\(component.maximum.displayString)")
                        .font(BrandStyle.displayFont(30, relativeTo: .title2))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            if component.displayMode == .stars {
                StarRatingInputView(
                    score: $text,
                    maximum: Int(truncating: NSDecimalNumber(decimal: component.maximum))
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .brandCard()
    }
}

private struct StarRatingInputView: View {
    @Binding var score: String
    let maximum: Int

    private var selectedScore: Int {
        guard let parsed = Decimal.parseUserInput(score) else { return 0 }
        return Int(truncating: NSDecimalNumber(decimal: parsed))
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...maximum, id: \.self) { value in
                Button {
                    score = selectedScore == value ? "" : String(value)
                } label: {
                    Image(systemName: value <= selectedScore ? "star.fill" : "star")
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) out of \(maximum) stars")
                .accessibilityAddTraits(value == selectedScore ? .isSelected : [])
            }
        }
        .foregroundStyle(Color.accentColor)
        .accessibilityElement(children: .contain)
    }
}

enum RatingInputPolicy {
    static func boundedText(_ candidate: String, maximum: Decimal, locale: Locale = .current) -> String {
        guard let value = Decimal.parseUserInput(candidate, locale: locale) else { return candidate }
        if value < 0 { return "0" }
        if value > maximum { return maximum.displayString }
        return candidate
    }
}

private struct PhotoEditorCard: View {
    let existingFilename: String?
    let pendingData: Data?
    @Binding var showPhotoPicker: Bool
    @Binding var showFileImporter: Bool
    @Binding var showCamera: Bool
    let onRemove: () -> Void
    @Environment(PhotoStore.self) private var photoStore

    private var image: UIImage? {
        pendingData.flatMap(UIImage.init(data:)) ?? photoStore.image(for: existingFilename)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(.tertiarySystemFill)
                .overlay {
                if let image {
                    AspectFillImage(image: image)
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(BrandStyle.photoAspectRatio, contentMode: .fit)
                .clipped()
                .clipShape(.rect(cornerRadius: BrandStyle.cardRadius))

            Menu {
                Button("Take Photo", systemImage: "camera") { showCamera = true }
                Button("Choose from Photos", systemImage: "photo.on.rectangle") { showPhotoPicker = true }
                Button("Choose File", systemImage: "folder") { showFileImporter = true }
                if image != nil {
                    Button("Remove Photo", systemImage: "trash", role: .destructive, action: onRemove)
                }
            } label: {
                Label(image == nil ? "Add photo" : "Photo options", systemImage: "camera")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding()
        }
    }
}
