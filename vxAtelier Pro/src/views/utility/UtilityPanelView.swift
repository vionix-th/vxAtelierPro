#if os(macOS)
import SwiftData
import SwiftUI

struct UtilityPanelView: View {
    @Environment(QueryManager.self) private var queryManager
    @Environment(AppSceneModel.self) private var sceneModel
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var conversationID: PersistentIdentifier?
    @State private var draftStore = ConversationDraftStore()
    @State private var errorAlert: ErrorAlert?

    var body: some View {
        Group {
            if let conversation {
                MessageInputView(
                    queryManager: queryManager,
                    draftStore: draftStore,
                    contextConversation: conversation,
                    focusInputOnAppear: true,
                    resolveConversation: {
                        guard let resolved = self.conversation else {
                            throw AppError.invalidOperation("Conversation not found")
                        }
                        return resolved
                    },
                    didSend: { conversation in
                        sceneModel.router.openConversation(conversation.id, in: nil)
                        dismissWindow(id: "utilityPanel")
                    }
                )
            } else {
                ProgressView()
                    .frame(width: 420, height: 120)
            }
        }
        .frame(minWidth: 420, idealWidth: 420, maxWidth: 560, minHeight: 120)
        .task {
            resolveUtilityConversation()
        }
        .errorAlert(error: $errorAlert)
    }

    private var conversation: ConversationItem? {
        guard let conversationID else { return nil }
        return queryManager.conversation(with: conversationID)
    }

    private func resolveUtilityConversation() {
        do {
            let conversation = try queryManager.ensureUtilityPanelConversation()
            conversationID = conversation.id
        } catch {
            vxAtelierPro.log.error("Failed to resolve utility conversation: \(error.localizedDescription)")
            errorAlert = ErrorAlert(error: error)
        }
    }
}
#endif
