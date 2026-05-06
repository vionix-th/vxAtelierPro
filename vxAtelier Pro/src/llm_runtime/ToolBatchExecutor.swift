import Foundation

struct ToolBatchExecutor {
    let toolCatalog: LLMToolCatalog

    init(toolCatalog: LLMToolCatalog = LLMToolRegistry.shared) {
        self.toolCatalog = toolCatalog
    }

    @MainActor
    func execute(
        _ toolCall: ToolCallItem,
        conversation: ConversationItem,
        turn: ConversationTurn
    ) async throws -> String {
        guard conversation.options.isToolEnabled(toolCall.name) else {
            throw LLMProviderError.unsupportedCapability("Tool '\(toolCall.name)' is not enabled.")
        }
        guard let tool = toolCatalog.tool(named: toolCall.name) else {
            throw LLMProviderError.unsupportedCapability("Tool not found: \(toolCall.name)")
        }
        guard let executableTool = tool as? any ExecutableLLMTool else {
            throw LLMProviderError.unsupportedCapability("Tool execution not supported: \(toolCall.name)")
        }

        let configuration = conversation.options.getToolConfiguration(toolCall.name)
            ?? (tool as? any ConfigurableLLMTool)?.defaultConfiguration()
            ?? [:]
        let call = LLMToolExecutionCall(
            id: toolCall.callID,
            name: toolCall.name,
            argumentsJSON: toolCall.argumentsJSON,
            configuration: configuration,
            context: LLMToolExecutionContext(conversation: conversation, turn: turn)
        )
        return try await executableTool.execute(call)
    }
}
