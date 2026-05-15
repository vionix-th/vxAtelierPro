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

    private func showCompletion(message: String) {
        completionMessage = message
        showCompletionAlert = true
    }

    private func resetToDefaults() {
        AppRecoveryService.resetUserDefaults()
        showCompletion(message: "Application settings reset to defaults.")
    }

    private func cleanLocalStorage() {
        do {
            try AppRecoveryService.cleanLocalStorage(using: queryManager)
            showCompletion(message: "Local storage cleaned.")
        } catch {
            showCompletion(message: "Failed to clean local storage: \(error.localizedDescription)")
        }
    }

    var body: some View {
        SettingsPage(title: "Maintenance") {
            SettingsFormSection("Data Management") {
                maintenanceActionButton(
                    title: "Reset to Defaults",
                    systemImage: "arrow.uturn.backward.circle.fill"
                ) {
                    confirmation = SettingsConfirmation(
                        title: "Reset to Defaults",
                        message: "Are you sure you want to reset all settings to their default values?",
                        confirmTitle: "Reset",
                        action: resetToDefaults
                    )
                }

                maintenanceActionButton(
                    title: "Clear Local Storage",
                    systemImage: "trash.circle.fill",
                    role: .destructive
                ) {
                    confirmation = SettingsConfirmation(
                        title: "Clear Local Storage",
                        message: "Are you sure you want to clear all local storage? This action cannot be undone.",
                        confirmTitle: "Clear",
                        action: cleanLocalStorage
                    )
                }

                maintenanceActionButton(
                    title: "Backup Database",
                    systemImage: "arrow.up.doc"
                ) {
                    Task { @MainActor in
                        do {
                            let data = try await AppRecoveryService.createBackup(from: modelContext)
                            backupDocument = BackupDocument(backupData: data)
                            showBackupExporter = true
                        } catch {
                            showCompletion(message: "Database backup failed: \(error.localizedDescription)")
                        }
                    }
                }

                maintenanceActionButton(
                    title: "Restore Database",
                    systemImage: "arrow.down.doc",
                    role: .destructive
                ) {
                    confirmation = SettingsConfirmation(
                        title: "Restore Database",
                        message: "Are you sure you want to restore the database? This action cannot be undone.",
                        confirmTitle: "Restore",
                        action: { showBackupImporter = true }
                    )
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
                Task { @MainActor in
                    do {
                        try await AppRecoveryService.restoreBackup(from: url, into: modelContext)
                        queryManager.ensureSystemConversation()
                        showCompletion(message: "Database restored successfully")
                    } catch {
                        showCompletion(message: "Database restore failed: \(error.localizedDescription)")
                    }
                }
            case .failure(let error):
                if (error as NSError).code != CocoaError.userCancelled.rawValue {
                    showCompletion(message: "Backup import failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @ViewBuilder
    private func maintenanceActionButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: AppDefaults.paddingSmall) {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
} 
