import Foundation
import SwiftData

/// Persisted generation, provider, display, and tool settings for a conversation.
@Model
final class ConversationOptions: Equatable {
    @Relationship(deleteRule: .nullify) var apiConfiguration: APIConfigurationItem?

    var avatarImageData: Data? = nil
    var enabledToolsDict: [String: Bool]
    var toolConfigurations: [String: String]
    var enabledParameterOverrides: [String: Bool]
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

    convenience init(from: ConversationOptions) {
        self.init(avatarImageData: from.avatarImageData, apiConfiguration: from.apiConfiguration)
        enabledToolsDict = from.enabledToolsDict
        toolConfigurations = from.toolConfigurations
        enabledParameterOverrides = from.enabledParameterOverrides
        isMarkdownEnabled = from.isMarkdownEnabled
        systemPrompt = from.systemPrompt
        modelOverride = from.modelOverride
        endpointOverride = from.endpointOverride
        temperature = from.temperature
        topP = from.topP
        maxOutputTokens = from.maxOutputTokens
        stopSequences = from.stopSequences
        responseFormatRaw = from.responseFormatRaw
        reasoning = from.reasoning
        serviceTier = from.serviceTier
        streamModeRaw = from.streamModeRaw
        retryPolicyRaw = from.retryPolicyRaw
        providerExtrasJSON = from.providerExtrasJSON
    }

    init(
        avatarImageData: Data? = nil,
        apiConfiguration: APIConfigurationItem? = nil
    ) {
        self.avatarImageData = avatarImageData
        self.apiConfiguration = apiConfiguration
        self.toolConfigurations = [:]
        self.enabledToolsDict = [:]
        self.enabledParameterOverrides = [:]
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
        applyAPIConfigurationDefaults(replaceModel: false)
    }

    func copy() -> ConversationOptions {
        ConversationOptions(from: self)
    }

    func applyAPIConfigurationDefaults(replaceModel: Bool) {
        guard let apiConfiguration else { return }
        let providerID = apiConfiguration.providerIDEnum
        let profile = LLMProviderRegistry.shared.profile(for: providerID)

        if let override = endpointOverrideFamily,
           !profile.supportedEndpointFamilies.contains(override) {
            endpointOverrideFamily = nil
        }
        if endpointOverrideFamily == nil {
            endpointOverrideFamily = apiConfiguration.defaultEndpointFamilyEnum
        }

        let defaultModel = LLMModelDescriptorResolver().defaultModelID(
            for: providerID,
            apiConfiguration: apiConfiguration
        )
        let currentModel = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if replaceModel || currentModel.isEmpty {
            modelOverride = defaultModel
        }
    }

    func setEndpointOverride(_ endpoint: LLMEndpointFamily?) {
        endpointOverrideFamily = endpoint
    }

    func setModelOverride(_ model: String?) {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        modelOverride = trimmed.isEmpty ? nil : trimmed
    }

    func setStreamMode(_ mode: LLMGenerationOptions.StreamMode) {
        streamMode = mode
    }

