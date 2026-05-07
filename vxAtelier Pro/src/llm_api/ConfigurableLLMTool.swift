import Foundation

/// Optional user/runtime configuration for tools.
protocol ConfigurableLLMTool: LLMTool {
    /// Schema for configuration values stored outside a single tool call.
    var configurationSchema: any LLMToolParameters { get }
    /// Baseline configuration used when the conversation has no explicit override.
    func defaultConfiguration() -> [String: JSONValue]
}
