import SwiftData
import SwiftUI

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(QueryManager.self) private var queryManager
    @Environment(TTSQueue.self) private var ttsQueue
    @AppStorage(AppSettings.Keys.statusBarVisible) private var statusBarVisible: Bool = AppDefaults.statusBarVisible
    @State private var router = NavigationRouter()
    @State private var applicationSettingsViewIsPresented: Bool = false
    @State private var ttsViewIsPresented: Bool = false
    @State private var settingsInitialTab: ApplicationSettingsView.SettingsTab? = nil
    @State private var optionsSheetKey: OptionsSheetKey?
    @State private var exportRequest: ExportRequest?
    @State private var importRequested = false
    @State private var isLogHistoryShown: Bool = false

    // todo: having this structure is suspicious as PersistentIdentifier is already Identifiable
    private struct OptionsSheetKey: Identifiable { let id: PersistentIdentifier }

    private enum ExportRequest: Identifiable {
        case project(ProjectItem, UUID)
        case conversation(ConversationItem, UUID)

        var id: UUID {
            switch self {
            case .project(_, let id):
                return id
            case .conversation(_, let id):
                return id
            }
        }
    }

    private func requestOptions(for id: PersistentIdentifier) {
        vxAtelierPro.log.debug("AppShellView: options requested for dialog id \(id)")
        optionsSheetKey = OptionsSheetKey(id: id)
    }

    private func requestExport(project: ProjectItem) {
        exportRequest = .project(project, UUID())
    }

    private func requestExport(conversation: ConversationItem) {
        exportRequest = .conversation(conversation, UUID())
    }

    private func requestImport() {
        importRequested = true
    }

    private func requestSettings(_ tab: ApplicationSettingsView.SettingsTab?) {
        settingsInitialTab = tab
        applicationSettingsViewIsPresented = true
    }

    private func requestTTS() {
        ttsViewIsPresented = true
    }

    private func requestLogHistory() {
        isLogHistoryShown = true
    }

    var body: some View {
        VStack(spacing: 0) {
            ContentView(
                onRequestOptions: requestOptions(for:),
                onRequestExportProject: requestExport(project:),
                onRequestExportConversation: requestExport(conversation:),
                onRequestImport: requestImport,
                onRequestSettings: requestSettings(_:),
                onRequestTTS: requestTTS,
                onRequestLogHistory: requestLogHistory
            )

            if statusBarVisible {
                StatusBar(onRequestLogHistory: requestLogHistory)
            }
        }
        .environment(router)
        #if os(iOS)
            .onChange(of: ttsQueue.isPlaying) {
                if ttsQueue.isPlaying {
                    vxAtelierPro.log.info("TTS playback started")
                    ttsViewIsPresented = true
                }
            }
        #else
            .onChange(of: ttsQueue.isPlaying) { _, _ in
                if ttsQueue.isPlaying {
                    vxAtelierPro.log.info("TTS playback started")
                    ttsViewIsPresented = true
                }
            }
        #endif
        .task(id: exportRequest?.id) { await exportTask(for: exportRequest) }
        .task(id: importRequested) { await importTask() }
        .sheet(isPresented: $isLogHistoryShown) {
            LogHistorySheet()
        }
        // Present Settings from the toolbar menu entry
        .sheet(
            isPresented: $applicationSettingsViewIsPresented,
            onDismiss: {
                settingsInitialTab = nil
            }
        ) {
            ApplicationSettingsView(initialTab: settingsInitialTab)
                .environment(queryManager)
                .environment(\.modelContext, modelContext)
                #if os(macOS)
                    .frame(idealWidth: 900, idealHeight: 640)
                #else
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                #endif
        }
        // Hoisted dialog options sheet (stable parent anchor)
        .sheet(
            item: $optionsSheetKey,
            onDismiss: {
                vxAtelierPro.log.debug("AppShellView: options sheet dismissed (onDismiss)")
            }
        ) { key in
            if let dialog = queryManager.conversation(with: key.id) {
                ConversationOptionsView(
                    options: Binding(get: { dialog.options }, set: { dialog.options = $0 })
                )
                .onAppear {
                    vxAtelierPro.log.debug(
                        "AppShellView: options sheet presented for dialog '\(dialog.title)' (id: \(dialog.id))"
                    )
                }
                .onDisappear {
                    do {
                        try queryManager.saveContext()
                        vxAtelierPro.log.debug(
                            "AppShellView: Saved context after options dismissed for dialog '\(dialog.title)'."
                        )
                    } catch {
                        vxAtelierPro.log.error(
                            "AppShellView: Failed to save context after options dismissed: \(error.localizedDescription)"
                        )
                    }
                }
            } else {
                VStack(spacing: AppDefaults.paddingMedium) {
                    ProgressView()
                    Text("Preparing options…")
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 300, minHeight: 200)
                .onAppear {
                    vxAtelierPro.log.debug(
                        "AppShellView: options sheet waiting for conversation to resolve (requested id: \(key.id))"
                    )
                }
            }
        }
        // TTS playlist sheet
        .sheet(isPresented: $ttsViewIsPresented) {
            TTSControlView()
                .onAppear { vxAtelierPro.log.debug("AppShellView: TTSControlView presented") }
        }
    }

    // MARK: - Async Tasks

    /// Generic export task for Projects or Dialogs.
    @MainActor
    private func exportTask(for request: ExportRequest?) async {
        guard let request = request else { return }

        do {
            switch request {
            case .project(let project, _):
                try await DataManager.shared.exportProject(project)
                vxAtelierPro.log.info("Successfully exported project '\(project.name)'.")
            case .conversation(let conversation, _):
                try await DataManager.shared.exportDialog(conversation)
                vxAtelierPro.log.info("Successfully exported conversation '\(conversation.title)'.")
            }
        } catch {
            let itemType: String
            switch request {
            case .project:
                itemType = "project"
            case .conversation:
                itemType = "dialog"
            }
            vxAtelierPro.log.error("Export \(itemType) failed: \(error.localizedDescription)")
        }
        exportRequest = nil
    }

    /// Task to handle importing data.
    @MainActor
    private func importTask() async {
        if importRequested {
            defer { importRequested = false }
            do {
                let importedItem = try await DataManager.shared.importData(into: modelContext)
                if let project = importedItem as? ProjectItem {
                    try queryManager.insert(project)
                    router.setSelection(.project(project.id))
                    router.clearPath(for: project.id)
                    vxAtelierPro.log.info("Successfully imported project '\(project.name)'.")
                } else if let dialog = importedItem as? ConversationItem {
                    try queryManager.insert(dialog)
                    router.openConversation(dialog.id, in: dialog.project?.id)
                    vxAtelierPro.log.info("Successfully imported dialog '\(dialog.title)'.")
                }
            } catch {
                vxAtelierPro.log.error("Import failed: \(error.localizedDescription)")
            }
        }
    }
}
