import Foundation

protocol LLMModelCatalog {
    func fetchModelMetadata(
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata]
}

protocol LLMProviderIntegration {
    var profile: LLMProviderProfile { get }

    func resolveRoute(
        adapterID: LLMAdapterID,
        modelID: String?,
        configuration: LLMProviderConfiguration
    ) throws -> LLMResolvedProviderRoute

    func fetchModelMetadata(
        adapterID: LLMAdapterID,
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata]

    func localStatusText() -> String?
}

extension LLMProviderIntegration {
    func localStatusText() -> String? { nil }
}

struct OpenAIModelCatalog: LLMModelCatalog {
    private static let modelsPath = "/models"

    let profile: LLMProviderProfile
    private let httpClient = LLMHTTPClient()

    func fetchModelMetadata(
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata] {
        let response: JSONValue = try await httpClient.getJSON(
            path: Self.modelsPath,
            configuration: httpClient.makeConfiguration(for: configuration),
            responseType: JSONValue.self
        )
        guard let data = response.objectValue?.array("data") else { return [] }
        return LLMModelMetadataDecoder.openAIShapedMetadata(from: data, profile: profile)
    }
}

struct AnthropicModelCatalog: LLMModelCatalog {
    private static let modelsPath = "/models"

    let profile: LLMProviderProfile
    private let httpClient = LLMHTTPClient()

    func fetchModelMetadata(
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata] {
        let response: JSONValue = try await httpClient.getJSON(
            path: Self.modelsPath,
            configuration: httpClient.makeConfiguration(for: configuration),
            responseType: JSONValue.self
        )
        guard let data = response.objectValue?.array("data") else { return [] }
        return LLMModelMetadataDecoder.anthropicMetadata(from: data, profile: profile)
    }
}

struct OpenRouterModelCatalog: LLMModelCatalog {
    private static let modelsPath = "/models"

    let profile: LLMProviderProfile
    private let httpClient = LLMHTTPClient()

    func fetchModelMetadata(
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata] {
        let response: JSONValue = try await httpClient.getJSON(
            path: Self.modelsPath,
            configuration: httpClient.makeConfiguration(for: configuration),
            responseType: JSONValue.self
        )
        guard let data = response.objectValue?.array("data") else { return [] }
        return LLMModelMetadataDecoder.openRouterMetadata(from: data, profile: profile)
    }
}

struct StaticModelCatalog: LLMModelCatalog {
    let metadata: [LLMProviderModelMetadata]

    func fetchModelMetadata(
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata] {
        metadata
    }
}

@available(macOS 26.0, iOS 26.0, *)
struct FoundationModelsCatalog: LLMModelCatalog {
    private let backend = FoundationModelsBackend()

    func fetchModelMetadata(
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata] {
        backend.modelMetadata(configuration: configuration)
    }
}

struct StandardLLMProviderIntegration: LLMProviderIntegration {
    let profile: LLMProviderProfile
    let catalogs: [LLMAdapterID: any LLMModelCatalog]

    func resolveRoute(
        adapterID: LLMAdapterID,
        modelID: String?,
        configuration: LLMProviderConfiguration
    ) throws -> LLMResolvedProviderRoute {
        try LLMProviderRouteResolver.resolve(
            profile: profile,
            adapterID: adapterID,
            configuration: configuration
        )
    }

    func fetchModelMetadata(
        adapterID: LLMAdapterID,
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata] {
        let route = try resolveRoute(
            adapterID: adapterID,
            modelID: nil,
            configuration: configuration
        )
        guard let catalog = catalogs[adapterID] else {
            throw LLMProviderError.invalidConfiguration(
                "\(profile.name) does not provide model discovery for \(adapterID.displayName)."
            )
        }
        return try await catalog.fetchModelMetadata(configuration: route.configuration)
    }
}

struct OpenCodeZenProviderIntegration: LLMProviderIntegration {
    private static let chatModelPrefixes = [
        "grok-",
        "deepseek-",
        "minimax-",
        "glm-",
        "kimi-",
        "mimo-",
        "laguna-",
        "ling-",
        "nemotron-",
        "north-"
    ]
    private static let chatModelIDs = ["big-pickle"]

    let profile: LLMProviderProfile
    private let catalog: any LLMModelCatalog

    init(profile: LLMProviderProfile) {
        self.profile = profile
        catalog = OpenAIModelCatalog(profile: profile)
    }

