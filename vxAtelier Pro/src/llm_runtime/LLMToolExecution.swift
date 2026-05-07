import Foundation

/// Runtime context exposed to executable tools.
struct LLMToolExecutionContext {
    var conversation: ConversationItem
    var turn: ConversationTurn
}

/// Normalized tool invocation data passed from persisted tool calls to executable tools.
struct LLMToolExecutionCall {
    var id: String
    var name: String
    var argumentsJSON: String
    var configuration: [String: JSONValue]
    var context: LLMToolExecutionContext
}

/// Tool execution failures surfaced to the conversation run loop.
enum LLMToolExecutionError: LocalizedError, Equatable {
    case invalidArguments(String)
    case unavailable(String)
    case executionFailed(String)

    /// Presents the stored tool failure message as user-facing text.
    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .unavailable(let message):
            return message
        case .executionFailed(let message):
            return message
        }
    }
}

/// Tool contract for model-invoked operations that can run in the app runtime.
@MainActor
protocol ExecutableLLMTool: LLMTool {
    /// Executes one validated tool call and returns provider-visible text output.
    func execute(_ call: LLMToolExecutionCall) async throws -> String
}
