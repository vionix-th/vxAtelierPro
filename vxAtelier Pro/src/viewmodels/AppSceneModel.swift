import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class AppSceneModel {
    enum PresentedSheet: Identifiable {
        case logHistory(UUID)
        #if os(iOS)
            case applicationSettings(SettingsDestination?, UUID)
        #endif
        case conversationOptions(PersistentIdentifier, UUID)
        case modelSelection(PersistentIdentifier, UUID)
        case tts(UUID)

        var id: UUID {
            switch self {
            case .logHistory(let id),
                 .conversationOptions(_, let id),
                 .modelSelection(_, let id),
                 .tts(let id):
                return id
            #if os(iOS)
            case .applicationSettings(_, let id):
                return id
            #endif
            }
        }
    }

    enum ExportRequest: Identifiable {
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

    let router = NavigationRouter()
    var presentedSheet: PresentedSheet?
    var exportRequest: ExportRequest?
    var importRequested: Bool = false
    var utilityPanelRequestID: UUID?
    var focusedConversationID: PersistentIdentifier?
    #if os(macOS)
        var openSettingsSceneRequestID: UUID?
    #endif

    private let modelContext: ModelContext
    @ObservationIgnored
    private var pendingSheetTask: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var exportTaskID: UUID? {
        exportRequest?.id
    }

    var importRequestFlag: Bool {
        importRequested
    }

    func requestOptions(for id: PersistentIdentifier) {
        vxAtelierPro.log.debug("AppSceneModel: options requested for conversation id \(id)")
        presentSheet(.conversationOptions(id, UUID()))
    }

    func requestModelSelection(for id: PersistentIdentifier) {
        vxAtelierPro.log.debug("AppSceneModel: model selection requested for conversation id \(id)")
        presentSheet(.modelSelection(id, UUID()))
    }

    func requestExport(project: ProjectItem) {
        exportRequest = .project(project, UUID())
    }

    func requestExport(conversation: ConversationItem) {
        exportRequest = .conversation(conversation, UUID())
    }

    func requestImport() {
        importRequested = true
    }

    func requestSettings(_ destination: SettingsDestination?) {
        #if os(iOS)
            presentSheet(.applicationSettings(destination, UUID()))
        #else
            selectMacOSSettingsDestination(destination)
            openSettingsSceneRequestID = UUID()
        #endif
    }

    func requestTTS() {
        presentSheet(.tts(UUID()))
    }

    func requestLogHistory() {
        presentSheet(.logHistory(UUID()))
    }

    func focusConversation(_ conversationID: PersistentIdentifier) {
        guard focusedConversationID != conversationID else { return }
        focusedConversationID = conversationID
    }

    func clearConversationFocus(_ conversationID: PersistentIdentifier) {
        guard focusedConversationID == conversationID else { return }
        focusedConversationID = nil
    }

    func requestUtilityPanel() {
        utilityPanelRequestID = UUID()
    }

    func handleTTSPlayback(isPlaying: Bool) {
        if isPlaying {
            vxAtelierPro.log.info("TTS playback started")
            requestTTS()
        }
    }

    private func presentSheet(_ sheet: PresentedSheet) {
        pendingSheetTask?.cancel()
        pendingSheetTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            presentedSheet = sheet
            pendingSheetTask = nil
        }
    }

    #if os(macOS)
        private func selectMacOSSettingsDestination(_ destination: SettingsDestination?, defaults: UserDefaults = .standard) {
            let resolvedDestination = destination ?? .general
            defaults.set(resolvedDestination.rawValue, forKey: AppSettings.Keys.selectedSettingsDestination)
            defaults.set(
                MacOSSettingsSection.section(containing: resolvedDestination).rawValue,
                forKey: AppSettings.Keys.selectedMacSettingsSection
            )
        }
    #endif

    func exportTask() async {
        guard let request = exportRequest else { return }

        do {
            switch request {
            case .project(let project, _):
                try await DataManager.shared.exportProject(project)
                await MainActor.run {
                    vxAtelierPro.log.info("Successfully exported project '\(project.name)'.")
                }
            case .conversation(let conversation, _):
                try await DataManager.shared.exportConversation(conversation)
                await MainActor.run {
                    vxAtelierPro.log.info("Successfully exported conversation '\(conversation.title)'.")
                }
            }
        } catch {
            let itemType: String
            switch request {
            case .project:
                itemType = "project"
            case .conversation:
                itemType = "conversation"
            }
            await MainActor.run {
                vxAtelierPro.log.error("Export \(itemType) failed: \(error.localizedDescription)")
            }
        }

        exportRequest = nil
    }

    func importTask() async {
        guard importRequested else { return }

        defer { importRequested = false }

        do {
            let importedItem = try await DataManager.shared.importData(into: modelContext)
            if let project = importedItem as? ProjectItem {
                router.setSelection(.project(project.id))
                router.clearPath(for: project.id)
                await MainActor.run {
                    vxAtelierPro.log.info("Successfully imported project '\(project.name)'.")
                }
            } else if let conversation = importedItem as? ConversationItem {
                router.openConversation(conversation.id, in: conversation.project?.id)
                await MainActor.run {
                    vxAtelierPro.log.info("Successfully imported conversation '\(conversation.title)'.")
                }
            } else if let promptTemplate = importedItem as? PromptTemplate {
                await MainActor.run {
                    vxAtelierPro.log.info("Successfully imported prompt template '\(promptTemplate.name)'.")
                }
            } else if let voiceConfiguration = importedItem as? VoiceConfigurationItem {
                await MainActor.run {
                    vxAtelierPro.log.info(
                        "Successfully imported voice configuration '\(voiceConfiguration.language)' for role '\(voiceConfiguration.role)'."
                    )
                }
            } else if let model = importedItem as? ModelItem {
                await MainActor.run {
                    vxAtelierPro.log.info("Successfully imported model '\(model.modelID)'.")
                }
            }
        } catch {
            await MainActor.run {
                vxAtelierPro.log.error("Import failed: \(error.localizedDescription)")
            }
        }
    }
}
