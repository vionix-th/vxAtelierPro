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

    var systemPrompt: String
    var modelOverride: String?
    var endpointOverride: String?
    var temperature: Double?
    var topP: Double?
    var maxOutputTokens: Int?
    var stopSequences: [String]
    var responseFormatRaw: String
    var reasoning: String?
    var serviceTier: String?
    var streamModeRaw: String
    var retryPolicyRaw: String
    var providerExtrasJSON: String

    var endpointOverrideFamily: LLMEndpointFamily? {
        get { endpointOverride.flatMap { LLMEndpointFamily(rawValue: $0) } }
        set { endpointOverride = newValue?.rawValue }
    }

    var streamMode: LLMGenerationOptions.StreamMode {
        get { LLMGenerationOptions.StreamMode(rawValue: streamModeRaw) ?? .auto }
        set { streamModeRaw = newValue.rawValue }
    }

    var retryPolicy: LLMGenerationOptions.RetryPolicy {
        get { LLMGenerationOptions.RetryPolicy(rawValue: retryPolicyRaw) ?? .disabled }
        set { retryPolicyRaw = newValue.rawValue }
    }

    var responseFormat: LLMGenerationOptions.ResponseFormat {
        get { LLMGenerationOptions.ResponseFormat(rawValue: responseFormatRaw) ?? .text }
        set { responseFormatRaw = newValue.rawValue }
    }

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
        self.isMarkdownEnabled = from.isMarkdownEnabled
        self.systemPrompt = from.systemPrompt
        self.modelOverride = from.modelOverride
        self.endpointOverride = from.endpointOverride
        self.temperature = from.temperature
        self.topP = from.topP
        self.maxOutputTokens = from.maxOutputTokens
        self.stopSequences = from.stopSequences
        self.responseFormatRaw = from.responseFormatRaw
        self.reasoning = from.reasoning
        self.serviceTier = from.serviceTier
        self.streamModeRaw = from.streamModeRaw
        self.retryPolicyRaw = from.retryPolicyRaw
        self.providerExtrasJSON = from.providerExtrasJSON

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
        self.systemPrompt = ""
        self.modelOverride = nil
        self.endpointOverride = nil
        self.temperature = nil
        self.topP = nil
        self.maxOutputTokens = nil
        self.stopSequences = []
        self.responseFormatRaw = LLMGenerationOptions.ResponseFormat.text.rawValue
        self.reasoning = nil
        self.serviceTier = nil
        self.streamModeRaw = LLMGenerationOptions.StreamMode.auto.rawValue
        self.retryPolicyRaw = LLMGenerationOptions.RetryPolicy.disabled.rawValue
        self.providerExtrasJSON = "{}"

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
        let parametersToDelete = parameters
        parameters.removeAll()

        if let context = modelContext {
            for param in parametersToDelete {
                context.delete(param)
            }
        }

        let registry = LLMProviderRegistry.shared
        let providerID = registry.resolveProviderID(for: config)
        let profile = registry.profile(for: providerID)
        let supported = Set(profile.supportedParameters)
        let schemaFeatures = Set(profile.schemaFeatures)
        let modelID = config.defaultModelID ?? profile.defaultModelID ?? ""
        modelOverride = modelID.isEmpty ? nil : modelID
        endpointOverride = config.defaultEndpointFamily

        appendParameter(
            name: "model",
            displayName: "Model",
            description: "Model identifier used for this conversation",
            required: true,
            valueType: .string,
            controlType: .textField,
            value: modelID
        )
        appendParameter(
            name: "system_prompt",
            displayName: "System Prompt",
            description: "Instructions for the assistant",
            required: true,
            valueType: .string,
            controlType: .textField,
            value: systemPrompt
        )
        if supported.contains("temperature") {
            appendParameter(
                name: "temperature",
                displayName: "Temperature",
                description: "Sampling temperature",
                valueType: .float,
                controlType: .slider,
                minValue: 0,
                maxValue: 2,
                step: 0.1,
                value: temperature
            )
        }
        if supported.contains("top_p") {
            appendParameter(
                name: "top_p",
                displayName: "Top P",
                description: "Nucleus sampling probability",
                valueType: .float,
                controlType: .slider,
                minValue: 0,
                maxValue: 1,
                step: 0.05,
                value: topP
            )
        }
        let maxTokenName = supported.contains("max_output_tokens") ? "max_output_tokens" : (supported.contains("max_tokens") ? "max_tokens" : nil)
        if let maxTokenName {
            appendParameter(
                name: maxTokenName,
                displayName: "Max Output Tokens",
                description: "Maximum number of generated tokens",
                valueType: .integer,
                controlType: .stepper,
                minValue: 1,
                maxValue: 200_000,
                step: 1,
                value: maxOutputTokens
            )
        }
        if supported.contains("response_format") {
            var formats = ["text"]
            if schemaFeatures.contains(.jsonObject) {
                formats.append("json_object")
            }
            if schemaFeatures.contains(.jsonSchema) {
                formats.append("json_schema")
            }
            appendParameter(
                name: "response_format",
                displayName: "Response Format",
                description: "Generated response format",
                valueType: .string,
                controlType: .picker,
                options: formats,
                value: responseFormatRaw
            )
        }
        if supported.contains("reasoning") {
            appendParameter(
                name: "reasoning",
                displayName: "Reasoning",
                description: "Provider reasoning control",
                valueType: .string,
                controlType: .textField,
                value: reasoning
            )
        }
        if supported.contains("service_tier") {
            appendParameter(
                name: "service_tier",
                displayName: "Service Tier",
                description: "Provider service tier",
                valueType: .string,
                controlType: .textField,
                value: serviceTier
            )
        }
        syncTypedFieldsFromParameters()
    }

    private func appendParameter(
        name: String,
        displayName: String,
        description: String,
        required: Bool = false,
        valueType: AiArgumentValueType,
        controlType: AiArgumentControlType,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        step: Double? = nil,
        options: [String]? = nil,
        value: Any?
    ) {
        let parameter = AiRequestArgument(
            name: name,
            displayName: displayName,
            description: description,
            required: required,
            valueType: valueType,
            controlType: controlType,
            minValue: minValue,
            maxValue: maxValue,
            step: step,
            options: options
        )
        parameter.isEnabled = required || value != nil
        if let value {
            parameter.setValue(value)
        }
        parameters.append(parameter)
    }

    func generationOptions(resolvedModelID: String?, resolvedEndpointFamily: LLMEndpointFamily?) -> LLMGenerationOptions {
        syncTypedFieldsFromParameters()
        return LLMGenerationOptions(
            systemPrompt: systemPrompt,
            modelID: modelOverride ?? resolvedModelID,
            endpointFamily: endpointOverrideFamily ?? resolvedEndpointFamily,
            temperature: temperature,
            topP: topP,
            maxOutputTokens: maxOutputTokens,
            stop: stopSequences,
            responseFormat: responseFormat,
            reasoning: reasoning,
            serviceTier: serviceTier,
            streamMode: streamMode,
            retryPolicy: retryPolicy,
            providerExtras: decodedProviderExtras
        )
    }

    var decodedProviderExtras: [String: JSONValue] {
        get {
            guard let data = providerExtrasJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                providerExtrasJSON = "{}"
                return
            }
            providerExtrasJSON = json
        }
    }

    func syncTypedFieldsFromParameters() {
        if let value = getParameterValue(name: "system_prompt") as? String {
            systemPrompt = value
        }
        if let value = getParameterValue(name: "model") as? String, !value.isEmpty {
            modelOverride = value
        }
        if let value = getParameterValue(name: "temperature") as? Double {
            temperature = value
        }
        if let value = getParameterValue(name: "top_p") as? Double {
            topP = value
        }
        if let value = getParameterValue(name: "max_tokens") as? Int {
            maxOutputTokens = value
        }
        if let value = getParameterValue(name: "max_output_tokens") as? Int {
            maxOutputTokens = value
        }
        if let value = getParameterValue(name: "response_format") as? String {
            switch value {
            case "json_object": responseFormat = .jsonObject
            case "json_schema": responseFormat = .jsonSchema
            default: responseFormat = .text
            }
        }
        if let value = getParameterValue(name: "reasoning") as? String, !value.isEmpty {
            reasoning = value
        }
        if let value = getParameterValue(name: "service_tier") as? String, !value.isEmpty {
            serviceTier = value
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
