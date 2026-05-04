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
        for toolCall in toolCalls {
            guard conversation.options.isToolEnabled(toolCall.name) else {
                try fail(toolCall, conversation: conversation, message: "Tool '\(toolCall.name)' is not enabled.")
            }
            guard let tool = AIToolRegistry.shared.getTools().first(where: { $0.name == toolCall.name }) else {
                try fail(toolCall, conversation: conversation, message: "Tool not found: \(toolCall.name)")
            }
            guard let executableTool = tool as? any ExecutableTool else {
                try fail(toolCall, conversation: conversation, message: "Tool execution not supported: \(toolCall.name)")
            }
            toolCall.status = .executing
            try persistence.save(conversation)

            let configuration = conversation.options.getToolConfiguration(toolCall.name)
                ?? (tool as? any ConfigurableAITool)?.defaultConfiguration()
                ?? [:]
            let call = ToolExecutionCall(
                id: toolCall.callID,
                name: toolCall.name,
                argumentsJSON: toolCall.argumentsJSON,
                configuration: configuration,
                context: ToolExecutionContext(conversation: conversation, turn: turn)
            )
            do {
                let output = try await executableTool.execute(call)
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

    @MainActor
    private func fail(_ toolCall: ToolCallItem, conversation: ConversationItem, message: String) throws -> Never {
        toolCall.status = .failed
        toolCall.errorMessage = message
        try persistence.save(conversation)
        throw LLMProviderError.unsupportedCapability(message)
    }
}
