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
    func getToolConfiguration(_ toolName: String) -> [String: JSONValue]? {
        guard let jsonString = toolConfigurations[toolName] else {
            return nil
        }
        guard let data = jsonString.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return nil
        }
        return value.objectValue
    }

    /// Sets the configuration for a specific tool.
    ///
    /// - Parameters:
    ///   - toolName: Name of the tool to configure
    ///   - configuration: Configuration data, or nil to remove configuration
    func setToolConfiguration(_ toolName: String, configuration: [String: JSONValue]?) {
        // Create a new dictionary to ensure SwiftData tracks the change
        var updatedConfigs = toolConfigurations
        if let config = configuration {
            if let data = try? JSONEncoder().encode(JSONValue.object(config)),
               let jsonString = String(data: data, encoding: .utf8) {
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
        for config: APIConfigurationItem,
        modelContext: ModelContext?,
        requestedModelID: String? = nil
    ) {
        var existingValues: [String: (value: JSONValue?, isEnabled: Bool)] = [:]
        for parameter in parameters {
            existingValues[parameter.name] = (parameter.jsonValue, parameter.isEnabled)
        }

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
        let modelID = requestedModelID
            ?? existingStringValue(for: .model, existingValues: existingValues)
            ?? modelOverride
            ?? config.defaultModelID
            ?? profile.defaultModelID
            ?? ""
        let endpoint = endpointOverrideFamily ?? config.defaultEndpointFamilyEnum
        modelOverride = modelID.isEmpty ? nil : modelID
        endpointOverride = endpoint.rawValue

        appendSemanticParameter(
            .model,
            required: true,
            value: .string(modelID),
            existingValues: existingValues
        )
        appendSemanticParameter(
            .systemPrompt,
            required: true,
            value: existingValue(for: .systemPrompt, existingValues: existingValues) ?? .string(systemPrompt),
            existingValues: existingValues
        )

        let mappings = resolvedParameterMappings(
            apiConfiguration: config,
            providerID: providerID,
            endpointFamily: endpoint,
            modelID: modelID,
            modelContext: modelContext
        )
        for mapping in mappings.values.sorted(by: {
            AiParameterPresentationCatalog.displayName(for: $0.semanticParameterID)
                < AiParameterPresentationCatalog.displayName(for: $1.semanticParameterID)
        }) {
            guard mapping.isEnabled, mapping.semanticParameterID.isProviderMappable else { continue }
            let value = existingValue(for: mapping.semanticParameterID, existingValues: existingValues)
                ?? fallbackJSONValue(for: mapping.semanticParameterID)
                ?? mapping.defaultValue
            appendSemanticParameter(
                mapping.semanticParameterID,
                required: mapping.isRequired,
                value: value,
                existingValues: existingValues
            )
        }
        syncTypedFieldsFromParameters()
    }

    private func appendSemanticParameter(
        _ parameterID: LLMParameterID,
        required: Bool = false,
        value: JSONValue?,
        existingValues: [String: (value: JSONValue?, isEnabled: Bool)]
    ) {
        let presentation = AiParameterPresentationCatalog.presentation(for: parameterID)
        let parameter = AiRequestArgument(
            name: parameterID.rawValue,
            displayName: presentation.displayName,
            description: presentation.description,
            required: required,
            valueType: parameterID.valueType,
            controlType: presentation.controlType,
            minValue: parameterID.minValue,
            maxValue: parameterID.maxValue,
            step: presentation.step,
            options: parameterID.options
        )
        let existing = existingValues[parameterID.rawValue]
        if let existing {
            parameter.isEnabled = required || existing.isEnabled
        } else {
            parameter.isEnabled = required || value != nil
        }
        parameter.setJSONValue(value)
        parameters.append(parameter)
    }

    private func appendParameter(
        name: String,
        displayName: String,
        description: String,
        required: Bool = false,
        valueType: LLMParameterValueType,
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
            systemPrompt: stringParameterValue(.systemPrompt) ?? systemPrompt,
            modelID: stringParameterValue(.model) ?? modelOverride ?? resolvedModelID,
            endpointFamily: endpointOverrideFamily ?? resolvedEndpointFamily,
            temperature: doubleParameterValue(.temperature, fallback: temperature),
            topP: doubleParameterValue(.topP, fallback: topP),
            maxOutputTokens: integerParameterValue(.maxOutputTokens, fallback: maxOutputTokens),
            stop: stopSequenceParameterValue(fallback: stopSequences),
            responseFormat: responseFormatParameterValue(fallback: responseFormat),
            reasoning: stringParameterValue(.reasoningEffort) ?? reasoning,
            serviceTier: stringParameterValue(.serviceTier) ?? serviceTier,
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
        if let value = stringParameterValue(.systemPrompt) {
            systemPrompt = value
        }
        if let value = stringParameterValue(.model), !value.isEmpty {
            modelOverride = value
        }
        if parameterExists(.temperature) { temperature = doubleParameterValue(.temperature, fallback: nil) }
        if parameterExists(.topP) { topP = doubleParameterValue(.topP, fallback: nil) }
        if parameterExists(.maxOutputTokens) { maxOutputTokens = integerParameterValue(.maxOutputTokens, fallback: nil) }
        if parameterExists(.stopSequences) { stopSequences = stopSequenceParameterValue(fallback: []) }
        if parameterExists(.responseFormat) { responseFormat = responseFormatParameterValue(fallback: .text) }
        if parameterExists(.reasoningEffort) { reasoning = stringParameterValue(.reasoningEffort) }
        if parameterExists(.serviceTier) { serviceTier = stringParameterValue(.serviceTier) }
    }

    private func parameter(_ parameterID: LLMParameterID) -> AiRequestArgument? {
        parameters.first { $0.name == parameterID.rawValue }
    }

    private func parameterExists(_ parameterID: LLMParameterID) -> Bool {
        parameter(parameterID) != nil
    }

    private func stringParameterValue(_ parameterID: LLMParameterID) -> String? {
        guard let parameter = parameter(parameterID) else { return nil }
        return parameter.stringValue
    }

    private func integerParameterValue(_ parameterID: LLMParameterID, fallback: Int?) -> Int? {
        guard let parameter = parameter(parameterID) else { return fallback }
        return parameter.intValue
    }

    private func doubleParameterValue(_ parameterID: LLMParameterID, fallback: Double?) -> Double? {
        guard let parameter = parameter(parameterID) else { return fallback }
        return parameter.floatValue
    }

    private func stopSequenceParameterValue(fallback: [String]) -> [String] {
        guard let parameter = parameter(.stopSequences) else { return fallback }
        guard let value = parameter.stringValue else { return [] }
        return value
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func responseFormatParameterValue(
        fallback: LLMGenerationOptions.ResponseFormat
    ) -> LLMGenerationOptions.ResponseFormat {
        guard let parameter = parameter(.responseFormat),
              let value = parameter.stringValue else {
            return fallback
        }
        return .fromSemanticRawValue(value)
    }

    private func existingValue(
        for parameterID: LLMParameterID,
        existingValues: [String: (value: JSONValue?, isEnabled: Bool)]
    ) -> JSONValue? {
        guard let existing = existingValues[parameterID.rawValue] else { return nil }
        return existing.isEnabled ? existing.value : nil
    }

    private func existingStringValue(
        for parameterID: LLMParameterID,
        existingValues: [String: (value: JSONValue?, isEnabled: Bool)]
    ) -> String? {
        existingValue(for: parameterID, existingValues: existingValues)?.stringValue
    }

    private func fallbackJSONValue(for parameterID: LLMParameterID) -> JSONValue? {
        switch parameterID {
        case .model:
            return modelOverride.map { .string($0) }
        case .systemPrompt:
            return systemPrompt.isEmpty ? nil : .string(systemPrompt)
        case .maxOutputTokens:
            return maxOutputTokens.map { .integer($0) }
        case .temperature:
            return temperature.map { .number($0) }
        case .topP:
            return topP.map { .number($0) }
        case .stopSequences:
            return stopSequences.isEmpty ? nil : .string(stopSequences.joined(separator: "\n"))
        case .responseFormat:
            return .string(responseFormat.semanticRawValue)
        case .reasoningEffort:
            return reasoning.flatMap { $0.isEmpty ? nil : .string($0) }
        case .serviceTier:
            return serviceTier.flatMap { $0.isEmpty ? nil : .string($0) }
        }
    }

    private func resolvedParameterMappings(
        apiConfiguration: APIConfigurationItem,
        providerID: LLMProviderID,
        endpointFamily: LLMEndpointFamily,
        modelID: String,
        modelContext: ModelContext?
    ) -> [LLMParameterID: LLMParameterMappingDescriptor] {
        let descriptor: LLMModelDescriptor?
        if let modelContext,
           let models = try? modelContext.fetch(FetchDescriptor<ModelItem>()),
           let model = models.first(where: {
               $0.modelID == modelID
                   && $0.apiConfiguration?.id == apiConfiguration.id
           }) {
            model.materializeDefaultParameterMappings(preserveCustomized: true)
            descriptor = model.descriptor
        } else {
            descriptor = nil
        }
        return LLMParameterMappingResolver.resolve(
            providerID: providerID,
            endpointFamily: endpointFamily,
            modelID: modelID,
            modelDescriptor: descriptor
        )
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
            let type = LLMParameterValueType(rawValue: l.valueType) ?? .string
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
