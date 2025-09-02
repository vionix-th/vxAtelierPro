public class AIToolRegistry {
    // Singleton instance
    public static let shared = AIToolRegistry()
    
    // Available tools dictionary
    private var availableTools: [String: AITool] = [:]
    
    // Tool configurations
    private var toolConfigurations: [String: Any] = [:]
    
    private init() {}
    
    // Register a new tool
    public func registerTool(_ tool: AITool) {
        availableTools[tool.name] = tool
    }
    
    // Get all registered tools
    public func getTools() -> [AITool] {
        Array(availableTools.values)
    }
    
    // Store tool configuration
    public func setConfiguration<T: Codable>(for toolName: String, config: T) {
        toolConfigurations[toolName] = config
    }
    
    // Get tool configuration
    public func getConfiguration<T: Codable>(for toolName: String) -> T? {
        return toolConfigurations[toolName] as? T
    }
} 