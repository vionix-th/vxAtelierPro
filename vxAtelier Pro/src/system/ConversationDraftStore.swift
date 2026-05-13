import Foundation
import Observation
import SwiftData

struct ConversationDraft: Equatable {
    var text: String = ""
    var isActive: Bool = false
    var toolCalls: [LLMToolCall] = []
    var runStatus: LLMRunStatus = .pending
    var errorMessage: String?
}

@MainActor
@Observable
final class ConversationDraftStore {
    private var drafts: [PersistentIdentifier: ConversationDraft] = [:]
    private var activeConversationID: PersistentIdentifier?

    var text: String {
        get { activeDraft.text }
        set { mutateActive { $0.text = newValue } }
    }

    var isActive: Bool {
        get { activeDraft.isActive }
        set { mutateActive { $0.isActive = newValue } }
    }

    var toolCalls: [LLMToolCall] {
        get { activeDraft.toolCalls }
        set { mutateActive { $0.toolCalls = newValue } }
    }

    var hasToolCallsOnly: Bool {
        activeDraft.text.isEmpty && !activeDraft.toolCalls.isEmpty
    }

    private var activeDraft: ConversationDraft {
        guard let activeConversationID else { return ConversationDraft() }
        return drafts[activeConversationID] ?? ConversationDraft()
    }

    func draft(for conversationID: PersistentIdentifier) -> ConversationDraft {
        drafts[conversationID] ?? ConversationDraft()
    }

    func activate(conversationID: PersistentIdentifier) {
        activeConversationID = conversationID
        if drafts[conversationID] == nil {
            drafts[conversationID] = ConversationDraft()
        }
    }

    func reset(conversationID: PersistentIdentifier? = nil) {
        let id = conversationID ?? activeConversationID
        guard let id else { return }
        drafts[id] = ConversationDraft()
    }

    func start(conversationID: PersistentIdentifier) {
        activeConversationID = conversationID
        drafts[conversationID] = ConversationDraft(isActive: true, runStatus: .streaming)
    }

    func appendContent(_ content: String, conversationID: PersistentIdentifier? = nil) {
        mutate(conversationID: conversationID) { draft in
            draft.text += content
            draft.isActive = true
            draft.runStatus = .streaming
        }
    }

    func updateToolCalls(_ newToolCalls: [LLMToolCall], conversationID: PersistentIdentifier? = nil) {
        mutate(conversationID: conversationID) { draft in
            var toolCalls = draft.toolCalls
            for call in newToolCalls {
                Self.upsertSnapshot(call, into: &toolCalls)
            }
            draft.toolCalls = toolCalls.sorted { $0.index < $1.index }
            draft.isActive = true
            draft.runStatus = .awaitingTools
        }
    }

    func complete(conversationID: PersistentIdentifier? = nil) {
        mutate(conversationID: conversationID) { draft in
            draft.isActive = false
            draft.runStatus = .completed
        }
    }

    func fail(_ error: Error, conversationID: PersistentIdentifier? = nil) {
        mutate(conversationID: conversationID) { draft in
            draft.isActive = false
            draft.runStatus = .failed
            draft.errorMessage = error.localizedDescription
        }
    }

    private func mutateActive(_ body: (inout ConversationDraft) -> Void) {
        mutate(conversationID: activeConversationID, body)
    }

    private func mutate(conversationID: PersistentIdentifier?, _ body: (inout ConversationDraft) -> Void) {
        guard let id = conversationID ?? activeConversationID else { return }
        activeConversationID = id
        var draft = drafts[id] ?? ConversationDraft()
        body(&draft)
        drafts[id] = draft
    }

    private static func upsertSnapshot(_ call: LLMToolCall, into calls: inout [LLMToolCall]) {
        if let existingIndex = calls.firstIndex(where: { existing in
            existing.index == call.index || existing.id == call.id || (call.callID != nil && existing.callID == call.callID)
        }) {
            calls[existingIndex] = call
        } else {
            calls.append(call)
        }
    }
}
