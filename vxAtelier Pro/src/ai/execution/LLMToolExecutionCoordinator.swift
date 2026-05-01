import Foundation

struct LLMToolExecutionCoordinator {
    let persistence: LLMPersistenceCoordinator

    init(persistence: LLMPersistenceCoordinator = LLMPersistenceCoordinator()) {
        self.persistence = persistence
    }

    @MainActor
    func execute(
        _ toolCalls: [ToolCallItem],
        conversation: ConversationItem,
        turn: ConversationTurn
    ) async throws {
        let handler = DefaultToolHandler()
        for toolCall in toolCalls {
            guard conversation.options.isToolEnabled(toolCall.name) else {
                toolCall.status = .failed
                toolCall.errorMessage = "Tool '\(toolCall.name)' is not enabled."
                try persistence.save(conversation)
                throw LLMProviderError.unsupportedCapability(toolCall.errorMessage ?? "Tool is not enabled.")
            }
            toolCall.status = .executing
            try persistence.save(conversation)

            let configuration = conversation.options.getToolConfiguration(toolCall.name)
            let generic = toolCall.asGenericToolCall(configuration: configuration, context: conversation)
            do {
                let results = try await handler.handleToolCalls([generic])
                let output = results.first?.output ?? ""
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
                try persistence.save(conversation)
            } catch is CancellationError {
                toolCall.status = .cancelled
                try persistence.save(conversation)
                throw LLMProviderError.cancelled
            } catch {
                toolCall.status = .failed
                toolCall.errorMessage = error.localizedDescription
                try persistence.save(conversation)
                throw error
            }
        }
    }
}