    func resolveRoute(
        adapterID: LLMAdapterID,
        modelID: String?,
        configuration: LLMProviderConfiguration
    ) throws -> LLMResolvedProviderRoute {
        if let modelID, !Self.supports(modelID: modelID, adapterID: adapterID) {
            throw LLMProviderError.invalidConfiguration(
                "\(modelID) is not compatible with \(adapterID.displayName) on OpenCode Zen."
            )
        }
        return try LLMProviderRouteResolver.resolve(
            profile: profile,
            adapterID: adapterID,
            configuration: configuration
        )
    }

    func fetchModelMetadata(
        adapterID: LLMAdapterID,
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata] {
        let route = try resolveRoute(
            adapterID: adapterID,
            modelID: nil,
            configuration: configuration
        )
        var listingConfiguration = route.configuration
        listingConfiguration.authKind = .bearerToken
        let metadata = try await catalog.fetchModelMetadata(configuration: listingConfiguration)
        return metadata.filter { Self.supports(modelID: $0.id, adapterID: adapterID) }
    }

    static func supports(modelID: String, adapterID: LLMAdapterID) -> Bool {
        supportedAdapterID(for: modelID) == adapterID
    }

    static func supportedAdapterID(for modelID: String) -> LLMAdapterID? {
        let normalizedID = modelID.lowercased()
        if normalizedID.hasPrefix("gpt-") {
            return .openAIResponses
        }
        if normalizedID.hasPrefix("claude-") || normalizedID.hasPrefix("qwen") {
            return .anthropicMessages
        }
        if chatModelPrefixes.contains(where: { normalizedID.hasPrefix($0) })
            || chatModelIDs.contains(normalizedID) {
            return .openAIChatCompletionsLegacy
        }
        return nil
    }

    static func authKind(for adapterID: LLMAdapterID) -> LLMAuthKind {
        adapterID == .anthropicMessages ? .xAPIKey : .bearerToken
    }
}

@available(macOS 26.0, iOS 26.0, *)
struct AppleIntelligenceProviderIntegration: LLMProviderIntegration {
    let profile: LLMProviderProfile
    private let backend = FoundationModelsBackend()
    private let catalog = FoundationModelsCatalog()

    func resolveRoute(
        adapterID: LLMAdapterID,
        modelID: String?,
        configuration: LLMProviderConfiguration
    ) throws -> LLMResolvedProviderRoute {
        try LLMProviderRouteResolver.resolve(
            profile: profile,
            adapterID: adapterID,
            configuration: configuration
        )
    }

    func fetchModelMetadata(
        adapterID: LLMAdapterID,
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata] {
        _ = try resolveRoute(
            adapterID: adapterID,
            modelID: nil,
            configuration: configuration
        )
        return try await catalog.fetchModelMetadata(configuration: configuration)
    }

    func localStatusText() -> String? {
        backend.statusText()
    }
}

enum LLMProviderRouteResolver {
    static func resolve(
        profile: LLMProviderProfile,
        adapterID: LLMAdapterID,
        configuration: LLMProviderConfiguration
    ) throws -> LLMResolvedProviderRoute {
        guard profile.isEnabled else {
            throw LLMProviderError.authUnavailable("\(profile.name) is disabled.")
        }
        guard configuration.providerID == profile.id else {
            throw LLMProviderError.invalidConfiguration(
                "Configuration provider \(configuration.providerID.rawValue) does not match \(profile.id.rawValue)."
            )
        }
        guard let route = profile.route(for: adapterID) else {
            throw LLMProviderError.invalidConfiguration(
                "\(profile.name) cannot use \(adapterID.rawValue)."
            )
        }

        var resolved = configuration
        let authKind = configuration.authKind ?? route.defaultAuthKind
        guard route.allowedAuthKinds.contains(authKind) else {
            throw LLMProviderError.invalidConfiguration(
                "\(profile.name) cannot use \(authKind.rawValue) with \(adapterID.displayName)."
            )
        }
        resolved.authKind = authKind
        resolved.baseURL = route.requiresBaseURL
            ? (configuration.baseURL.isEmpty ? route.defaultBaseURL : configuration.baseURL)
            : ""

        return LLMResolvedProviderRoute(
            providerID: profile.id,
            adapterID: adapterID,
            configuration: resolved
        )
    }
}
