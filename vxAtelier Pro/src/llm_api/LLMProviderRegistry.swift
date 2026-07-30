import Foundation

struct LLMProviderRegistry {
    static let shared = LLMProviderRegistry()

    let profiles: [LLMProviderID: LLMProviderProfile]
    private let integrations: [LLMProviderID: any LLMProviderIntegration]

    init() {
        let profiles = Self.makeProfiles()
        self.profiles = profiles

        var integrations: [LLMProviderID: any LLMProviderIntegration] = [:]
        for providerID in LLMProviderID.allCases {
            guard let profile = profiles[providerID] else { continue }
            switch providerID {
            case .openCodeZen:
                integrations[providerID] = OpenCodeZenProviderIntegration(profile: profile)
            case .appleIntelligence:
                #if canImport(FoundationModels)
                if #available(macOS 26.0, iOS 26.0, *) {
                    integrations[providerID] = AppleIntelligenceProviderIntegration(profile: profile)
                }
                #endif
            default:
                integrations[providerID] = StandardLLMProviderIntegration(
                    profile: profile,
                    catalogs: Self.catalogs(for: profile)
                )
            }
        }
        self.integrations = integrations
    }

    func profile(for id: LLMProviderID) -> LLMProviderProfile {
        guard let profile = profiles[id] else {
            preconditionFailure("Missing provider profile for \(id.rawValue).")
        }
        return profile
    }

    func validateRoute(adapterID: LLMAdapterID, providerID: LLMProviderID) throws {
        let configuration = LLMProviderConfiguration(
            providerID: providerID,
            baseURL: profile(for: providerID).route(for: adapterID)?.defaultBaseURL ?? ""
        )
        _ = try resolveRoute(
            adapterID: adapterID,
            providerID: providerID,
            modelID: nil,
            configuration: configuration
        )
    }

    func resolveRoute(
        adapterID: LLMAdapterID,
        providerID: LLMProviderID,
        modelID: String?,
        configuration: LLMProviderConfiguration
    ) throws -> LLMResolvedProviderRoute {
        guard let integration = integrations[providerID] else {
            if providerID == .appleIntelligence {
                throw LLMProviderError.localModelUnavailable(
                    "Apple Intelligence requires macOS 26.0 or iOS 26.0 or newer."
                )
            }
            throw LLMProviderError.invalidConfiguration(
                "No provider integration is registered for \(providerID.rawValue)."
            )
        }
        return try integration.resolveRoute(
            adapterID: adapterID,
            modelID: modelID,
            configuration: configuration
        )
    }

    func fetchModelMetadata(
        adapterID: LLMAdapterID,
        providerID: LLMProviderID,
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata] {
        guard let integration = integrations[providerID] else {
            throw LLMProviderError.localModelUnavailable(
                "\(profile(for: providerID).name) is unavailable on this platform."
            )
        }
        return try await integration.fetchModelMetadata(
            adapterID: adapterID,
            configuration: configuration
        )
    }

    func localStatusText(for providerID: LLMProviderID) -> String? {
        guard profile(for: providerID).transportKind != .remoteHTTP else { return nil }
        if let integration = integrations[providerID] {
            return integration.localStatusText()
        }
        return "Foundation Models requires macOS 26.0 or iOS 26.0 or newer."
    }

    static func providerID(fromProviderName providerName: String) -> LLMProviderID {
        let probe = providerName.lowercased()
        if probe.contains("opencode") || probe.contains("open code zen") { return .openCodeZen }
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
        if probe.contains("custom") { return .custom }
        if probe.contains("openai") { return .openAIPlatform }
        return .custom
    }

    private static func makeProfiles() -> [LLMProviderID: LLMProviderProfile] {
        let remoteAdapters: [LLMAdapterID] = [
            .openAIResponses,
            .openAIChatCompletions,
            .openAIChatCompletionsLegacy,
            .openRouterChatCompletions,
            .anthropicMessages
        ]
        let allProfiles = [
            profile(
                id: .openAIPlatform,
                name: "OpenAI",
                defaultAdapterID: .openAIResponses,
                routes: [
                    remoteRoute(.openAIResponses, AppDefaults.OpenAi.baseURL, .bearerToken),
                    remoteRoute(.openAIChatCompletions, AppDefaults.OpenAi.baseURL, .bearerToken)
                ]
            ),
            profile(
                id: .openAICodexChatGPTSubscription,
                name: "Codex ChatGPT Subscription",
                defaultAdapterID: .openAIResponses,
                routes: [
                    remoteRoute(
                        .openAIResponses,
                        "https://chatgpt.com/backend-api/codex",
                        .codexChatGPTOAuth,
                        allowedAuthKinds: [.codexChatGPTOAuth, .codexChatGPTDeviceCode]
                    )
                ]
            ),
            profile(
                id: .openCodeZen,
                name: "OpenCode Zen",
                defaultAdapterID: .openAIChatCompletionsLegacy,
                routes: [
                    remoteRoute(.openAIResponses, "https://opencode.ai/zen/v1", .bearerToken),
                    remoteRoute(.anthropicMessages, "https://opencode.ai/zen/v1", .xAPIKey),
                    remoteRoute(.openAIChatCompletionsLegacy, "https://opencode.ai/zen/v1", .bearerToken)
                ]
            ),
            profile(
                id: .appleIntelligence,
                name: "Apple Intelligence",
                defaultAdapterID: .foundationModels,
                routes: [
                    LLMProviderRouteProfile(
                        adapterID: .foundationModels,
                        transportKind: .localSystem,
                        defaultBaseURL: "",
                        defaultAuthKind: .none,
                        allowedAuthKinds: [.none],
                        isEnabled: true
                    )
                ]
            ),
            profile(
                id: .anthropic,
                name: "Anthropic",
                defaultAdapterID: .anthropicMessages,
                routes: [
                    remoteRoute(.anthropicMessages, AppDefaults.Anthropic.baseURL, .xAPIKey)
                ]
            ),
            profile(
                id: .openRouter,
                name: "OpenRouter",
                defaultAdapterID: .openRouterChatCompletions,
                routes: [
                    remoteRoute(.openRouterChatCompletions, "https://openrouter.ai/api/v1", .bearerToken)
                ]
            ),
            profile(
                id: .lmStudio,
                name: "LM Studio",
                defaultAdapterID: .openAIChatCompletionsLegacy,
                routes: [
                    remoteRoute(.openAIChatCompletionsLegacy, "http://localhost:1234/v1", .none)
                ]
            ),
            profile(
                id: .ollama,
                name: "Ollama",
                defaultAdapterID: .openAIChatCompletionsLegacy,
                routes: [
                    remoteRoute(.openAIChatCompletionsLegacy, "http://localhost:11434/v1", .none)
                ]
            ),
            profile(
                id: .xAI,
                name: "xAI",
                defaultAdapterID: .openAIChatCompletionsLegacy,
                routes: [
                    remoteRoute(.openAIChatCompletionsLegacy, AppDefaults.XAI.baseURL, .bearerToken)
                ]
            ),
            profile(
                id: .deepSeek,
                name: "DeepSeek",
                defaultAdapterID: .openAIChatCompletionsLegacy,
                routes: [
                    remoteRoute(.openAIChatCompletionsLegacy, AppDefaults.DeepSeek.baseURL, .bearerToken)
                ]
            ),
            profile(
                id: .custom,
                name: "Custom",
                defaultAdapterID: .openAIChatCompletionsLegacy,
                routes: remoteAdapters.map {
                    remoteRoute(
                        $0,
                        AppDefaults.OpenAi.baseURL,
                        .bearerToken,
                        allowedAuthKinds: [.none, .bearerToken, .xAPIKey, .customHeaders]
                    )
                }
            )
        ]
        return Dictionary(uniqueKeysWithValues: allProfiles.map { ($0.id, $0) })
    }

    private static func profile(
        id: LLMProviderID,
        name: String,
        defaultAdapterID: LLMAdapterID,
        routes: [LLMProviderRouteProfile]
    ) -> LLMProviderProfile {
        LLMProviderProfile(
            id: id,
            name: name,
            defaultAdapterID: defaultAdapterID,
            routes: routes,
            isEnabled: true
        )
    }

    private static func remoteRoute(
        _ adapterID: LLMAdapterID,
        _ baseURL: String,
        _ defaultAuthKind: LLMAuthKind,
        allowedAuthKinds: [LLMAuthKind]? = nil
    ) -> LLMProviderRouteProfile {
        LLMProviderRouteProfile(
            adapterID: adapterID,
            transportKind: .remoteHTTP,
            defaultBaseURL: baseURL,
            defaultAuthKind: defaultAuthKind,
            allowedAuthKinds: allowedAuthKinds ?? [defaultAuthKind],
            isEnabled: true
        )
    }

    private static func catalogs(
        for profile: LLMProviderProfile
    ) -> [LLMAdapterID: any LLMModelCatalog] {
        switch profile.id {
        case .openAICodexChatGPTSubscription:
            return [.openAIResponses: StaticModelCatalog(metadata: CodexChatGPTModels.metadata())]
        case .anthropic:
            return [.anthropicMessages: AnthropicModelCatalog(profile: profile)]
        case .openRouter:
            return [.openRouterChatCompletions: OpenRouterModelCatalog(profile: profile)]
        case .custom:
            return [
                .openAIResponses: OpenAIModelCatalog(profile: profile),
                .openAIChatCompletions: OpenAIModelCatalog(profile: profile),
                .openAIChatCompletionsLegacy: OpenAIModelCatalog(profile: profile),
                .openRouterChatCompletions: OpenRouterModelCatalog(profile: profile),
                .anthropicMessages: AnthropicModelCatalog(profile: profile)
            ]
        case .appleIntelligence, .openCodeZen:
            return [:]
        default:
            return Dictionary(
                uniqueKeysWithValues: profile.supportedAdapterIDs.map {
                    ($0, OpenAIModelCatalog(profile: profile) as any LLMModelCatalog)
                }
            )
        }
    }
}
