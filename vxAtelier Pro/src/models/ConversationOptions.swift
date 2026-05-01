import Foundation
import SwiftData
import SwiftUI

/// Represents configuration options for an AI conversation.
///
/// This model stores all the settings that control how a conversation
/// behaves, including:
/// - API connection details
/// - Model parameters
/// - Tool/function calling configurations
/// - UI customization
@Model
final class ConversationOptions: Equatable {
    /// Parameter values for the conversation
    @Relationship(deleteRule: .cascade)
    var parameters: [AiRequestArgument] = []

    /// API configuration for the service provider
    @Relationship(deleteRule: .nullify) var apiConfiguration: APIConfigurationItem?

    /// Custom avatar image data
    var avatarImageData: Data? = nil

    /// Dictionary of tool names to enabled state
    var enabledToolsDict: [String: Bool]

    /// Configuration data for each enabled tool
    var toolConfigurations: [String: String]

    /// Whether markdown rendering is enabled for this conversation
    var isMarkdownEnabled: Bool = AppDefaults.isMarkdownEnabled

    /// Checks if a specific tool is enabled.
    ///
    /// - Parameter toolName: Name of the tool to check
    /// - Returns: True if the tool is enabled, false otherwise
    func isToolEnabled(_ toolName: String) -> Bool {
        return enabledToolsDict[toolName] == true
    }

    /// Enables or disables a specific tool.
    ///
    /// - Parameters:
    ///   - toolName: Name of the tool to configure
    ///   - enabled: Whether the tool should be enabled
    func setToolEnabled(_ toolName: String, enabled: Bool) {
        // Create a new dictionary with the updated value to ensure SwiftData tracks the change
        var updatedDict = enabledToolsDict
        updatedDict[toolName] = enabled
        enabledToolsDict = updatedDict
    }

    /// Gets the configuration for a specific tool.
    ///
    /// - Parameter toolName: Name of the tool
    /// - Returns: Tool configuration dictionary, or nil if not configured
    func getToolConfiguration(_ toolName: String) -> [String: Any]? {
        guard let jsonString = toolConfigurations[toolName] else {
            return nil
        }
        return JSONUtils.jsonStringToDictionary(jsonString)
    }

    /// Sets the configuration for a specific tool.
    ///
    /// - Parameters:
    ///   - toolName: Name of the tool to configure
    ///   - configuration: Configuration data, or nil to remove configuration
    func setToolConfiguration(_ toolName: String, configuration: [String: Any]?) {
        // Create a new dictionary to ensure SwiftData tracks the change
        var updatedConfigs = toolConfigurations
        if let config = configuration {
            if let jsonString = JSONUtils.dictionaryToJsonString(config) {
                updatedConfigs[toolName] = jsonString
            }
        } else {
            updatedConfigs.removeValue(forKey: toolName)
        }
        toolConfigurations = updatedConfigs
    }

    /// Gets a parameter value with a default fallback.
    ///
    /// - Parameters:
    ///   - name: Name of the parameter
    ///   - defaultValue: Default value to return if parameter not found
    /// - Returns: Parameter value or default value
    func getParameterValue<T>(name: String, defaultValue: T) -> T {
        if let param = parameters.first(where: { $0.name == name }) {
            if let value = param.value, let typedValue = value as? T {
                return typedValue
            }
        }
        return defaultValue
    }

    /// Checks if a parameter exists and has a value.
    ///
    /// - Parameter name: Name of the parameter to check
    /// - Returns: True if parameter exists and has a value
    func hasParameterValue(name: String) -> Bool {
        return parameters.first(where: { $0.name == name }) != nil
    }

    /// Gets a parameter value by name.
    ///
    /// - Parameter name: Name of the parameter
    /// - Returns: Parameter value, or nil if not found
    func getParameterValue(name: String) -> Any? {
        return parameters.first(where: { $0.name == name })?.value
    }

