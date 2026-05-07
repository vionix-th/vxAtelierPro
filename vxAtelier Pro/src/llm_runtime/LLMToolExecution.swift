import Foundation

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

enum LLMToolExecutionError: LocalizedError, Equatable {
    case invalidArguments(String)
    case unavailable(String)
    case executionFailed(String)

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

/// Protocol for tools that can be executed.
/// Executable tools implement the actual functionality that will be performed
/// when the model invokes the tool.
@MainActor
protocol ExecutableLLMTool: LLMTool {
    func execute(_ call: LLMToolExecutionCall) async throws -> String
}
