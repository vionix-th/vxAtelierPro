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
                id: .openAIChatGPTSubscription,
                name: "ChatGPT Subscription",
                defaultBaseURL: "http://127.0.0.1",
                authKind: .chatGPTOAuth,
                defaultAdapterID: .openAIResponses,
                supportedAdapterIDs: [.openAIResponses],
                isEnabled: false
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
            LLMProviderProfile.openAICompatible(
                id: .openRouter,
                name: "OpenRouter",
                baseURL: "https://openrouter.ai/api/v1"
            ),
            LLMProviderProfile.openAICompatible(
                id: .lmStudio,
                name: "LM Studio",
                baseURL: "http://localhost:1234/v1"
            ),
            LLMProviderProfile.openAICompatible(
                id: .ollama,
                name: "Ollama",
                baseURL: "http://localhost:11434/v1"
            ),
            LLMProviderProfile.openAICompatible(
                id: .xAI,
                name: "xAI",
                baseURL: AppDefaults.XAI.baseURL
            ),
            LLMProviderProfile.openAICompatible(
                id: .deepSeek,
                name: "DeepSeek",
                baseURL: AppDefaults.DeepSeek.baseURL
            ),
            LLMProviderProfile.openAICompatible(
                id: .customOpenAICompatible,
                name: "Custom OpenAI Compatible",
                baseURL: AppDefaults.OpenAi.baseURL
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
            return DisabledLLMProviderAdapter(
                profile: profile,
                message: "ChatGPT subscription auth is disabled because no supported embedded OAuth, device-code, or Codex-token flow is configured."
            )
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
        if probe.contains("chatgpt") { return .openAIChatGPTSubscription }
        if probe.contains("custom") { return .customOpenAICompatible }
        if probe.contains("openai") { return .openAIPlatform }
        return .customOpenAICompatible
    }
}

/// Factories for reusable provider profile shapes.
extension LLMProviderProfile {
    /// Builds a profile for providers that implement the OpenAI Chat Completions shape.
    static func openAICompatible(
        id: LLMProviderID,
        name: String,
        baseURL: String
    ) -> LLMProviderProfile {
        LLMProviderProfile(
            id: id,
            name: name,
            defaultBaseURL: baseURL,
            authKind: id == .lmStudio || id == .ollama ? .none : .bearerToken,
            defaultAdapterID: .openAICompatibleChatCompletions,
            supportedAdapterIDs: [.openAICompatibleChatCompletions],
            isEnabled: true
        )
    }
}
