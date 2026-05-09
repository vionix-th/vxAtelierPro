import Foundation
import SwiftData

/// Persists conversation turns, provider runs, assistant messages, and tool results.
struct ConversationRunStore {
    /// Creates and saves the user turn that starts a completion run.
    @MainActor
    func startTurn(message: String, in conversation: ConversationItem) throws -> ConversationTurn {
        let userMessage = MessageItem(
            role: "user",
            contentParts: [MessageContentPartItem(index: 0, kind: .text, text: message)],
            timestamp: Date()
        )
        let nextSequence = (conversation.turns.map(\.sequenceNumber).max() ?? -1) + 1
        let turn = ConversationTurn(
            sequenceNumber: nextSequence,
            timestamp: userMessage.timestamp,
            userMessage: userMessage,
            conversation: conversation
        )
        conversation.turns.append(turn)
        conversation.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: false)
        try save(conversation)
        return turn
    }

    /// Removes an unsent turn after run setup fails before any provider run is recorded.
    @MainActor
    func rollbackTurn(_ turn: ConversationTurn, from conversation: ConversationItem) throws {
        if let index = conversation.turns.firstIndex(where: { $0.id == turn.id }) {
            conversation.turns.remove(at: index)
        }
        conversation.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: false)
        try save(conversation)
    }

    /// Refreshes conversation token counts and saves final run state.
    @MainActor
    func finishConversation(_ conversation: ConversationItem) throws {
        conversation.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: true)
        try save(conversation)
    }

    /// Creates a persisted provider run and transitions it into streaming state.
    @MainActor
    func createResponseRun(
        for request: LLMRequest,
        turn: ConversationTurn,
        conversation: ConversationItem
    ) throws -> ResponseRunItem {
        let run = ResponseRunItem(
            providerID: request.providerID,
            adapterID: request.adapterID,
            requestedModelID: request.modelID,
            status: .pending,
            turn: turn
        )
        turn.responseRuns.append(run)
        try run.transition(to: .streaming)
        try save(conversation)
        return run
    }

    /// Applies provider output to the run and creates an assistant message when content exists.
    @MainActor
    func applyProviderResult(
        _ result: ProviderRunResult,
        to run: ResponseRunItem,
        turn: ConversationTurn,
        conversation: ConversationItem
    ) throws -> MessageItem? {
        try run.transition(to: result.toolCalls.isEmpty ? .completed : .awaitingTools)
        run.actualModelID = result.actualModelID
        run.requestID = result.requestID
        run.applyUsage(result.usage)
        if let metadata = result.metadata {
            run.applyMetadata(metadata)
        }
        run.completedAt = result.toolCalls.isEmpty ? Date() : nil
        try save(conversation)

        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && result.toolCalls.isEmpty {
            return nil
        }

        let message = MessageItem(
            role: "assistant",
            contentParts: [MessageContentPartItem(index: 0, kind: .text, text: result.text)],
            timestamp: Date()
        )
        message.toolCallItems = result.toolCalls.sorted { $0.index < $1.index }.map { call in
            ToolCallItem(
                callID: call.id,
                providerCallID: call.callID,
                index: call.index,
                name: call.name,
                argumentsJSON: call.argumentsJSON,
                status: .readyToExecute,
                assistantMessage: message
            )
        }
        turn.events.append(TurnEvent(type: .assistant, timestamp: message.timestamp, message: message, turn: turn))
        try save(conversation)
        return message
    }

    /// Records a terminal failed or cancelled state and returns the normalized error.
    @MainActor
    func markRunFailed(
        _ run: ResponseRunItem,
        error: Error,
        metadata: LLMResponseMetadata? = nil,
        conversation: ConversationItem
    ) throws -> Error {
        let normalizedError = ConversationRunError.normalized(error)
        if let metadata {
            run.applyMetadata(metadata)
        }
        try? run.transition(to: ConversationRunError.isCancellation(normalizedError) ? .cancelled : .failed)
        run.errorMessage = normalizedError.localizedDescription
        run.completedAt = Date()
        try save(conversation)
        return normalizedError
    }

    /// Marks a run completed after all requested tool calls have produced results.
    @MainActor
    func completeRunAfterTools(_ run: ResponseRunItem, conversation: ConversationItem) throws {
        try run.transition(to: .completed)
        run.completedAt = Date()
        try save(conversation)
    }

    /// Marks a persisted tool call as currently executing.
    @MainActor
    func markToolExecuting(_ toolCall: ToolCallItem, conversation: ConversationItem) throws {
        toolCall.status = .executing
        try save(conversation)
    }

    /// Stores tool output as a tool-result message and marks the call completed.
    @MainActor
    func completeToolCall(
        _ toolCall: ToolCallItem,
        output: String,
        turn: ConversationTurn,
        conversation: ConversationItem
    ) throws {
        let resultMessage = MessageItem(
            role: "tool",
            contentParts: [MessageContentPartItem(index: 0, kind: .toolResult, text: output)],
            timestamp: Date(),
            toolCallId: toolCall.providerCallID ?? toolCall.callID
        )
        toolCall.resultMessage = resultMessage
        toolCall.status = .completed
        toolCall.completedAt = Date()
        turn.events.append(TurnEvent(type: .toolResult, timestamp: resultMessage.timestamp, message: resultMessage, turn: turn))
        try save(conversation)
    }

    /// Stores a tool failure message on the tool-call record.
    @MainActor
    func failToolCall(_ toolCall: ToolCallItem, error: Error, conversation: ConversationItem) throws {
        toolCall.status = .failed
        toolCall.errorMessage = error.localizedDescription
        try save(conversation)
    }

    /// Marks a tool call as cancelled without creating a result message.
    @MainActor
    func cancelToolCall(_ toolCall: ToolCallItem, conversation: ConversationItem) throws {
        toolCall.status = .cancelled
        try save(conversation)
    }

    /// Saves through the conversation's SwiftData model context.
    @MainActor
    func save(_ conversation: ConversationItem) throws {
        try conversation.modelContext?.save()
    }
}
