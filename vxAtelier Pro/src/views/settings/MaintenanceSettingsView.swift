import SwiftUI

/// Reset, backup, and restore tools for local app data.
struct MaintenanceSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(QueryManager.self) private var queryManager
    @State private var confirmation: SettingsConfirmation?
    @State private var showBackupExporter = false
    @State private var showBackupImporter = false
    @State private var backupDocument: BackupDocument? = nil
    @State private var completionMessage: String = ""
    @State private var showCompletionAlert = false
    @State private var restoreError: Error? = nil

    private func showCompletion(message: String) {
        completionMessage = message
        showCompletionAlert = true
    }

    private func resetToDefaults() {
        AppDefaults.resetUserDefaults()
        showCompletion(message: "Application settings reset to defaults.")
    }

    private func cleanLocalStorage() {
        do {
            try queryManager.cleanLocalStorage()
            showCompletion(message: "Local storage cleaned.")
        } catch {
            showCompletion(message: "Failed to clean local storage: \(error.localizedDescription)")
        }
    }

    var body: some View {
        SettingsPage(title: "Maintenance") {
            SettingsFormSection("Data Management") {
                Button {
                    confirmation = SettingsConfirmation(
                        title: "Reset to Defaults",
                        message: "Are you sure you want to reset all settings to their default values?",
                        confirmTitle: "Reset",
                        action: resetToDefaults
                    )
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.uturn.backward.circle.fill")
                }

                Button(role: .destructive) {
                    confirmation = SettingsConfirmation(
                        title: "Clear Local Storage",
                        message: "Are you sure you want to clear all local storage? This action cannot be undone.",
                        confirmTitle: "Clear",
                        action: cleanLocalStorage
                    )
                } label: {
                    Label("Clear Local Storage", systemImage: "trash.circle.fill")
                }

                Button {
                    Task { @MainActor in
                        do {
                            let data = try await DataManager.shared.createBackup(from: modelContext)
                            backupDocument = BackupDocument(backupData: data)
                            showBackupExporter = true
                        } catch {
                            showCompletion(message: "Database backup failed: \(error.localizedDescription)")
                        }
                    }
                } label: {
                    Label("Backup Database", systemImage: "arrow.up.doc")
                }

                Button(role: .destructive) {
                    confirmation = SettingsConfirmation(
                        title: "Restore Database",
                        message: "Are you sure you want to restore the database? This action cannot be undone.",
                        confirmTitle: "Restore",
                        action: { showBackupImporter = true }
                    )
                } label: {
                    Label("Restore Database", systemImage: "arrow.down.doc")
                }
            }
        }
        .alert(completionMessage, isPresented: $showCompletionAlert) {
            Button("OK", role: .cancel) { }
        }
        .settingsConfirmationDialog($confirmation)
        .fileExporter(
            isPresented: $showBackupExporter,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "vxAtelierPro-backup.json"
        ) { result in
            switch result {
            case .success:
                showCompletion(message: "Database backup completed successfully")
            case .failure(let error):
                showCompletion(message: "Backup export failed: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $showBackupImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else {
                    showCompletion(message: "Permission denied: could not access selected backup file.")
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try Data(contentsOf: url)
                    Task { @MainActor in
                        do {
                            try await DataManager.shared.restoreBackup(from: data, into: modelContext)
                            queryManager.ensureSystemConversation()
                            showCompletion(message: "Database restored successfully")
                        } catch {
                            showCompletion(message: "Database restore failed: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    showCompletion(message: "Failed to read selected backup file: \(error.localizedDescription)")
                }
            case .failure(let error):
                showCompletion(message: "Backup import failed: \(error.localizedDescription)")
            }
        }
    }
} 
