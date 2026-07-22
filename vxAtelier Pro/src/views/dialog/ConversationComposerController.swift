import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ConversationComposerController {
    private let queryManager: QueryManager
    private let responseUseCase: ConversationResponseUseCase
    private let resolveConversation: @MainActor () throws -> ConversationItem
    private let didCompleteConversation: ((PersistentIdentifier) -> Void)?

    @ObservationIgnored private var sendTask: Task<Void, Never>?

    let draftStore: ConversationDraftStore
    var message = ""
    var isPromptTemplatesPresented = false
    var isTaskRunning = false
    var showError = false
    var errorMessage = ""
    var isInputFocused: Bool

    init(
        queryManager: QueryManager,
        responseUseCase: ConversationResponseUseCase? = nil,
        draftStore: ConversationDraftStore,
        focusOnAppear: Bool,
        resolveConversation: @escaping @MainActor () throws -> ConversationItem,
        didCompleteConversation: ((PersistentIdentifier) -> Void)? = nil
    ) {
        self.queryManager = queryManager
        self.responseUseCase = responseUseCase ?? .shared
        self.draftStore = draftStore
        self.resolveConversation = resolveConversation
        self.didCompleteConversation = didCompleteConversation
        self.isInputFocused = focusOnAppear
    }

    func applyTemplate(id: PersistentIdentifier, conversation: ConversationItem?) {
        guard let template = queryManager.promptTemplate(with: id) else { return }
        message = expandVariables(template.prompt, conversation: conversation)
    }

    func send(autoNameConversations: Bool) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            vxAtelierPro.log.info("Ignoring empty message")
            return
        }

        sendTask?.cancel()
        draftStore.reset()
        isTaskRunning = true
        let originalMessage = message
        var startedTurnID: PersistentIdentifier?

        sendTask = Task { @MainActor in
            defer {
                self.isTaskRunning = false
                self.isInputFocused = true
                self.sendTask = nil
            }

            do {
                let conversation = try self.resolveConversation()
                self.autoNameIfNeeded(
                    conversation: conversation,
                    sourceText: originalMessage,
                    autoNameConversations: autoNameConversations
                )

                try await self.responseUseCase.sendMessage(
                    expandVariables(originalMessage, conversation: conversation),
                    in: conversation,
                    draftStore: self.draftStore,
                    onTurnStarted: { turnID in
                        startedTurnID = turnID
                        self.message = ""
                    }
                )
                try self.queryManager.saveContext()
                self.didCompleteConversation?(conversation.persistentModelID)
                vxAtelierPro.log.notice("Message sent and completed successfully")
            } catch {
                self.restoreMessageIfTurnWasRolledBack(
                    originalMessage,
                    startedTurnID: startedTurnID
                )
                guard !Task.isCancelled else { return }
                vxAtelierPro.log.error("Failed to complete message - \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                self.showError = true
            }
        }
    }

    private func restoreMessageIfTurnWasRolledBack(
        _ originalMessage: String,
        startedTurnID: PersistentIdentifier?
    ) {
        guard let startedTurnID,
              message.isEmpty,
              let conversation = try? resolveConversation(),
              queryManager.turn(with: startedTurnID, in: conversation) == nil else {
            return
        }
        message = originalMessage
    }

    private func autoNameIfNeeded(
        conversation: ConversationItem,
        sourceText: String,
        autoNameConversations: Bool
    ) {
        guard autoNameConversations,
              conversation.turns.isEmpty,
              conversation.title == AppDefaults.newConversationName else {
            return
        }

        let separators = CharacterSet(charactersIn: "\n\r.:;")
        var title = sourceText.components(separatedBy: separators).first ?? ""
        if title.isEmpty {
            title = sourceText
        }
        if title.lengthOfBytes(using: .utf8) > 64 {
            title = title.prefix(64) + "..."
        }
        guard !title.isEmpty else { return }

        conversation.title = title
        vxAtelierPro.log.notice("Auto-named conversation to '\(title)'")
    }
}
