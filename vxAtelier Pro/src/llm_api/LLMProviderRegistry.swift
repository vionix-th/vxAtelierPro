import Foundation

/// Registry of built-in provider profiles and their adapter implementations.
struct LLMProviderRegistry {
    static let shared = LLMProviderRegistry()

    let profiles: [LLMProviderID: LLMProviderProfile]

    /// Builds the built-in provider profiles used by configuration and adapter selection.
    init() {
        let allProfiles = [
            LLMProviderProfile(
                id: .openAIPlatform,
                name: "OpenAI",
                defaultBaseURL: AppDefaults.OpenAi.baseURL,
                authKind: .bearerToken,
                defaultAdapterID: .openAIResponses,
                supportedAdapterIDs: [.openAIResponses, .openAIChatCompletions],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .openAICodexChatGPTSubscription,
                name: "Codex ChatGPT Subscription",
                defaultBaseURL: "https://chatgpt.com/backend-api/codex",
                authKind: .codexChatGPTOAuth,
                defaultAdapterID: .openAIResponses,
                supportedAdapterIDs: [.openAIResponses],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .anthropic,
                name: "Anthropic",
                defaultBaseURL: AppDefaults.Anthropic.baseURL,
                authKind: .xAPIKey,
                defaultAdapterID: .anthropicMessages,
                supportedAdapterIDs: [.anthropicMessages],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .openRouter,
                name: "OpenRouter",
                defaultBaseURL: "https://openrouter.ai/api/v1",
                authKind: .bearerToken,
                defaultAdapterID: .openAICompatibleChatCompletions,
                supportedAdapterIDs: [.openAICompatibleChatCompletions],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .lmStudio,
                name: "LM Studio",
                defaultBaseURL: "http://localhost:1234/v1",
                authKind: .none,
                defaultAdapterID: .openAICompatibleChatCompletions,
                supportedAdapterIDs: [.openAICompatibleChatCompletions],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .ollama,
                name: "Ollama",
                defaultBaseURL: "http://localhost:11434/v1",
                authKind: .none,
                defaultAdapterID: .openAICompatibleChatCompletions,
                supportedAdapterIDs: [.openAICompatibleChatCompletions],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .xAI,
                name: "xAI",
                defaultBaseURL: AppDefaults.XAI.baseURL,
                authKind: .bearerToken,
                defaultAdapterID: .openAICompatibleChatCompletions,
                supportedAdapterIDs: [.openAICompatibleChatCompletions],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .deepSeek,
                name: "DeepSeek",
                defaultBaseURL: AppDefaults.DeepSeek.baseURL,
                authKind: .bearerToken,
                defaultAdapterID: .openAICompatibleChatCompletions,
                supportedAdapterIDs: [.openAICompatibleChatCompletions],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .customOpenAICompatible,
                name: "Custom OpenAI Compatible",
                defaultBaseURL: AppDefaults.OpenAi.baseURL,
                authKind: .bearerToken,
                defaultAdapterID: .openAICompatibleChatCompletions,
                supportedAdapterIDs: [.openAICompatibleChatCompletions],
                isEnabled: true
            )
        ]
        self.profiles = Dictionary(uniqueKeysWithValues: allProfiles.map { ($0.id, $0) })
    }

    /// Returns the profile for a provider, falling back to the custom compatible profile.
    func profile(for id: LLMProviderID) -> LLMProviderProfile {
        profiles[id] ?? profiles[.customOpenAICompatible]!
    }

    /// Creates the default adapter appropriate for the provider profile.
    func defaultAdapter(for providerID: LLMProviderID) -> LLMProviderAdapter {
        let profile = profile(for: providerID)
        return adapter(for: profile.defaultAdapterID, providerID: providerID)
    }

    /// Creates an adapter appropriate for a provider and generation wire contract.
    func adapter(for adapterID: LLMAdapterID, providerID: LLMProviderID) -> LLMProviderAdapter {
        let profile = profile(for: providerID)
        guard profile.isEnabled else {
            return DisabledLLMProviderAdapter(profile: profile, message: "\(profile.name) is disabled.")
        }
        guard profile.supportedAdapterIDs.contains(adapterID) else {
            return DisabledLLMProviderAdapter(
                profile: profile,
                message: "\(profile.name) does not support \(adapterID.rawValue)."
            )
        }

        switch adapterID {
        case .openAIResponses:
            return OpenAIResponsesAdapter(profile: profile)
        case .openAIChatCompletions:
            return OpenAIChatCompletionsAdapter(profile: profile)
        case .openAICompatibleChatCompletions:
            return OpenAICompatibleChatCompletionsAdapter(profile: profile)
        case .anthropicMessages:
            return AnthropicMessagesAdapter(profile: profile)
        }
    }

    /// Infers a provider identifier from user- or import-supplied provider text.
    static func providerID(fromProviderName providerName: String) -> LLMProviderID {
        let probe = providerName.lowercased()
        if probe.contains("anthropic") || probe.contains("claude") { return .anthropic }
        if probe.contains("openrouter") { return .openRouter }
        if probe.contains("lm studio") { return .lmStudio }
        if probe.contains("ollama") { return .ollama }
        if probe.contains("xai") || probe.contains("x.ai") || probe.contains("grok") { return .xAI }
        if probe.contains("deepseek") { return .deepSeek }
        if probe.contains("codex") && probe.contains("chatgpt") { return .openAICodexChatGPTSubscription }
        if probe.contains("chatgpt") { return .openAICodexChatGPTSubscription }
        if probe.contains("custom") { return .customOpenAICompatible }
        if probe.contains("openai") { return .openAIPlatform }
        return .customOpenAICompatible
    }
}
