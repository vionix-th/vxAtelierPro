import Foundation
import SwiftData

/// Persisted generation, provider, display, and tool settings for a conversation.
@Model
final class ConversationOptions: Equatable {
    @Relationship(deleteRule: .nullify) var apiConfiguration: APIConfigurationItem?

    var avatarImageData: Data? = nil
    var enabledToolsDict: [String: Bool]
    var toolConfigurations: [String: String]
    @Attribute(originalName: "enabledParameterOverrides") var parameterEnabledStates: [String: Bool]
    var parameterValuesJSON: String
    var isMarkdownEnabled: Bool = AppDefaults.isMarkdownEnabled
    var retryPolicyRaw: String

    var parameterInclusionPreferences: [String: Bool] {
        get { parameterEnabledStates }
        set { parameterEnabledStates = newValue }
    }

    var selectedModelID: String? {
        get {
            parameterValue(.model)?.stringValue.flatMap {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        set { setParameterValue(.model, value: newValue.map { .string($0) }) }
    }

    var systemPrompt: String {
        get { parameterValue(.systemPrompt)?.stringValue ?? "" }
        set { setParameterValue(.systemPrompt, value: .string(newValue)) }
    }

    var temperature: Double? {
        get { parameterValue(.temperature)?.doubleValue }
        set { setParameterValue(.temperature, value: newValue.map { .number($0) }) }
    }

    var topP: Double? {
        get { parameterValue(.topP)?.doubleValue }
        set { setParameterValue(.topP, value: newValue.map { .number($0) }) }
    }

    var maxOutputTokens: Int? {
        get { parameterValue(.maxOutputTokens)?.integerValue }
        set { setParameterValue(.maxOutputTokens, value: newValue.map { .integer($0) }) }
    }

    var topK: Int? {
        get { parameterValue(.topK)?.integerValue }
        set { setParameterValue(.topK, value: newValue.map { .integer($0) }) }
    }

    var stopSequences: [String] {
        get { Self.stopSequences(from: parameterValue(.stopSequences)) }
        set { setParameterValue(.stopSequences, value: newValue.isEmpty ? nil : .array(newValue.map { .string($0) })) }
    }

    var responseFormatRaw: String {
        get { parameterValue(.responseFormat)?.stringValue ?? LLMGenerationOptions.ResponseFormat.text.rawValue }
        set { setParameterValue(.responseFormat, value: .string(newValue)) }
    }

    var reasoningEffort: String? {
        get { parameterValue(.reasoningEffort)?.stringValue }
        set { setParameterValue(.reasoningEffort, value: newValue.map { .string($0) }) }
    }

    var reasoningSummary: String? {
        get { parameterValue(.reasoningSummary)?.stringValue }
        set { setParameterValue(.reasoningSummary, value: newValue.map { .string($0) }) }
    }

    var reasoningBudgetTokens: Int? {
        get { parameterValue(.reasoningBudgetTokens)?.integerValue }
        set { setParameterValue(.reasoningBudgetTokens, value: newValue.map { .integer($0) }) }
    }

    var serviceTier: String? {
        get { parameterValue(.serviceTier)?.stringValue }
        set { setParameterValue(.serviceTier, value: newValue.map { .string($0) }) }
    }

    var textVerbosity: String? {
        get { parameterValue(.textVerbosity)?.stringValue }
        set { setParameterValue(.textVerbosity, value: newValue.map { .string($0) }) }
    }

    var streamModeRaw: String {
        get { streamMode.rawValue }
        set { streamMode = LLMGenerationOptions.StreamMode(rawValue: newValue) ?? .disabled }
    }

    var providerExtrasJSON: String {
        get {
            let extras = decodedParameterValues.filter { key, _ in
                guard let parameterID = LLMParameterID(rawValue: key) else { return true }
                return Self.providerExtraParameters.contains(parameterID)
            }
            guard let data = try? JSONEncoder().encode(extras),
                  let json = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return json
        }
        set {
            guard let data = newValue.data(using: .utf8),
                  let extras = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
                return
            }
            var values = decodedParameterValues
            for (key, value) in extras {
                values[key] = value
            }
            decodedParameterValues = values
        }
    }

    var streamMode: LLMGenerationOptions.StreamMode {
        get { (parameterValue(.stream)?.boolValue ?? false) ? .enabled : .disabled }
        set { setStreamMode(newValue) }
    }

    var retryPolicy: LLMGenerationOptions.RetryPolicy {
        get { LLMGenerationOptions.RetryPolicy(rawValue: retryPolicyRaw) ?? .disabled }
        set { retryPolicyRaw = newValue.rawValue }
    }

    var responseFormat: LLMGenerationOptions.ResponseFormat {
        get { LLMGenerationOptions.ResponseFormat.fromSemanticRawValue(responseFormatRaw) }
        set { responseFormatRaw = newValue.semanticRawValue }
    }

    convenience init(from: ConversationOptions) {
        self.init(avatarImageData: from.avatarImageData, apiConfiguration: from.apiConfiguration)
        enabledToolsDict = from.enabledToolsDict
        toolConfigurations = from.toolConfigurations
        parameterEnabledStates = from.parameterEnabledStates
        parameterValuesJSON = from.parameterValuesJSON
        isMarkdownEnabled = from.isMarkdownEnabled
        retryPolicyRaw = from.retryPolicyRaw
        normalizeKnownParameters()
        reconcileParameters()
    }

    init(
        avatarImageData: Data? = nil,
        apiConfiguration: APIConfigurationItem? = nil
    ) {
        self.avatarImageData = avatarImageData
        self.apiConfiguration = apiConfiguration
        self.toolConfigurations = [:]
        self.enabledToolsDict = [:]
        self.parameterEnabledStates = [:]
        self.parameterValuesJSON = "{}"
        self.retryPolicyRaw = LLMGenerationOptions.RetryPolicy.disabled.rawValue
        self.isMarkdownEnabled = AppDefaults.isMarkdownEnabled
        applyAPIConfigurationDefaults(replaceSelectedModel: false)
        if apiConfiguration == nil {
            normalizeKnownParameters()
        }
    }

    func copy() -> ConversationOptions {
        ConversationOptions(from: self)
    }

    func normalizeKnownParameters() {
        var enabledStates = parameterEnabledStates
        for parameterID in LLMParameterID.allCases where enabledStates[parameterID.rawValue] == nil {
            enabledStates[parameterID.rawValue] = Self.defaultEnabledState(for: parameterID)
        }
        parameterEnabledStates = enabledStates
    }

    func reconcileParameters(
        apiConfiguration: APIConfigurationItem? = nil,
        modelID explicitModelID: String? = nil
    ) {
        let configuration = apiConfiguration ?? self.apiConfiguration
        let previousEnabledStates = parameterEnabledStates
        normalizeKnownParameters()
        guard let configuration else { return }

        let selectedModel = explicitModelID ?? selectedModelID ?? configuration.defaultModelID
        guard let modelID = selectedModel,
              let model = configuration.models.first(where: { $0.modelID == modelID }) else {
            return
        }

        let adapterID = configuration.defaultAdapterIDEnum
        let availability = LLMParameterAvailabilityMappingResolver.resolve(
            adapterID: adapterID,
            availability: model.parameterAvailability.map(\.descriptor)
        )
        var enabledStates = parameterEnabledStates

        for parameterID in LLMParameterID.allCases {
            guard parameterID.isProviderMappable else {
                enabledStates[parameterID.rawValue] = true
                continue
            }
            guard let descriptor = availability[parameterID] else {
                enabledStates[parameterID.rawValue] = false
                continue
            }
            if descriptor.isRequired {
                enabledStates[parameterID.rawValue] = true
            } else if !descriptor.isAvailable {
                enabledStates[parameterID.rawValue] = false
            } else if previousEnabledStates[parameterID.rawValue] == nil {
                enabledStates[parameterID.rawValue] = descriptor.isEnabled
            }
            if parameterValue(parameterID) == nil, let defaultValue = descriptor.defaultValue {
                setParameterValue(parameterID, value: defaultValue, reconcileAfterModelChange: false)
            }
        }

        parameterEnabledStates = enabledStates
    }

    func applyAPIConfigurationDefaults(replaceSelectedModel: Bool) {
        guard let apiConfiguration else { return }
        let defaultModel = apiConfiguration.defaultModelID
        let currentModel = selectedModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if replaceSelectedModel || currentModel.isEmpty {
            setSelectedModelID(defaultModel, reconcileAfterModelChange: false)
        }
        reconcileParameters(apiConfiguration: apiConfiguration, modelID: selectedModelID)
    }

    func setSelectedModelID(_ model: String?) {
        setSelectedModelID(model, reconcileAfterModelChange: true)
    }

    private func setSelectedModelID(_ model: String?, reconcileAfterModelChange: Bool) {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        setParameterValue(.model, value: trimmed.isEmpty ? nil : .string(trimmed), reconcileAfterModelChange: false)
        if reconcileAfterModelChange {
            reconcileParameters(modelID: selectedModelID)
        }
    }

    func setStreamMode(_ mode: LLMGenerationOptions.StreamMode) {
        setParameterValue(.stream, value: .boolean(mode == .enabled), reconcileAfterModelChange: false)
        setParameterEnabled(.stream, enabled: true)
    }

    func parameterValue(_ parameter: LLMParameterID) -> JSONValue? {
        decodedParameterValues[parameter.rawValue]
    }

    func setParameterValue(_ parameter: LLMParameterID, value: JSONValue?) {
        setParameterValue(parameter, value: value, reconcileAfterModelChange: parameter == .model)
    }

    private func setParameterValue(
        _ parameter: LLMParameterID,
        value: JSONValue?,
        reconcileAfterModelChange: Bool
    ) {
        var values = decodedParameterValues
        if let value {
            values[parameter.rawValue] = normalizedValue(value, for: parameter)
        } else {
            values.removeValue(forKey: parameter.rawValue)
        }
        decodedParameterValues = values
        if reconcileAfterModelChange {
            reconcileParameters(modelID: selectedModelID)
        }
    }

    func setParameterEnabled(_ parameter: LLMParameterID, enabled: Bool) {
        var states = parameterEnabledStates
        states[parameter.rawValue] = enabled
        parameterEnabledStates = states
    }

    func parameterInclusionPreference(_ parameter: LLMParameterID) -> Bool? {
        parameterEnabledStates[parameter.rawValue]
    }

    func isParameterEnabled(_ parameter: LLMParameterID) -> Bool {
        parameterEnabledStates[parameter.rawValue] ?? Self.defaultEnabledState(for: parameter)
    }

    func generationOptions(
        resolvedModelID: String?
    ) -> LLMGenerationOptions {
        normalizeKnownParameters()
        let modelID = selectedModelID ?? resolvedModelID
        let extras = enabledProviderExtras()

        return LLMGenerationOptions(
            systemPrompt: systemPrompt,
            modelID: modelID,
            temperature: enabledValue(.temperature)?.doubleValue,
            topP: enabledValue(.topP)?.doubleValue,
            maxOutputTokens: enabledValue(.maxOutputTokens)?.integerValue,
            topK: enabledValue(.topK)?.integerValue,
            stop: Self.stopSequences(from: enabledValue(.stopSequences)),
            responseFormat: enabledValue(.responseFormat)?.stringValue.map(LLMGenerationOptions.ResponseFormat.fromSemanticRawValue) ?? .text,
            reasoning: enabledValue(.reasoningEffort)?.stringValue.flatMap { $0.isEmpty ? nil : $0 },
            reasoningSummary: enabledValue(.reasoningSummary)?.stringValue.flatMap { $0.isEmpty ? nil : $0 },
            reasoningBudgetTokens: enabledValue(.reasoningBudgetTokens)?.integerValue,
            serviceTier: enabledValue(.serviceTier)?.stringValue.flatMap { $0.isEmpty ? nil : $0 },
            textVerbosity: enabledValue(.textVerbosity)?.stringValue.flatMap { $0.isEmpty ? nil : $0 },
            streamMode: enabledValue(.stream)?.boolValue == true ? .enabled : .disabled,
            retryPolicy: retryPolicy,
            providerExtras: extras
        )
    }

    var decodedParameterValues: [String: JSONValue] {
        get {
            guard let data = parameterValuesJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                parameterValuesJSON = "{}"
                return
            }
            parameterValuesJSON = json
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

    private func enabledValue(_ parameter: LLMParameterID) -> JSONValue? {
        guard isParameterEnabled(parameter) else { return nil }
        return parameterValue(parameter)
    }

    private func enabledProviderExtras() -> [String: JSONValue] {
        decodedParameterValues.reduce(into: [:]) { result, entry in
            guard let parameterID = LLMParameterID(rawValue: entry.key),
                  Self.providerExtraParameters.contains(parameterID),
                  isParameterEnabled(parameterID) else {
                return
            }
            result[entry.key] = entry.value
        }
    }

    private func normalizedValue(_ value: JSONValue, for parameter: LLMParameterID) -> JSONValue {
        switch parameter {
        case .model, .systemPrompt, .responseFormat, .reasoningEffort, .reasoningSummary,
             .serviceTier, .toolChoice, .promptCacheKey, .previousResponseID, .include,
             .textVerbosity, .logitBias, .user, .safetyIdentifier:
            return value.stringValue.map { .string($0) } ?? value
        case .maxOutputTokens, .topK, .reasoningBudgetTokens, .seed:
            return value.integerValue.map { .integer($0) } ?? value
        case .temperature, .topP, .frequencyPenalty, .presencePenalty:
            return value.doubleValue.map { .number($0) } ?? value
        case .stream, .store, .parallelToolCalls:
            return value.boolValue.map { .boolean($0) } ?? value
        case .stopSequences:
            let stops = Self.stopSequences(from: value)
            return stops.isEmpty ? .array([]) : .array(stops.map { .string($0) })
        }
    }

    private static func defaultEnabledState(for parameter: LLMParameterID) -> Bool {
        switch parameter {
        case .model, .systemPrompt:
            return true
        default:
            return false
        }
    }

    private static let providerExtraParameters: Set<LLMParameterID> = [
        .store,
        .toolChoice,
        .parallelToolCalls,
        .promptCacheKey,
        .previousResponseID,
        .include,
        .frequencyPenalty,
        .presencePenalty,
        .logitBias,
        .seed,
        .user,
        .safetyIdentifier
    ]

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
            && lhs.parameterEnabledStates == rhs.parameterEnabledStates
            && lhs.parameterValuesJSON == rhs.parameterValuesJSON
            && lhs.isMarkdownEnabled == rhs.isMarkdownEnabled
            && lhs.retryPolicyRaw == rhs.retryPolicyRaw
    }
}
