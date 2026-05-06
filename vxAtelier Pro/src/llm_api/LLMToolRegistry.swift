protocol LLMToolCatalog {
    func allTools() -> [LLMTool]
    func tool(named name: String) -> LLMTool?
}

final class LLMToolRegistry {
    // Singleton instance
    static let shared = LLMToolRegistry()

    // Available tools dictionary
    private var availableTools: [String: LLMTool] = [:]

    private init() {}

    // Register a new tool
    func registerTool(_ tool: LLMTool) {
        availableTools[tool.name] = tool
    }

    // Get all registered tools
    func getTools() -> [LLMTool] {
        allTools()
    }
}

extension LLMToolRegistry: LLMToolCatalog {
    func allTools() -> [LLMTool] {
        Array(availableTools.values)
    }

    func tool(named name: String) -> LLMTool? {
        availableTools[name]
    }
}
