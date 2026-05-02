final class AIToolRegistry {
    // Singleton instance
    static let shared = AIToolRegistry()

    // Available tools dictionary
    private var availableTools: [String: AITool] = [:]

    private init() {}

    // Register a new tool
    func registerTool(_ tool: AITool) {
        availableTools[tool.name] = tool
    }

    // Get all registered tools
    func getTools() -> [AITool] {
        Array(availableTools.values)
    }
}
