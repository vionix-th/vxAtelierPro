import SwiftUI

struct MaintenanceSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(QueryManager.self) private var queryManager
    @State private var showConfirmation: Bool = false
    @State private var confirmationContext: ConfirmationContext? = nil
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

    private func handleConfirmation() {
        switch confirmationContext {
        case .resetToDefaults:
            resetToDefaults()
        case .cleanLocalStorage:
            cleanLocalStorage()
        case .restoreDatabase:
            showBackupImporter = true
        default:
            break
        }
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
        ScrollView {
            VStack(spacing: AppDefaults.paddingLarge) {
                SettingsSectionView(title: "Data Management") {
                    VStack(spacing: AppDefaults.paddingMedium) {
                        ActionButton(title: "Reset to Defaults", iconName: "arrow.uturn.backward.circle.fill") {
                            confirmationContext = .resetToDefaults
                            showConfirmation = true
                        }
                        ActionButton(title: "Clear Local Storage", iconName: "trash.circle.fill") {
                            confirmationContext = .cleanLocalStorage
                            showConfirmation = true
                        }
                        ActionButton(title: "Backup Database", iconName: "arrow.up.doc") {
                            Task { @MainActor in
                                do {
                                    let data = try await DataManager.shared.createBackup(from: modelContext)
                                    backupDocument = BackupDocument(backupData: data)
                                    showBackupExporter = true
                                } catch {
                                    showCompletion(message: "Database backup failed: \(error.localizedDescription)")
                                }
                            }
                        }
                        ActionButton(title: "Restore Database", iconName: "arrow.down.doc") {
                            confirmationContext = .restoreDatabase
                            showConfirmation = true
                        }
                    }
                }
            }
            .padding(.vertical, AppDefaults.paddingLarge)
        }
        .navigationTitle("Maintenance")
        .alert(completionMessage, isPresented: $showCompletionAlert) {
            Button("OK", role: .cancel) { }
        }
        .alert(
            confirmationContext?.title ?? "",
            isPresented: $showConfirmation,
            presenting: confirmationContext
        ) { context in
            Button(context.confirmButtonTitle, role: .destructive) {
                handleConfirmation()
            }
            Button("Cancel", role: .cancel) { }
        } message: { context in
            Text(context.message)
        }
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
