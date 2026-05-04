import Foundation

/// Optional user/runtime configuration for tools.
protocol ConfigurableAITool: AITool {
    var configurationSchema: any AIToolParameters { get }
    func defaultConfiguration() -> [String: JSONValue]
}

struct ToolExecutionContext {
    var conversation: ConversationItem
    var turn: ConversationTurn
}

struct ToolExecutionCall {
    var id: String
    var name: String
    var argumentsJSON: String
    var configuration: [String: JSONValue]
    var context: ToolExecutionContext
}

/// Protocol for tools that can be executed.
/// Executable tools implement the actual functionality that will be performed
/// when the AI invokes the tool.
protocol ExecutableTool: AITool {
    func execute(_ call: ToolExecutionCall) async throws -> String
}
