import Foundation
import SwiftData

// MARK: - Conversation Options Export

struct ConversationOptionsExportData: Codable {
    let avatarImageData: Data?
    let apiConfiguration: APIConfigurationExportData?
    let enabledToolsDict: [String: Bool]
    let toolConfigurations: [String: String]
    // Keep export key stable for existing backups; model code names this parameterEnabledStates.
    let enabledParameterOverrides: [String: Bool]
    let parameterValuesJSON: String?
    let isMarkdownEnabled: Bool
    let systemPrompt: String?
    let selectedModelID: String?
    let temperature: Double?
    let topP: Double?
    let maxOutputTokens: Int?
    let stopSequences: [String]?
    let responseFormatRaw: String?
    let reasoningEffort: String?
    let serviceTier: String?
    let streamModeRaw: String?
    let retryPolicyRaw: String?
    let providerExtrasJSON: String?
    
    init(_ options: ConversationOptions) {
        self.avatarImageData = options.avatarImageData
        self.apiConfiguration = options.apiConfiguration.map { APIConfigurationExportData($0) }
        self.enabledToolsDict = options.enabledToolsDict
        self.toolConfigurations = options.toolConfigurations
        self.enabledParameterOverrides = options.parameterInclusionPreferences
        self.parameterValuesJSON = options.parameterValuesJSON
        self.isMarkdownEnabled = options.isMarkdownEnabled
        self.systemPrompt = options.systemPrompt
        self.selectedModelID = options.selectedModelID
        self.temperature = options.temperature
        self.topP = options.topP
        self.maxOutputTokens = options.maxOutputTokens
        self.stopSequences = options.stopSequences
        self.responseFormatRaw = options.responseFormatRaw
        self.reasoningEffort = options.reasoningEffort
        self.serviceTier = options.serviceTier
        self.streamModeRaw = options.streamModeRaw
        self.retryPolicyRaw = options.retryPolicyRaw
        self.providerExtrasJSON = options.providerExtrasJSON
    }
    
    func toDataItem(context: ModelContext) -> ConversationOptions {
        let options = ConversationOptions(
            avatarImageData: avatarImageData,
            apiConfiguration: apiConfiguration?.toDataItem()
        )

        options.enabledToolsDict = enabledToolsDict
        options.toolConfigurations = toolConfigurations
        options.parameterInclusionPreferences = enabledParameterOverrides
        options.parameterValuesJSON = parameterValuesJSON ?? options.parameterValuesJSON
        options.isMarkdownEnabled = isMarkdownEnabled
        if parameterValuesJSON == nil {
            options.systemPrompt = systemPrompt ?? ""
            options.selectedModelID = selectedModelID
            options.temperature = temperature
            options.topP = topP
            options.maxOutputTokens = maxOutputTokens
            options.stopSequences = stopSequences ?? []
            options.responseFormatRaw = responseFormatRaw ?? LLMGenerationOptions.ResponseFormat.text.rawValue
            options.reasoningEffort = reasoningEffort
            options.serviceTier = serviceTier
            options.streamModeRaw = streamModeRaw ?? LLMGenerationOptions.StreamMode.disabled.rawValue
            options.providerExtrasJSON = providerExtrasJSON ?? "{}"
        }
        options.retryPolicyRaw = retryPolicyRaw ?? LLMGenerationOptions.RetryPolicy.disabled.rawValue
        options.normalizeKnownParameters()
        options.reconcileParameters()
        
        return options
    }
} 
