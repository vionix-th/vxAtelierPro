import Foundation
import CryptoKit

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

/// Provides a stable hash implementation using MD5.
/// Used to generate consistent identifiers for tool calls and other components.
extension String {
    /// Computes an MD5 hash of the string and returns it as a hexadecimal string.
    /// This provides a stable identifier that remains the same for identical inputs.
    /// - Returns: MD5 hash as a hexadecimal string
    func stableHash() -> String {
        let data = Data(self.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}