    /// Sets a parameter value by name.
    ///
    /// - Parameters:
    ///   - name: Name of the parameter
    ///   - value: Value to set
    func setParameterValue(name: String, value: Any?) {
        if let param = parameters.first(where: { $0.name == name }) {
            param.setValue(value)
        }
    }

    /// Creates a copy of this conversation options instance.
    ///
    /// - Parameter from: Options to copy from
    convenience init(from: ConversationOptions) {
        self.init()
        self.apiConfiguration = from.apiConfiguration
        self.avatarImageData = from.avatarImageData
        self.enabledToolsDict = from.enabledToolsDict
        self.toolConfigurations = from.toolConfigurations

        // Create copies of all parameters
        for param in from.parameters {
            parameters.append(param.copy())
        }
    }

    /// Creates a new conversation options instance.
    ///
    /// - Parameters:
    ///   - avatarImageData: Custom avatar image data
    ///   - apiConfiguration: API configuration for the service provider
    ///   - shouldSetupParameters: Whether to set up default parameters
    init(
        avatarImageData: Data? = nil,
        apiConfiguration: APIConfigurationItem? = nil,
        shouldSetupParameters: Bool = true
    ) {
        self.avatarImageData = avatarImageData
        self.apiConfiguration = apiConfiguration
        self.toolConfigurations = [:]
        self.enabledToolsDict = [:]

        // Only setup parameters if explicitly requested
        if shouldSetupParameters, let config = apiConfiguration {
            setupAiRequestArguments(for: config, modelContext: nil)
        }
    }

    /// Sets up provider-specific parameters based on the API configuration.
    ///
    /// - Parameters:
    ///   - config: The API configuration to use
    ///   - modelContext: Optional model context for deleting existing parameters
    func setupAiRequestArguments(
        for config: APIConfigurationItem, modelContext: ModelContext?
    ) {
        // Query the provider for its default parameters
        let provider = AIServiceProvider.detectProvider(from: config)
        let service = provider.createService(with: config)

        let parametersToDelete = parameters
        parameters.removeAll()

        // Delete the parameters from the model context if provided
        if let context = modelContext {
            for param in parametersToDelete {
                context.delete(param)
            }
        }

        for param in service.getDefaultParameters() {
            parameters.append(param.copy())
        }

        // Only ensure system_prompt exists if not provided by the service
        if parameters.first(where: { $0.name == "system_prompt" }) == nil {
            let systemPromptParam = AiRequestArgument(
                name: "system_prompt",
                displayName: "System Prompt",
                description: "Instructions for the AI assistant",
                required: true,
                valueType: .string,
                controlType: .textField
            )
            systemPromptParam.setValue("")
            parameters.append(systemPromptParam)
        }
    }

    /// Creates a copy of this conversation options instance.
    ///
    /// - Returns: A new DialogOptions instance with copied values
    func copy() -> ConversationOptions {
        return ConversationOptions(from: self)
    }
    static func == (lhs: ConversationOptions, rhs: ConversationOptions) -> Bool {
        // Compare parameters arrays
        guard lhs.parameters.count == rhs.parameters.count else { return false }
        for (l, r) in zip(lhs.parameters, rhs.parameters) {
            if l.name != r.name { return false }
            
            // Compare values based on parameter type
            let type = AiArgumentValueType(rawValue: l.valueType) ?? .string
            switch type {
            case .string:
                if l.stringValue != r.stringValue { return false }
            case .integer:
                if l.intValue != r.intValue { return false }
            case .float:
                if l.floatValue != r.floatValue { return false }
            case .boolean:
                if l.boolValue != r.boolValue { return false }
            }
        }
        
        // Compare API configuration
        if lhs.apiConfiguration?.id != rhs.apiConfiguration?.id { return false }
        
        // Compare avatar data
        if lhs.avatarImageData != rhs.avatarImageData { return false }
        
        // Compare dictionaries
        if lhs.enabledToolsDict != rhs.enabledToolsDict { return false }
        if lhs.toolConfigurations != rhs.toolConfigurations { return false }
        
        return true
    }
} 
