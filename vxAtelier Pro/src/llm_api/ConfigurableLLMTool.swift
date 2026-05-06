import Foundation

/// Optional user/runtime configuration for tools.
protocol ConfigurableLLMTool: LLMTool {
    var configurationSchema: any LLMToolParameters { get }
    func defaultConfiguration() -> [String: JSONValue]
}