    func parameterValue(_ parameter: LLMParameterID) -> JSONValue? {
        switch parameter {
        case .model:
            return modelOverride.flatMap { $0.isEmpty ? nil : .string($0) }
        case .systemPrompt:
            return .string(systemPrompt)
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

    func setParameterValue(_ parameter: LLMParameterID, value: JSONValue?) {
        switch parameter {
        case .model:
            setModelOverride(value?.stringValue)
        case .systemPrompt:
            systemPrompt = value?.stringValue ?? ""
        case .maxOutputTokens:
            maxOutputTokens = value?.integerValue
        case .temperature:
            temperature = value?.doubleValue
        case .topP:
            topP = value?.doubleValue
        case .stopSequences:
            stopSequences = Self.stopSequences(from: value)
        case .responseFormat:
            responseFormat = value?.stringValue.map(LLMGenerationOptions.ResponseFormat.fromSemanticRawValue) ?? .text
        case .reasoningEffort:
            let trimmed = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            reasoning = trimmed.isEmpty ? nil : trimmed
        case .serviceTier:
            let trimmed = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            serviceTier = trimmed.isEmpty ? nil : trimmed
        }
    }

    func setParameterEnabled(_ parameter: LLMParameterID, enabled: Bool) {
        var overrides = enabledParameterOverrides
        overrides[parameter.rawValue] = enabled
        enabledParameterOverrides = overrides
    }

    func isParameterEnabled(
        _ parameter: LLMParameterID,
        mapping: LLMParameterMappingDescriptor
    ) -> Bool {
        guard mapping.isEnabled else { return false }
        if mapping.isRequired { return true }
        if let override = enabledParameterOverrides[parameter.rawValue] {
            return override
        }
        return parameterValue(parameter) != nil || mapping.defaultValue != nil
    }

    func generationOptions(
        resolvedModelID: String?,
        resolvedEndpointFamily: LLMEndpointFamily?,
        mappings: [LLMParameterID: LLMParameterMappingDescriptor] = [:]
    ) -> LLMGenerationOptions {
        LLMGenerationOptions(
            systemPrompt: systemPrompt,
            modelID: modelOverride ?? resolvedModelID,
            endpointFamily: endpointOverrideFamily ?? resolvedEndpointFamily,
            temperature: includedDouble(.temperature, mappings: mappings),
            topP: includedDouble(.topP, mappings: mappings),
            maxOutputTokens: includedInt(.maxOutputTokens, mappings: mappings),
            stop: includedStopSequences(mappings: mappings),
            responseFormat: includedResponseFormat(mappings: mappings),
            reasoning: includedString(.reasoningEffort, fallback: reasoning, mappings: mappings),
            serviceTier: includedString(.serviceTier, fallback: serviceTier, mappings: mappings),
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

    func isToolEnabled(_ toolName: String) -> Bool {
        enabledToolsDict[toolName] == true
    }

    func setToolEnabled(_ toolName: String, enabled: Bool) {
        var updatedDict = enabledToolsDict
        updatedDict[toolName] = enabled
        enabledToolsDict = updatedDict
    }

    func getToolConfiguration(_ toolName: String) -> [String: JSONValue]? {
        guard let jsonString = toolConfigurations[toolName],
              let data = jsonString.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return nil
        }
        return value.objectValue
    }

    func setToolConfiguration(_ toolName: String, configuration: [String: JSONValue]?) {
        var updatedConfigs = toolConfigurations
        if let configuration,
           let data = try? JSONEncoder().encode(JSONValue.object(configuration)),
           let jsonString = String(data: data, encoding: .utf8) {
            updatedConfigs[toolName] = jsonString
        } else {
            updatedConfigs.removeValue(forKey: toolName)
        }
        toolConfigurations = updatedConfigs
    }

    private func includedString(
        _ parameter: LLMParameterID,
        fallback: String?,
        mappings: [LLMParameterID: LLMParameterMappingDescriptor]
    ) -> String? {
        guard shouldInclude(parameter, mappings: mappings) else { return nil }
        return fallback.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func includedInt(
        _ parameter: LLMParameterID,
        mappings: [LLMParameterID: LLMParameterMappingDescriptor]
    ) -> Int? {
        guard shouldInclude(parameter, mappings: mappings) else { return nil }
        return maxOutputTokens
    }

    private func includedDouble(
        _ parameter: LLMParameterID,
        mappings: [LLMParameterID: LLMParameterMappingDescriptor]
    ) -> Double? {
        guard shouldInclude(parameter, mappings: mappings) else { return nil }
        switch parameter {
        case .temperature:
            return temperature
        case .topP:
            return topP
        default:
            return nil
        }
    }

    private func includedStopSequences(mappings: [LLMParameterID: LLMParameterMappingDescriptor]) -> [String] {
        guard shouldInclude(.stopSequences, mappings: mappings) else { return [] }
        return stopSequences
    }

    private func includedResponseFormat(
        mappings: [LLMParameterID: LLMParameterMappingDescriptor]
    ) -> LLMGenerationOptions.ResponseFormat {
        shouldInclude(.responseFormat, mappings: mappings) ? responseFormat : .text
    }

    private func shouldInclude(
        _ parameter: LLMParameterID,
        mappings: [LLMParameterID: LLMParameterMappingDescriptor]
    ) -> Bool {
        guard parameter.isProviderMappable else { return true }
        guard let mapping = mappings[parameter] else { return true }
        return isParameterEnabled(parameter, mapping: mapping)
    }

    private static func stopSequences(from value: JSONValue?) -> [String] {
        guard let value else { return [] }
        if let array = value.arrayValue {
            return array.compactMap(\.stringValue).filter { !$0.isEmpty }
        }
        guard let string = value.stringValue else { return [] }
        return string
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func == (lhs: ConversationOptions, rhs: ConversationOptions) -> Bool {
        lhs.apiConfiguration?.id == rhs.apiConfiguration?.id
            && lhs.avatarImageData == rhs.avatarImageData
            && lhs.enabledToolsDict == rhs.enabledToolsDict
            && lhs.toolConfigurations == rhs.toolConfigurations
            && lhs.enabledParameterOverrides == rhs.enabledParameterOverrides
            && lhs.isMarkdownEnabled == rhs.isMarkdownEnabled
            && lhs.systemPrompt == rhs.systemPrompt
            && lhs.modelOverride == rhs.modelOverride
            && lhs.endpointOverride == rhs.endpointOverride
            && lhs.temperature == rhs.temperature
            && lhs.topP == rhs.topP
            && lhs.maxOutputTokens == rhs.maxOutputTokens
            && lhs.stopSequences == rhs.stopSequences
            && lhs.responseFormatRaw == rhs.responseFormatRaw
            && lhs.reasoning == rhs.reasoning
            && lhs.serviceTier == rhs.serviceTier
            && lhs.streamModeRaw == rhs.streamModeRaw
            && lhs.retryPolicyRaw == rhs.retryPolicyRaw
            && lhs.providerExtrasJSON == rhs.providerExtrasJSON
    }
}
