import Foundation
import SwiftData

/// Persisted generation, provider, display, and tool settings for a conversation.
@Model
final class ConversationOptions: Equatable {
    @Relationship(deleteRule: .nullify) var apiConfiguration: APIConfigurationItem?

    var avatarImageData: Data? = nil
    var enabledToolsDict: [String: Bool]
    var toolConfigurations: [String: String]
    @Attribute(originalName: "enabledParameterOverrides") var parameterInclusionPreferences: [String: Bool]
    var isMarkdownEnabled: Bool = AppDefaults.isMarkdownEnabled

    var systemPrompt: String
    var selectedModelID: String?
    var temperature: Double?
    var topP: Double?
    var maxOutputTokens: Int?
    var stopSequences: [String]
    var responseFormatRaw: String
    @Attribute(originalName: "reasoning") var reasoningEffort: String?
    var serviceTier: String?
    var streamModeRaw: String
    var retryPolicyRaw: String
    var providerExtrasJSON: String

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
        parameterInclusionPreferences = from.parameterInclusionPreferences
        isMarkdownEnabled = from.isMarkdownEnabled
        systemPrompt = from.systemPrompt
        selectedModelID = from.selectedModelID
        temperature = from.temperature
        topP = from.topP
        maxOutputTokens = from.maxOutputTokens
        stopSequences = from.stopSequences
        responseFormatRaw = from.responseFormatRaw
        reasoningEffort = from.reasoningEffort
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
        self.parameterInclusionPreferences = [:]
        self.systemPrompt = ""
        self.selectedModelID = nil
        self.temperature = nil
        self.topP = nil
        self.maxOutputTokens = nil
        self.stopSequences = []
        self.responseFormatRaw = LLMGenerationOptions.ResponseFormat.text.rawValue
        self.reasoningEffort = nil
        self.serviceTier = nil
        self.streamModeRaw = LLMGenerationOptions.StreamMode.auto.rawValue
        self.retryPolicyRaw = LLMGenerationOptions.RetryPolicy.disabled.rawValue
        self.providerExtrasJSON = "{}"
        applyAPIConfigurationDefaults(replaceSelectedModel: false)
    }

    func copy() -> ConversationOptions {
        ConversationOptions(from: self)
    }

    func applyAPIConfigurationDefaults(replaceSelectedModel: Bool) {
        guard let apiConfiguration else { return }
        let defaultModel = apiConfiguration.defaultModelID
        let currentModel = selectedModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if replaceSelectedModel || currentModel.isEmpty {
            selectedModelID = defaultModel
        }
    }

    func setSelectedModelID(_ model: String?) {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        selectedModelID = trimmed.isEmpty ? nil : trimmed
    }

    func setStreamMode(_ mode: LLMGenerationOptions.StreamMode) {
        streamMode = mode
    }

    func parameterValue(_ parameter: LLMParameterID) -> JSONValue? {
        switch parameter {
        case .model:
            return selectedModelID.flatMap { $0.isEmpty ? nil : .string($0) }
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
            return reasoningEffort.flatMap { $0.isEmpty ? nil : .string($0) }
        case .serviceTier:
            return serviceTier.flatMap { $0.isEmpty ? nil : .string($0) }
        case .stream:
            switch streamMode {
            case .enabled:
                return .boolean(true)
            case .disabled:
                return .boolean(false)
            case .auto:
                return nil
            }
        case .store,
             .toolChoice,
             .parallelToolCalls,
             .promptCacheKey,
             .previousResponseID,
             .include,
             .textVerbosity,
             .frequencyPenalty,
             .presencePenalty,
             .logitBias,
             .seed,
             .user,
             .safetyIdentifier,
             .reasoningSummary:
            return decodedProviderExtras[parameter.rawValue]
        }
    }

    func setParameterValue(_ parameter: LLMParameterID, value: JSONValue?) {
        switch parameter {
        case .model:
            setSelectedModelID(value?.stringValue)
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
            reasoningEffort = trimmed.isEmpty ? nil : trimmed
        case .serviceTier:
            let trimmed = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            serviceTier = trimmed.isEmpty ? nil : trimmed
        case .stream:
            if let bool = value?.boolValue {
                streamMode = bool ? .enabled : .disabled
            } else if let rawValue = value?.stringValue {
                streamMode = LLMGenerationOptions.StreamMode(rawValue: rawValue) ?? .auto
            } else {
                streamMode = .auto
            }
        case .store,
             .toolChoice,
             .parallelToolCalls,
             .promptCacheKey,
             .previousResponseID,
             .include,
             .textVerbosity,
             .frequencyPenalty,
             .presencePenalty,
             .logitBias,
             .seed,
             .user,
             .safetyIdentifier,
             .reasoningSummary:
            var extras = decodedProviderExtras
            extras[parameter.rawValue] = value
            decodedProviderExtras = extras
        }
    }

    func setParameterEnabled(_ parameter: LLMParameterID, enabled: Bool) {
        var preferences = parameterInclusionPreferences
        preferences[parameter.rawValue] = enabled
        parameterInclusionPreferences = preferences
    }

    func parameterInclusionPreference(_ parameter: LLMParameterID) -> Bool? {
        parameterInclusionPreferences[parameter.rawValue]
    }

    func generationOptions(
        resolvedModelID: String?
    ) -> LLMGenerationOptions {
        LLMGenerationOptions(
            systemPrompt: systemPrompt,
            modelID: selectedModelID ?? resolvedModelID,
            temperature: temperature,
            topP: topP,
            maxOutputTokens: maxOutputTokens,
            stop: stopSequences,
            responseFormat: responseFormat,
            reasoning: reasoningEffort.flatMap { $0.isEmpty ? nil : $0 },
            serviceTier: serviceTier.flatMap { $0.isEmpty ? nil : $0 },
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
            && lhs.parameterInclusionPreferences == rhs.parameterInclusionPreferences
            && lhs.isMarkdownEnabled == rhs.isMarkdownEnabled
            && lhs.systemPrompt == rhs.systemPrompt
            && lhs.selectedModelID == rhs.selectedModelID
            && lhs.temperature == rhs.temperature
            && lhs.topP == rhs.topP
            && lhs.maxOutputTokens == rhs.maxOutputTokens
            && lhs.stopSequences == rhs.stopSequences
            && lhs.responseFormatRaw == rhs.responseFormatRaw
            && lhs.reasoningEffort == rhs.reasoningEffort
            && lhs.serviceTier == rhs.serviceTier
            && lhs.streamModeRaw == rhs.streamModeRaw
            && lhs.retryPolicyRaw == rhs.retryPolicyRaw
            && lhs.providerExtrasJSON == rhs.providerExtrasJSON
    }
}
