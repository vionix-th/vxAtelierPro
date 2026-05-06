struct LLMToolExecutionContext {
    var conversation: ConversationItem
    var turn: ConversationTurn
}

struct LLMToolExecutionCall {
    var id: String
    var name: String
    var argumentsJSON: String
    var configuration: [String: JSONValue]
    var context: LLMToolExecutionContext
}

/// Protocol for tools that can be executed.
/// Executable tools implement the actual functionality that will be performed
/// when the model invokes the tool.
protocol ExecutableLLMTool: LLMTool {
    func execute(_ call: LLMToolExecutionCall) async throws -> String
}
