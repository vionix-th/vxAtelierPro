import Foundation
import SwiftData

/// Fully resolved runtime inputs needed to build one provider request.
struct ConversationRunContext {
    var conversationID: PersistentIdentifier
    var providerConfiguration: LLMProviderConfiguration
    var providerProfile: LLMProviderProfile
    var providerID: LLMProviderID
    var adapterID: LLMAdapterID
    var modelID: String
    var modelCapabilities: [LLMModelCapability]
    var parameterMappings: [LLMParameterMappingDescriptor]
    var parameterAvailability: [LLMParameterAvailabilityDescriptor]
    var messages: [LLMMessage]
    var tools: [LLMToolDefinition]
    var options: LLMGenerationOptions
}

/// Accumulates normalized provider output while a run is streaming.
struct ProviderRunResult {
    var text: String = ""
    var reasoning: String = ""
    var toolCalls: [LLMToolCall] = []
    var toolOutputs: [LLMToolOutput] = []
    var usage: LLMUsage = LLMUsage()
    var metadata: LLMResponseMetadata?
    var requestID: String?
    var actualModelID: String?
}

/// Receives transient draft updates while provider output is in flight.
@MainActor
protocol ConversationDraftSink {
    /// Starts displaying draft output for a conversation.
    func start(conversationID: PersistentIdentifier)
    /// Clears draft output before the next provider pass.
    func reset(conversationID: PersistentIdentifier)
    /// Appends assistant text to the current draft.
    func appendContent(_ content: String, conversationID: PersistentIdentifier)
    /// Replaces visible draft tool-call state.
    func updateToolCalls(_ toolCalls: [LLMToolCall], conversationID: PersistentIdentifier)
    /// Marks the draft stream as complete.
    func complete(conversationID: PersistentIdentifier)
    /// Marks the draft stream as failed.
    func fail(_ error: Error, conversationID: PersistentIdentifier)
}

/// Adapter from runtime draft events into `ConversationDraftStore`.
@MainActor
struct ConversationDraftStoreSink: ConversationDraftSink {
    let draftStore: ConversationDraftStore

    /// Starts displaying draft output for a conversation.
    func start(conversationID: PersistentIdentifier) {
        draftStore.start(conversationID: conversationID)
    }

    /// Clears draft output before the next provider pass.
    func reset(conversationID: PersistentIdentifier) {
        draftStore.reset(conversationID: conversationID)
    }

    /// Appends assistant text to the current draft.
    func appendContent(_ content: String, conversationID: PersistentIdentifier) {
        draftStore.appendContent(content, conversationID: conversationID)
    }

    /// Replaces visible draft tool-call state.
    func updateToolCalls(_ toolCalls: [LLMToolCall], conversationID: PersistentIdentifier) {
        draftStore.updateToolCalls(toolCalls, conversationID: conversationID)
    }

    /// Marks the draft stream as complete.
    func complete(conversationID: PersistentIdentifier) {
        draftStore.complete(conversationID: conversationID)
    }

    /// Marks the draft stream as failed.
    func fail(_ error: Error, conversationID: PersistentIdentifier) {
        draftStore.fail(error, conversationID: conversationID)
    }
}

/// Helpers for preserving cancellation semantics across provider and Swift task errors.
enum ConversationRunError {
    /// Returns true when an error represents user or task cancellation.
    static func isCancellation(_ error: Error) -> Bool {
        if case .cancelled = error as? LLMProviderError {
            return true
        }
        return error is CancellationError
    }

    /// Maps cancellation into the provider-domain cancellation error.
    static func normalized(_ error: Error) -> Error {
        isCancellation(error) ? LLMProviderError.cancelled : error
    }
}
