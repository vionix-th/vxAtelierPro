import Foundation
import SwiftData

struct ConversationRunStore {
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

    @MainActor
    func rollbackTurn(_ turn: ConversationTurn, from conversation: ConversationItem) throws {
        if let index = conversation.turns.firstIndex(where: { $0.id == turn.id }) {
            conversation.turns.remove(at: index)
        }
        conversation.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: false)
        try save(conversation)
    }

    @MainActor
    func finishConversation(_ conversation: ConversationItem) throws {
        conversation.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: true)
        try save(conversation)
    }

    @MainActor
    func createResponseRun(
        for request: LLMRequest,
        turn: ConversationTurn,
        conversation: ConversationItem
    ) throws -> ResponseRunItem {
        let run = ResponseRunItem(
            providerID: request.providerID,
            endpointFamily: request.endpointFamily,
            requestedModelID: request.modelID,
            status: .pending,
            turn: turn
        )
        turn.responseRuns.append(run)
        try run.transition(to: .streaming)
        try save(conversation)
        return run
    }

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

    @MainActor
    func completeRunAfterTools(_ run: ResponseRunItem, conversation: ConversationItem) throws {
        try run.transition(to: .completed)
        run.completedAt = Date()
        try save(conversation)
    }

    @MainActor
    func markToolExecuting(_ toolCall: ToolCallItem, conversation: ConversationItem) throws {
        toolCall.status = .executing
        try save(conversation)
    }

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

    @MainActor
    func failToolCall(_ toolCall: ToolCallItem, error: Error, conversation: ConversationItem) throws {
        toolCall.status = .failed
        toolCall.errorMessage = error.localizedDescription
        try save(conversation)
    }

    @MainActor
    func cancelToolCall(_ toolCall: ToolCallItem, conversation: ConversationItem) throws {
        toolCall.status = .cancelled
        try save(conversation)
    }

    @MainActor
    func save(_ conversation: ConversationItem) throws {
        try conversation.modelContext?.save()
    }
}
