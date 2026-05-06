import Foundation
import SwiftData

struct ConversationRunContext {
    var conversationID: PersistentIdentifier
    var providerConfiguration: LLMProviderConfiguration
    var providerProfile: LLMProviderProfile
    var providerID: LLMProviderID
    var endpointFamily: LLMEndpointFamily
    var modelID: String
    var modelDescriptor: LLMModelDescriptor?
    var messages: [LLMMessage]
    var tools: [LLMToolDefinition]
    var options: LLMGenerationOptions
}

struct ProviderRunResult {
    var text: String = ""
    var reasoning: String = ""
    var toolCalls: [LLMToolCall] = []
    var usage: LLMUsage = LLMUsage()
    var metadata: LLMResponseMetadata?
    var requestID: String?
    var actualModelID: String?
}

@MainActor
protocol ConversationDraftSink {
    func start(conversationID: PersistentIdentifier)
    func reset(conversationID: PersistentIdentifier)
    func appendContent(_ content: String, conversationID: PersistentIdentifier)
    func updateToolCalls(_ toolCalls: [LLMToolCall], conversationID: PersistentIdentifier)
    func complete(conversationID: PersistentIdentifier)
    func fail(_ error: Error, conversationID: PersistentIdentifier)
}

@MainActor
struct ConversationDraftStoreSink: ConversationDraftSink {
    let draftStore: ConversationDraftStore

    func start(conversationID: PersistentIdentifier) {
        draftStore.start(conversationID: conversationID)
    }

    func reset(conversationID: PersistentIdentifier) {
        draftStore.reset(conversationID: conversationID)
    }

    func appendContent(_ content: String, conversationID: PersistentIdentifier) {
        draftStore.appendContent(content, conversationID: conversationID)
    }

    func updateToolCalls(_ toolCalls: [LLMToolCall], conversationID: PersistentIdentifier) {
        draftStore.updateToolCalls(toolCalls, conversationID: conversationID)
    }

    func complete(conversationID: PersistentIdentifier) {
        draftStore.complete(conversationID: conversationID)
    }

    func fail(_ error: Error, conversationID: PersistentIdentifier) {
        draftStore.fail(error, conversationID: conversationID)
    }
}

enum ConversationRunError {
    static func isCancellation(_ error: Error) -> Bool {
        if case .cancelled = error as? LLMProviderError {
            return true
        }
        return error is CancellationError
    }

    static func normalized(_ error: Error) -> Error {
        isCancellation(error) ? LLMProviderError.cancelled : error
    }
}
