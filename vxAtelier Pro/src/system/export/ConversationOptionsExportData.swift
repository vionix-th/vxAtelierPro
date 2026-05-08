import Foundation
import SwiftData

// MARK: - Conversation Options Export

struct ConversationOptionsExportData: Codable {
    let avatarImageData: Data?
    let apiConfiguration: APIConfigurationExportData?
    let enabledToolsDict: [String: Bool]
    let toolConfigurations: [String: String]
    let enabledParameterOverrides: [String: Bool]
    let isMarkdownEnabled: Bool
    let systemPrompt: String?
    let modelOverride: String?
    let endpointOverride: String?
    let temperature: Double?
    let topP: Double?
    let maxOutputTokens: Int?
    let stopSequences: [String]?
    let responseFormatRaw: String?
    let reasoning: String?
    let serviceTier: String?
    let streamModeRaw: String?
    let retryPolicyRaw: String?
    let providerExtrasJSON: String?
    
    init(_ options: ConversationOptions) {
        self.avatarImageData = options.avatarImageData
        self.apiConfiguration = options.apiConfiguration.map { APIConfigurationExportData($0) }
        self.enabledToolsDict = options.enabledToolsDict
        self.toolConfigurations = options.toolConfigurations
        self.enabledParameterOverrides = options.enabledParameterOverrides
        self.isMarkdownEnabled = options.isMarkdownEnabled
        self.systemPrompt = options.systemPrompt
        self.modelOverride = options.modelOverride
        self.endpointOverride = options.endpointOverride
        self.temperature = options.temperature
        self.topP = options.topP
        self.maxOutputTokens = options.maxOutputTokens
        self.stopSequences = options.stopSequences
        self.responseFormatRaw = options.responseFormatRaw
        self.reasoning = options.reasoning
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
        options.enabledParameterOverrides = enabledParameterOverrides
        options.isMarkdownEnabled = isMarkdownEnabled
        options.systemPrompt = systemPrompt ?? ""
        options.modelOverride = modelOverride
        options.endpointOverride = endpointOverride
        options.temperature = temperature
        options.topP = topP
        options.maxOutputTokens = maxOutputTokens
        options.stopSequences = stopSequences ?? []
        options.responseFormatRaw = responseFormatRaw ?? LLMGenerationOptions.ResponseFormat.text.rawValue
        options.reasoning = reasoning
        options.serviceTier = serviceTier
        options.streamModeRaw = streamModeRaw ?? LLMGenerationOptions.StreamMode.auto.rawValue
        options.retryPolicyRaw = retryPolicyRaw ?? LLMGenerationOptions.RetryPolicy.disabled.rawValue
        options.providerExtrasJSON = providerExtrasJSON ?? "{}"
        
        return options
    }
} 
