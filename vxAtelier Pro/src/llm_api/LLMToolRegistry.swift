/// Read-only catalog used by request builders and runtime executors.
protocol LLMToolCatalog {
    /// Returns every registered tool in unspecified order.
    func allTools() -> [LLMTool]
    /// Returns the tool registered under a provider-visible name.
    func tool(named name: String) -> LLMTool?
}

/// Process-wide registry for tools exposed to LLM requests.
final class LLMToolRegistry {
    /// Shared mutable registry used by app startup and run execution.
    static let shared = LLMToolRegistry()

    private var availableTools: [String: LLMTool] = [:]

    /// Restricts construction to the shared registry.
    private init() {}

    /// Registers or replaces a tool by its provider-visible name.
    func registerTool(_ tool: LLMTool) {
        availableTools[tool.name] = tool
    }

    /// Compatibility accessor for callers that predate `LLMToolCatalog`.
    func getTools() -> [LLMTool] {
        allTools()
    }
}

/// Catalog conformance for read-only tool lookup.
extension LLMToolRegistry: LLMToolCatalog {
    /// Returns every registered tool in unspecified order.
    func allTools() -> [LLMTool] {
        Array(availableTools.values)
    }

    /// Returns the registered tool with the requested provider-visible name.
    func tool(named name: String) -> LLMTool? {
        availableTools[name]
    }
}
