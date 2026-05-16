import Observation
import SwiftData
import SwiftUI

struct AppShellView: View {
    @Environment(QueryManager.self) private var queryManager
    @Environment(TTSQueue.self) private var ttsQueue
    @Environment(AppSceneModel.self) private var sceneModel
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
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
                onRequestSettings: scene.requestSettings,
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
        .onChange(of: scene.openSettingsSceneRequestID) { _, requestID in
            guard requestID != nil else { return }
            openSettings()
        }
        .onChange(of: scene.utilityPanelRequestID) { _, requestID in
            guard requestID != nil else { return }
            openWindow(id: "utilityPanel")
        }
#endif
        .sheet(item: $scene.presentedSheet) { sheet in
            switch sheet {
            case .logHistory(_):
                LogHistorySheet()
#if os(iOS)
            case .applicationSettings(let initialTab, _):
                IOSApplicationSettingsSheetView(initialDestination: initialTab)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .conversationOptions(let conversationID, _):
                conversationOptionsSheet(for: conversationID)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
#else
            case .conversationOptions(let conversationID, _):
                conversationOptionsSheet(for: conversationID)
#endif
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
            ConversationOptionsSheetView(
                initialOptions: conversation.options
            ) { updatedOptions in
                guard let resolvedConversation = queryManager.conversation(with: conversationID) else { return }
                resolvedConversation.options = updatedOptions
                do {
                    try queryManager.saveContext()
                    vxAtelierPro.log.debug(
                        "AppShellView: Saved context after options dismissed for conversation '\(resolvedConversation.title)'."
                    )
                } catch {
                    vxAtelierPro.log.error(
                        "AppShellView: Failed to save context after options dismissed: \(error.localizedDescription)"
                    )
                }
            }
            .onAppear {
                vxAtelierPro.log.debug(
                    "AppShellView: options sheet presented for conversation '\(conversation.title)' (id: \(conversation.id))"
                )
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
