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
                transportKind: .remoteHTTP,
                defaultBaseURL: AppDefaults.OpenAi.baseURL,
                authKind: .bearerToken,
                defaultAdapterID: .openAIResponses,
                supportedAdapterIDs: [.openAIResponses, .openAIChatCompletions],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .openAICodexChatGPTSubscription,
                name: "Codex ChatGPT Subscription",
                transportKind: .remoteHTTP,
                defaultBaseURL: "https://chatgpt.com/backend-api/codex",
                authKind: .codexChatGPTOAuth,
                defaultAdapterID: .openAIResponses,
                supportedAdapterIDs: [.openAIResponses],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .appleIntelligence,
                name: "Apple Intelligence",
                transportKind: .localSystem,
                defaultBaseURL: "",
                authKind: .none,
                defaultAdapterID: .foundationModels,
                supportedAdapterIDs: [.foundationModels],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .anthropic,
                name: "Anthropic",
                transportKind: .remoteHTTP,
                defaultBaseURL: AppDefaults.Anthropic.baseURL,
                authKind: .xAPIKey,
                defaultAdapterID: .anthropicMessages,
                supportedAdapterIDs: [.anthropicMessages],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .openRouter,
                name: "OpenRouter",
                transportKind: .remoteHTTP,
                defaultBaseURL: "https://openrouter.ai/api/v1",
                authKind: .bearerToken,
                defaultAdapterID: .openAICompatibleChatCompletions,
                supportedAdapterIDs: [.openAICompatibleChatCompletions],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .lmStudio,
                name: "LM Studio",
                transportKind: .remoteHTTP,
                defaultBaseURL: "http://localhost:1234/v1",
                authKind: .none,
                defaultAdapterID: .openAICompatibleChatCompletions,
                supportedAdapterIDs: [.openAICompatibleChatCompletions],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .ollama,
                name: "Ollama",
                transportKind: .remoteHTTP,
                defaultBaseURL: "http://localhost:11434/v1",
                authKind: .none,
                defaultAdapterID: .openAICompatibleChatCompletions,
                supportedAdapterIDs: [.openAICompatibleChatCompletions],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .xAI,
                name: "xAI",
                transportKind: .remoteHTTP,
                defaultBaseURL: AppDefaults.XAI.baseURL,
                authKind: .bearerToken,
                defaultAdapterID: .openAICompatibleChatCompletions,
                supportedAdapterIDs: [.openAICompatibleChatCompletions],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .deepSeek,
                name: "DeepSeek",
                transportKind: .remoteHTTP,
                defaultBaseURL: AppDefaults.DeepSeek.baseURL,
                authKind: .bearerToken,
                defaultAdapterID: .openAICompatibleChatCompletions,
                supportedAdapterIDs: [.openAICompatibleChatCompletions],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .customOpenAICompatible,
                name: "Custom OpenAI Compatible",
                transportKind: .remoteHTTP,
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
        case .foundationModels:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, *) {
                return FoundationModelsAdapter(profile: profile)
            }
            #endif
            return DisabledLLMProviderAdapter(
                profile: profile,
                message: "\(profile.name) requires macOS 26.0 or iOS 26.0 or newer."
            )
        }
    }

    /// Returns a user-facing availability summary for local-model providers, if available.
    func localStatusText(for providerID: LLMProviderID) -> String? {
        guard profile(for: providerID).transportKind != .remoteHTTP else { return nil }
        #if canImport(FoundationModels)
        if providerID == .appleIntelligence {
            if #available(macOS 26.0, iOS 26.0, *) {
                return localBackend(for: providerID)?.statusText()
            } else {
                return "Foundation Models requires macOS 26.0 or iOS 26.0 or newer."
            }
        }
        #endif
        return localBackend(for: providerID)?.statusText()
    }

    /// Returns the synthetic model candidates exposed by a local-model backend.
    func localModelCandidates(
        for providerID: LLMProviderID,
        configuration: LLMProviderConfiguration
    ) -> [LLMModelDescriptor] {
        localBackend(for: providerID)?.modelCandidates(configuration: configuration) ?? []
    }

    /// Returns the local backend associated with one provider profile.
    func localBackend(for providerID: LLMProviderID) -> (any LLMLocalModelBackend)? {
        switch providerID {
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, *) {
                return FoundationModelsBackend()
            }
            #endif
            return nil
        default:
            return nil
        }
    }

    /// Infers a provider identifier from user- or import-supplied provider text.
    static func providerID(fromProviderName providerName: String) -> LLMProviderID {
        let probe = providerName.lowercased()
        if probe.contains("anthropic") || probe.contains("claude") { return .anthropic }
        if probe.contains("apple intelligence") || probe.contains("foundation models") {
            return .appleIntelligence
        }
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
