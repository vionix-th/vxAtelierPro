import Foundation

struct LLMAdapterRegistry {
    static let shared = LLMAdapterRegistry()

    func resolve(_ adapterID: LLMAdapterID) throws -> any LLMGenerationAdapter {
        switch adapterID {
        case .openAIResponses:
            return OpenAIResponsesAdapter()
        case .openAIChatCompletions:
            return OpenAIChatCompletionsAdapter()
        case .openAIChatCompletionsLegacy:
            return OpenAIChatCompletionsLegacyAdapter()
        case .openRouterChatCompletions:
            return OpenRouterChatCompletionsAdapter()
        case .anthropicMessages:
            return AnthropicMessagesAdapter()
        case .foundationModels:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, *) {
                return FoundationModelsAdapter()
            }
            #endif
            throw LLMProviderError.localModelUnavailable(
                "Foundation Models requires macOS 26.0 or iOS 26.0 or newer."
            )
        }
    }
}
