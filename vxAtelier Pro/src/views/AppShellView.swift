import Observation
import SwiftData
import SwiftUI

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(QueryManager.self) private var queryManager
    @Environment(TTSQueue.self) private var ttsQueue
    @Environment(AppSceneModel.self) private var sceneModel
    @AppStorage(AppSettings.Keys.statusBarVisible) private var statusBarVisible: Bool = AppDefaults.statusBarVisible

    var body: some View {
        @Bindable var scene = sceneModel

        VStack(spacing: 0) {
            ContentView(
                onRequestOptions: scene.requestOptions(for:),
                onRequestExportProject: scene.requestExport(project:),
                onRequestExportConversation: scene.requestExport(conversation:),
                onRequestImport: scene.requestImport,
                onRequestSettings: scene.requestSettings(_:),
                onRequestTTS: scene.requestTTS,
                onRequestLogHistory: scene.requestLogHistory
            )

            if statusBarVisible {
                StatusBar(onRequestLogHistory: scene.requestLogHistory)
            }
        }
        .environment(scene.router)
        #if os(iOS)
            .onChange(of: ttsQueue.isPlaying) {
                sceneModel.handleTTSPlayback(isPlaying: ttsQueue.isPlaying)
            }
        #else
            .onChange(of: ttsQueue.isPlaying) { _, _ in
                sceneModel.handleTTSPlayback(isPlaying: ttsQueue.isPlaying)
            }
        #endif
        .task(id: scene.exportTaskID) { await scene.exportTask() }
        .task(id: scene.importRequestFlag) { await scene.importTask() }
        .sheet(isPresented: $scene.isLogHistoryShown) {
            LogHistorySheet()
        }
        // Present Settings from the toolbar menu entry
        .sheet(
            isPresented: $scene.applicationSettingsViewIsPresented,
            onDismiss: {
                scene.settingsInitialTab = nil
            }
        ) {
            ApplicationSettingsView(initialTab: scene.settingsInitialTab)
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
            item: $scene.optionsSheetID,
            onDismiss: {
                vxAtelierPro.log.debug("AppShellView: options sheet dismissed (onDismiss)")
            }
        ) { (conversationID: PersistentIdentifier) in
            if let dialog = queryManager.conversation(with: conversationID) {
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
                        "AppShellView: options sheet waiting for conversation to resolve (requested id: \(conversationID))"
                    )
                }
            }
        }
        // TTS playlist sheet
        .sheet(isPresented: $scene.ttsViewIsPresented) {
            TTSControlView()
                .onAppear { vxAtelierPro.log.debug("AppShellView: TTSControlView presented") }
        }
    }
}
