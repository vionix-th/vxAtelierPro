import Foundation
import SwiftUI

private enum RecoveryImportMode {
    case backup
    case genericImport
}

/// Startup recovery view shown when recovery launch is active.
struct StartupRecoveryView: View {
    @State private var confirmation: SettingsConfirmation?
    @State private var completionMessage = ""
    @State private var showCompletionAlert = false
    @State private var showFileImporter = false
    @State private var selectedImportMode: RecoveryImportMode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDefaults.paddingLarge) {
                VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                    Text("Startup Recovery")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Recovery launch bypasses normal shell so local settings and stored data can be repaired before app starts normally.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                    recoveryActionButton(
                        title: "Reset Settings",
                        systemImage: "arrow.uturn.backward.circle.fill"
                    ) {
                        confirmation = SettingsConfirmation(
                            title: "Reset Settings",
                            message: "Reset all application settings to their default values? The app will remain in recovery mode.",
                            confirmTitle: "Reset",
                            action: { _ in
                                AppDefaults.resetUserDefaults()
                                showCompletion(
                                    message: "Application settings reset to defaults. Relaunch app when ready."
                                )
                            }
                        )
                    }

                    recoveryActionButton(
                        title: "Wipe Store",
                        systemImage: "trash.circle.fill",
                        role: .destructive
                    ) {
                        confirmation = SettingsConfirmation(
                            title: "Wipe Store",
                            message: "Delete local SwiftData store and open a fresh empty state?",
                            confirmTitle: "Wipe",
                            action: { _ in
                                Task { @MainActor in
                                    await wipeStore()
                                }
                            }
                        )
                    }

                    recoveryActionButton(
                        title: "Restore Backup",
                        systemImage: "arrow.down.doc",
                        role: .destructive
                    ) {
                        confirmation = SettingsConfirmation(
                            title: "Restore Backup",
                            message: "Choose full backup file next. Current local store will be replaced after file is validated.",
                            confirmTitle: "Choose File",
                            action: { _ in
                                selectedImportMode = .backup
                                showFileImporter = true
                            }
                        )
                    }

                    recoveryActionButton(
                        title: "Generic Import",
                        systemImage: "square.and.arrow.down",
                        role: .destructive
                    ) {
                        confirmation = SettingsConfirmation(
                            title: "Generic Import",
                            message: "Choose project, conversation, prompt, voice, or model JSON file next. Current local store will be replaced after validation.",
                            confirmTitle: "Choose File",
                            action: { _ in
                                selectedImportMode = .genericImport
                                showFileImporter = true
                            }
                        )
                    }
                }

                VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                    Text("Notes")
                        .font(.headline)
                    Text("Reset Settings only changes UserDefaults. Wipe Store deletes local data. Restore Backup and Generic Import validate file first, then wipe and repopulate local store.")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, AppDefaults.paddingSmall)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .alert(completionMessage, isPresented: $showCompletionAlert) {
            Button("OK", role: .cancel) { }
        }
        .settingsConfirmationDialog($confirmation)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            guard let selectedImportMode else { return }
            self.selectedImportMode = nil

            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { @MainActor in
                    await performRecoveryImport(mode: selectedImportMode, url: url)
                }
            case .failure(let error):
                if (error as NSError).code != CocoaError.userCancelled.rawValue {
                    showCompletion(message: "Recovery import failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func showCompletion(message: String) {
        completionMessage = message
        showCompletionAlert = true
    }

    @MainActor
    private func wipeStore() async {
        do {
            try AppRecoveryService.wipePersistentStore()

            #if os(macOS)
                try AppRecoveryService.relaunchNormalApp()
            #else
                showCompletion(message: "Store wiped. Close and relaunch app to start with empty data.")
            #endif
        } catch {
            showCompletion(message: "Store wipe failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func performRecoveryImport(mode: RecoveryImportMode, url: URL) async {
        do {
            switch mode {
            case .backup:
                try await AppRecoveryService.validateBackup(from: url)
            case .genericImport:
                try await AppRecoveryService.validateImport(from: url)
            }

            try AppRecoveryService.wipePersistentStore()

            let bootstrap = AppBootstrap.live()
            switch mode {
            case .backup:
                try await DataManager.shared.restoreBackup(from: url, into: bootstrap.modelContainer.mainContext)
            case .genericImport:
                _ = try await DataManager.shared.importData(from: url, into: bootstrap.modelContainer.mainContext)
            }
            bootstrap.queryManager.ensureSystemConversation()

            #if os(macOS)
                try AppRecoveryService.relaunchNormalApp()
            #else
                showCompletion(message: "Recovery import completed. Close and relaunch app to use repaired data.")
            #endif
        } catch {
            showCompletion(message: "Recovery import failed: \(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private func recoveryActionButton(
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
        .buttonStyle(.bordered)
    }
}
