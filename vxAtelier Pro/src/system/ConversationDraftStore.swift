import Foundation
import Observation
import SwiftData

struct ConversationDraft: Equatable {
    var text: String = ""
    var isActive: Bool = false
    var toolCalls: [LLMToolCall] = []
    var runStatus: ProviderRunStatus = .pending
    var errorMessage: String?
}

@MainActor
@Observable
final class ConversationDraftStore {
    private var drafts: [PersistentIdentifier: ConversationDraft] = [:]
    private var activeConversationID: PersistentIdentifier?
    private(set) var isActive: Bool = false
    private(set) var revision: UInt64 = 0

    @ObservationIgnored private var pendingText: [PersistentIdentifier: String] = [:]
    @ObservationIgnored private var flushTasks: [PersistentIdentifier: Task<Void, Never>] = [:]

    private static let publicationIntervalNanoseconds: UInt64 = 33_000_000

    var text: String {
        get { activeDraft.text }
        set {
            mutateActive { $0.text = newValue }
            revision &+= 1
        }
    }

    var toolCalls: [LLMToolCall] {
        get { activeDraft.toolCalls }
        set {
            mutateActive { $0.toolCalls = newValue }
            revision &+= 1
        }
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
        isActive = drafts[conversationID]?.isActive ?? false
    }

    func reset(conversationID: PersistentIdentifier? = nil) {
        let id = conversationID ?? activeConversationID
        guard let id else { return }
        cancelPendingPublication(for: id)
        drafts[id] = ConversationDraft()
        if activeConversationID == id {
            isActive = false
        }
        revision &+= 1
    }

    func start(conversationID: PersistentIdentifier) {
        cancelPendingPublication(for: conversationID)
        activeConversationID = conversationID
        drafts[conversationID] = ConversationDraft(isActive: true, runStatus: .running)
        isActive = true
        revision &+= 1
    }

    func appendContent(_ content: String, conversationID: PersistentIdentifier? = nil) {
        guard !content.isEmpty,
              let id = conversationID ?? activeConversationID else { return }
        activeConversationID = id
        pendingText[id, default: ""] += content
        isActive = true
        schedulePublication(for: id)
    }

    func updateToolCalls(_ newToolCalls: [LLMToolCall], conversationID: PersistentIdentifier? = nil) {
        guard let id = conversationID ?? activeConversationID else { return }
        flushPendingText(for: id)
        mutate(conversationID: id) { draft in
            var toolCalls = draft.toolCalls
            for call in newToolCalls {
                Self.upsertSnapshot(call, into: &toolCalls)
            }
            draft.toolCalls = toolCalls.sorted { $0.index < $1.index }
            draft.isActive = true
            draft.runStatus = .awaitingTools
        }
        isActive = true
        revision &+= 1
    }

    func complete(conversationID: PersistentIdentifier? = nil) {
        guard let id = conversationID ?? activeConversationID else { return }
        flushPendingText(for: id)
        mutate(conversationID: id) { draft in
            draft.isActive = false
            draft.runStatus = .completed
        }
        isActive = false
        revision &+= 1
    }

    func fail(_ error: Error, conversationID: PersistentIdentifier? = nil) {
        guard let id = conversationID ?? activeConversationID else { return }
        flushPendingText(for: id)
        mutate(conversationID: id) { draft in
            draft.isActive = false
            draft.runStatus = .failed
            draft.errorMessage = error.localizedDescription
        }
        isActive = false
        revision &+= 1
    }

    private func mutateActive(_ body: (inout ConversationDraft) -> Void) {
        mutate(conversationID: activeConversationID, body)
    }

    private func mutate(conversationID: PersistentIdentifier?, _ body: (inout ConversationDraft) -> Void) {
        guard let id = conversationID ?? activeConversationID else { return }
        activeConversationID = id
        body(&drafts[id, default: ConversationDraft()])
    }

    private func schedulePublication(for conversationID: PersistentIdentifier) {
        guard flushTasks[conversationID] == nil else { return }
        flushTasks[conversationID] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.publicationIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            self?.flushPendingText(for: conversationID)
        }
    }

    private func flushPendingText(for conversationID: PersistentIdentifier) {
        flushTasks[conversationID]?.cancel()
        flushTasks[conversationID] = nil
        guard let text = pendingText.removeValue(forKey: conversationID), !text.isEmpty else { return }
        mutate(conversationID: conversationID) { draft in
            draft.text += text
            draft.isActive = true
            draft.runStatus = .running
        }
        revision &+= 1
    }

    private func cancelPendingPublication(for conversationID: PersistentIdentifier) {
        flushTasks[conversationID]?.cancel()
        flushTasks[conversationID] = nil
        pendingText[conversationID] = nil
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
