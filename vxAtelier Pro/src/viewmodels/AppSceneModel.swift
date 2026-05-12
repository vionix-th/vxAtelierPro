import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class AppSceneModel {
    enum PresentedSheet: Identifiable {
        case logHistory(UUID)
        case applicationSettings(ApplicationSettingsView.SettingsTab?, UUID)
        case conversationOptions(PersistentIdentifier, UUID)
        case modelSelection(PersistentIdentifier, UUID)
        case tts(UUID)

        var id: UUID {
            switch self {
            case .logHistory(let id),
                 .applicationSettings(_, let id),
                 .conversationOptions(_, let id),
                 .modelSelection(_, let id),
                 .tts(let id):
                return id
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

    var router = NavigationRouter()
    var presentedSheet: PresentedSheet?
    var exportRequest: ExportRequest?
    var importRequested: Bool = false
    var utilityPanelRequestID: UUID?

    private let queryManager: QueryManager
    private let modelContext: ModelContext
    @ObservationIgnored
    private var pendingSheetTask: Task<Void, Never>?

    init(queryManager: QueryManager, modelContext: ModelContext) {
        self.queryManager = queryManager
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

    func requestSettings(_ tab: ApplicationSettingsView.SettingsTab?) {
        presentSheet(.applicationSettings(tab, UUID()))
    }

    func requestTTS() {
        presentSheet(.tts(UUID()))
    }

    func requestLogHistory() {
        presentSheet(.logHistory(UUID()))
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
                try queryManager.insert(project)
                router.setSelection(.project(project.id))
                router.clearPath(for: project.id)
                await MainActor.run {
                    vxAtelierPro.log.info("Successfully imported project '\(project.name)'.")
                }
            } else if let conversation = importedItem as? ConversationItem {
                try queryManager.insert(conversation)
                router.openConversation(conversation.id, in: conversation.project?.id)
                await MainActor.run {
                    vxAtelierPro.log.info("Successfully imported conversation '\(conversation.title)'.")
                }
            }
        } catch {
            await MainActor.run {
                vxAtelierPro.log.error("Import failed: \(error.localizedDescription)")
            }
        }
    }
}
