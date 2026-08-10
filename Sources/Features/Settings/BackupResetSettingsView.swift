import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupResetSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(BackupService.self) private var backupService
    @Environment(PhotoStore.self) private var photoStore
    @Environment(LocationService.self) private var locationService
    @Environment(PubDetectionService.self) private var pubDetection
    @State private var chooseDirectory = false
    @State private var chooseRestoreFile = false
    @State private var pendingRestoreURL: URL?
    @State private var showRestoreConfirmation = false
    @State private var showResetConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Button("Choose Backup Location", systemImage: "folder.badge.plus") {
                    chooseDirectory = true
                }

                Button("Back Up Now", systemImage: "arrow.up.doc") {
                    performBackup()
                }
                .disabled(!backupService.hasBackupLocation || backupService.isWorking)

                Toggle("Automatic Backups", isOn: $settings.automaticBackupsEnabled)
                    .disabled(!backupService.hasBackupLocation)

                Button("Restore Backup", systemImage: "arrow.down.doc") {
                    chooseRestoreFile = true
                }

                if let last = backupService.lastSuccessfulBackup {
                    LabeledContent("Last successful backup", value: last.formatted(date: .abbreviated, time: .shortened))
                } else {
                    LabeledContent("Last successful backup", value: "Never")
                }

                if let status = backupService.statusMessage {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Explicit Backup")
            } footer: {
                Text("The chosen Files directory may be on this iPhone, iCloud Drive, OneDrive, Google Drive, or another File Provider. The versioned backup contains entries, history, settings, rich text and compressed photos.")
            }

            Section("System Device Backup") {
                Text("SwiftData and owned photos live in backed-up Application Support locations. iOS may include them in normal device backups according to your device settings. This is not CloudKit sync.")
                    .font(.footnote)
            }

            Section {
                Button("Reset App Data", systemImage: "trash", role: .destructive) {
                    showResetConfirmation = true
                }
            } header: {
                Text("Reset")
            } footer: {
                Text("Reset does not revoke permissions already granted in iOS Settings.")
            }
        }
        .brandedNavigationTitle("Backup & Reset")
        .overlay {
            if backupService.isWorking {
                ProgressView("Working…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 14))
            }
        }
        .fileImporter(isPresented: $chooseDirectory, allowedContentTypes: [.folder]) { result in
            do { try backupService.chooseBackupDirectory(try result.get()) }
            catch { errorMessage = "The backup location could not be saved. Choose another directory." }
        }
        .fileImporter(isPresented: $chooseRestoreFile, allowedContentTypes: [.parmaBackup, .json]) { result in
            do {
                pendingRestoreURL = try result.get()
                showRestoreConfirmation = true
            } catch {
                errorMessage = "The backup file could not be opened."
            }
        }
        .confirmationDialog("Replace all current app data?", isPresented: $showRestoreConfirmation, titleVisibility: .visible) {
            Button("Restore and Replace", role: .destructive) { restoreBackup() }
            Button("Cancel", role: .cancel) { pendingRestoreURL = nil }
        } message: {
            Text("Restore replaces all entries, history, photos and settings after validating the backup. It does not merge data.")
        }
        .confirmationDialog("Reset Parma Master?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset Everything", role: .destructive) { resetApp() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all entries, rating history, photos, backup location, settings and onboarding state.")
        }
        .alert("Backup & Reset", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "The operation could not be completed.")
        }
    }

    private func performBackup() {
        do { try backupService.backupNow() }
        catch { errorMessage = (error as? LocalizedError)?.errorDescription ?? "The backup destination is unavailable. The previous backup was left unchanged." }
    }

    private func restoreBackup() {
        guard let pendingRestoreURL else { return }
        do {
            try backupService.restore(from: pendingRestoreURL)
            self.pendingRestoreURL = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The backup could not be restored. Current data was not intentionally changed."
        }
    }

    private func resetApp() {
        do {
            try EntryRepository.reset(photoStore: photoStore, in: modelContext)
            backupService.clearBackupDirectory()
            pubDetection.clearVisitState()
            locationService.stopUpdates()
            settings.reset()
        } catch {
            errorMessage = "Some app data could not be reset. Please try again."
        }
    }
}
