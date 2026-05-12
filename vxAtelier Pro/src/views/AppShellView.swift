import Observation
import SwiftData
import SwiftUI

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(QueryManager.self) private var queryManager
    @Environment(TTSQueue.self) private var ttsQueue
    @Environment(AppSceneModel.self) private var sceneModel
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif
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
                StatusBar(
                    onRequestLogHistory: scene.requestLogHistory,
                    onRequestModelSelection: scene.requestModelSelection(for:)
                )
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
        #if os(macOS)
            .onChange(of: scene.utilityPanelRequestID) { _, requestID in
                guard requestID != nil else { return }
                openWindow(id: "utilityPanel")
            }
        #endif
        .sheet(item: $scene.presentedSheet) { sheet in
            switch sheet {
            case .logHistory(_):
                LogHistorySheet()
            case .applicationSettings(let initialTab, _):
                ApplicationSettingsView(initialTab: initialTab)
                    .environment(queryManager)
                    .environment(\.modelContext, modelContext)
                    #if os(macOS)
                        .frame(idealWidth: 900, idealHeight: 640)
                    #else
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                    #endif
            case .conversationOptions(let conversationID, _):
                conversationOptionsSheet(for: conversationID)
            case .modelSelection(let conversationID, _):
                modelSelectionSheet(for: conversationID)
            case .tts(_):
                TTSControlView()
                    .onAppear { vxAtelierPro.log.debug("AppShellView: TTSControlView presented") }
            }
        }
    }

    @ViewBuilder
    private func conversationOptionsSheet(for conversationID: PersistentIdentifier) -> some View {
        if let conversation = queryManager.conversation(with: conversationID) {
            ConversationOptionsView(
                options: Binding(get: { conversation.options }, set: { conversation.options = $0 })
            )
            .onAppear {
                vxAtelierPro.log.debug(
                    "AppShellView: options sheet presented for conversation '\(conversation.title)' (id: \(conversation.id))"
                )
            }
            .onDisappear {
                do {
                    try queryManager.saveContext()
                    vxAtelierPro.log.debug(
                        "AppShellView: Saved context after options dismissed for conversation '\(conversation.title)'."
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
                Text("Preparing options...")
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

    @ViewBuilder
    private func modelSelectionSheet(for conversationID: PersistentIdentifier) -> some View {
        if let conversation = queryManager.conversation(with: conversationID),
           let apiConfiguration = conversation.options.apiConfiguration {
            ModelSelectionView(
                selectedModel: conversation.options.selectedModelID
                    ?? apiConfiguration.defaultModelID
                    ?? "",
                onModelSelected: { newModel in
                    do {
                        try queryManager.setModel(newModel, for: conversation)
                    } catch {
                        vxAtelierPro.log.error("Failed to set model \(newModel): \(error.localizedDescription)")
                    }
                },
                apiConfiguration: apiConfiguration
            )
        } else {
            VStack(spacing: AppDefaults.paddingMedium) {
                ProgressView()
                Text("Preparing models...")
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 300, minHeight: 200)
        }
    }
}
