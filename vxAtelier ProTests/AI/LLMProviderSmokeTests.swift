import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMProviderLiveSmokeTests: XCTestCase {
    private static let localConfigFileNames = ["LiveLLMProviders.local.json", "LiveLLMProviders.json"]
    private static let templateConfigFileName = "LiveLLMProviders.template.json"

    func testOpenAIResponsesLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .openAIPlatform, adapterID: .openAIResponses)
    }

    func testOpenAIChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .openAIPlatform, adapterID: .openAIChatCompletions)
    }

    func testOpenAIResponsesLiveFetchModelsCompletesDefaults() async throws {
        try await runLiveModelFetch(providerID: .openAIPlatform, adapterID: .openAIResponses)
    }

    func testOpenAIQueryManagerLiveFetchModelsPersistsCompletedDefaults() async throws {
        let (suite, provider) = try loadEnabledProvider(providerID: .openAIPlatform, adapterID: .openAIResponses)
        let config = makeAPIConfigurationItem(for: provider, suite: suite, adapterID: .openAIResponses)
        let configuration = config.makeLLMProviderConfiguration()
        recordConfigurationActivity(provider: provider, adapterID: .openAIResponses, configuration: configuration)
        assertRequiredCredentialPresent(provider: provider, configuration: configuration)

        let testEnv = TestEnvironment()
        let queryManager = testEnv.createQueryManager()
        try queryManager.insert(config)

        let summary = await queryManager.fetchModelsFromProviders()
        XCTContext.runActivity(named: "QueryManager live fetch summary") { activity in
            activity.add(XCTAttachment(string: "added=\(summary.added), updated=\(summary.updated), failures=\(summary.failures.map(\.message).joined(separator: "\n"))"))
        }

        XCTAssertTrue(summary.failures.isEmpty, summary.failures.map(\.message).joined(separator: "\n"))
        XCTAssertGreaterThan(summary.added + summary.updated, 0)

        let persistedModels = queryManager.models(for: config)
        XCTAssertFalse(persistedModels.isEmpty)
        try assertFetchedModelsCompleteDefaults(
            persistedModels.map(\.descriptor),
            provider: provider,
            adapterID: .openAIResponses
        )

        let primaryModel = try XCTUnwrap(persistedModels.first { $0.modelID == provider.primaryModel })
        XCTContext.runActivity(named: "QueryManager materialized parameter mappings") { activity in
            let mappings = primaryModel.parameterMappings
                .sorted { $0.semanticParameterID < $1.semanticParameterID }
                .map { "\($0.adapterIDRaw):\($0.semanticParameterID) wireKey=\($0.wireKey)" }
                .joined(separator: "\n")
            activity.add(XCTAttachment(string: mappings))
        }
        XCTAssertFalse(primaryModel.parameterMappings.isEmpty)
    }

    func testAnthropicMessagesLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .anthropic, adapterID: .anthropicMessages)
    }

    func testOpenRouterChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .openRouter, adapterID: .openAICompatibleChatCompletions)
    }

    func testLMStudioChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .lmStudio, adapterID: .openAICompatibleChatCompletions)
    }

    func testOllamaChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .ollama, adapterID: .openAICompatibleChatCompletions)
    }

    func testXAIChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .xAI, adapterID: .openAICompatibleChatCompletions)
    }

    func testDeepSeekChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .deepSeek, adapterID: .openAICompatibleChatCompletions)
    }

    func testCustomOpenAICompatibleChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .customOpenAICompatible, adapterID: .openAICompatibleChatCompletions)
    }

    private func runLiveSmoke(providerID: LLMProviderID, adapterID: LLMAdapterID) async throws {
        let (suite, provider) = try loadEnabledProvider(providerID: providerID, adapterID: adapterID)

        let adapter = LLMProviderRegistry.shared.adapter(for: adapterID, providerID: providerID)
        let models = try provider.resolvedModels()
        let configuration = makeConfiguration(for: provider, suite: suite, adapterID: adapterID)

        if provider.checkModels ?? true {
            _ = try await runProviderOperation(provider: provider, adapterID: adapterID, operation: "models") {
                _ = try await adapter.fetchModels(configuration: configuration)
                return true
            }
        }

        for model in models {
            let nonStreamingActivity = activityName(provider: provider, adapterID: adapterID, model: model, streamMode: .disabled)
            recordActivity(named: nonStreamingActivity)
            let nonStreamingPassed = try await runProviderOperation(provider: provider, adapterID: adapterID, model: model, operation: "non-streaming turn") {
                let events = try await collectEvents(
                    adapter.stream(
                        makeRequest(providerID: providerID, adapterID: adapterID, model: model, streamMode: .disabled),
                        configuration: configuration
                    )
                )
                return assertCompletedTextTurn(events, provider: provider, adapterID: adapterID, model: model, streamMode: .disabled)
            }
            if nonStreamingPassed {
                recordActivity(named: "\(nonStreamingActivity) passed")
            }

            let streamingActivity = activityName(provider: provider, adapterID: adapterID, model: model, streamMode: .enabled)
            recordActivity(named: streamingActivity)
            let streamingPassed = try await runProviderOperation(provider: provider, adapterID: adapterID, model: model, operation: "streaming turn") {
                let events = try await collectEvents(
                    adapter.stream(
                        makeRequest(providerID: providerID, adapterID: adapterID, model: model, streamMode: .enabled),
                        configuration: configuration
                    )
                )
                return assertCompletedTextTurn(events, provider: provider, adapterID: adapterID, model: model, streamMode: .enabled)
            }
            if streamingPassed {
                recordActivity(named: "\(streamingActivity) passed")
            }
        }
    }

    private func runLiveModelFetch(providerID: LLMProviderID, adapterID: LLMAdapterID) async throws {
        let (suite, provider) = try loadEnabledProvider(providerID: providerID, adapterID: adapterID)
        let adapter = LLMProviderRegistry.shared.adapter(for: adapterID, providerID: providerID)
        let configuration = makeConfiguration(for: provider, suite: suite, adapterID: adapterID)
        recordConfigurationActivity(provider: provider, adapterID: adapterID, configuration: configuration)
        assertRequiredCredentialPresent(provider: provider, configuration: configuration)

        let fetchedModels = try await runProviderModelFetch(
            provider: provider,
            adapterID: adapterID,
            adapter: adapter,
            configuration: configuration
        )
        try assertFetchedModelsCompleteDefaults(fetchedModels, provider: provider, adapterID: adapterID)
    }

    private func runProviderModelFetch(
        provider: LiveSmokeProvider,
        adapterID: LLMAdapterID,
        adapter: LLMProviderAdapter,
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMModelDescriptor] {
        var fetchedModels: [LLMModelDescriptor] = []
        _ = try await runProviderOperation(provider: provider, adapterID: adapterID, operation: "live model fetch") {
            fetchedModels = try await adapter.fetchModels(configuration: configuration)
            return true
        }
        XCTContext.runActivity(named: "Adapter live /models response") { activity in
            let ids = fetchedModels.map(\.id).prefix(80).joined(separator: "\n")
            activity.add(XCTAttachment(string: "count=\(fetchedModels.count)\n\(ids)"))
        }
        return fetchedModels
    }

    private func makeConfiguration(
        for provider: LiveSmokeProvider,
        suite: LiveSmokeSuite,
        adapterID: LLMAdapterID
    ) -> LLMProviderConfiguration {
        makeAPIConfigurationItem(for: provider, suite: suite, adapterID: adapterID)
            .makeLLMProviderConfiguration()
    }

    private func makeAPIConfigurationItem(
        for provider: LiveSmokeProvider,
        suite: LiveSmokeSuite,
        adapterID: LLMAdapterID
    ) -> APIConfigurationItem {
        let profile = LLMProviderRegistry.shared.profile(for: provider.id)
        let configuration = APIConfigurationItem(
            name: provider.name ?? "\(profile.name) Live Smoke",
            apiKey: provider.apiKey ?? "",
            baseURL: provider.baseURL ?? profile.defaultBaseURL,
            defaultModel: provider.primaryModel,
            providerID: provider.id
        )
        if let authKind = provider.authKind {
            configuration.authKindEnum = authKind
        }
        configuration.defaultAdapterIDEnum = adapterID
        configuration.decodedHeaders = provider.headers ?? [:]
        configuration.decodedOptions = mergedOptions(provider: provider, suite: suite)
        return configuration
    }

    private func mergedOptions(provider: LiveSmokeProvider, suite: LiveSmokeSuite) -> [String: String] {
        var options: [String: String] = [:]
        if let timeout = suite.defaultRequestTimeoutSeconds {
            options["request_timeout_seconds"] = String(timeout)
        }
        if let idleTimeout = suite.defaultStreamIdleTimeoutSeconds {
            options["sse_idle_timeout_seconds"] = String(idleTimeout)
        }
        for (key, value) in provider.options ?? [:] {
            options[key] = value
        }
        return options
    }

    private func assertRequiredCredentialPresent(
        provider: LiveSmokeProvider,
        configuration: LLMProviderConfiguration
    ) {
        let authKind = configuration.authKind ?? LLMProviderRegistry.shared.profile(for: provider.id).authKind
        switch authKind {
        case .bearerToken, .xAPIKey:
            guard case .secret(let secret) = configuration.credential,
                  !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                XCTFail("\(provider.name ?? provider.id.rawValue) is enabled but APIConfiguration did not produce a secret credential.")
                return
            }
        case .none, .customHeaders, .codexChatGPTOAuth, .codexChatGPTDeviceCode:
            return
        }
    }

    private func recordConfigurationActivity(
        provider: LiveSmokeProvider,
        adapterID: LLMAdapterID,
        configuration: LLMProviderConfiguration
    ) {
        XCTContext.runActivity(named: "Live APIConfiguration conversion") { activity in
            let authKind = configuration.authKind ?? LLMProviderRegistry.shared.profile(for: provider.id).authKind
            let credentialState: String
            if case .secret = configuration.credential {
                credentialState = "present"
            } else {
                credentialState = "missing"
            }
            activity.add(XCTAttachment(string: [
                "providerID=\(provider.id.rawValue)",
                "adapterID=\(adapterID.rawValue)",
                "baseURL=\(configuration.baseURL)",
                "authKind=\(authKind.rawValue)",
                "credential=\(credentialState)",
                "configuredModels=\((try? provider.resolvedModels().joined(separator: ",")) ?? "")"
            ].joined(separator: "\n")))
        }
    }

    private func assertFetchedModelsCompleteDefaults(
        _ fetchedModels: [LLMModelDescriptor],
        provider: LiveSmokeProvider,
        adapterID: LLMAdapterID
    ) throws {
        XCTAssertFalse(fetchedModels.isEmpty)
        let fetchedIDs = Set(fetchedModels.map(\.id))
        for modelID in try provider.resolvedModels() {
            XCTAssertTrue(fetchedIDs.contains(modelID), "Live /models response missing configured model \(modelID).")
        }

        let primaryModelID = try XCTUnwrap(provider.primaryModel)
        let descriptor = try XCTUnwrap(
            fetchedModels.first { $0.id == primaryModelID },
            "Live /models response missing primary model \(primaryModelID)."
        )
        let defaults = try XCTUnwrap(
            LLMDefaultsCatalog.bundled.modelDefaults(providerID: provider.id, modelID: primaryModelID),
            "LLMDefaults.json has no rule for \(provider.id.rawValue) \(primaryModelID)."
        )

        XCTContext.runActivity(named: "LLMDefaults completion for live model") { activity in
            activity.add(XCTAttachment(string: [
                "modelID=\(descriptor.id)",
                "context=\(descriptor.contextWindow.map(String.init) ?? "nil")",
                "capabilities=\(descriptor.capabilities.map(\.rawValue).joined(separator: ","))",
                "rawMetadata=\(descriptor.rawMetadataJSON == nil ? "missing" : "present")"
            ].joined(separator: "\n")))
        }

        if let contextWindow = defaults.contextWindow {
            XCTAssertEqual(descriptor.contextWindow, contextWindow)
        }
        if let capabilities = defaults.capabilities {
            XCTAssertEqual(Set(descriptor.capabilities), Set(capabilities))
        }
        XCTAssertNotNil(descriptor.rawMetadataJSON)
    }

    private func loadEnabledProvider(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID
    ) throws -> (LiveSmokeSuite, LiveSmokeProvider) {
        let suite = try loadSuite()
        guard suite.enabled ?? true else {
            throw XCTSkip("Live LLM smoke tests are disabled in the local provider config.")
        }

        let candidates = suite.providers.filter { provider in
            provider.id == providerID && provider.adapterIDs.contains(adapterID)
        }
        guard !candidates.isEmpty else {
            throw XCTSkip("No \(providerID.rawValue) \(adapterID.rawValue) entry in the local provider config.")
        }
        guard let provider = candidates.first(where: { $0.enabled ?? true }) else {
            throw XCTSkip("\(providerID.rawValue) \(adapterID.rawValue) is disabled in the local provider config.")
        }
        return (suite, provider)
    }

    private func activityName(
        provider: LiveSmokeProvider,
        adapterID: LLMAdapterID,
        model: String,
        streamMode: LLMGenerationOptions.StreamMode
    ) -> String {
        "\(provider.name ?? provider.id.rawValue) / \(adapterID.rawValue) / \(model) / \(streamMode.rawValue)"
    }

    private func recordActivity(named name: String) {
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(string: name)
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    private func makeRequest(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        model: String,
        streamMode: LLMGenerationOptions.StreamMode
    ) -> LLMRequest {
        LLMRequest.runtimeEquivalent(
            providerID: providerID,
            adapterID: adapterID,
            modelID: model,
            messages: [
                LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Reply with only: ok")])
            ],
            options: LLMGenerationOptions(maxOutputTokens: 16, streamMode: streamMode)
        )
    }

    private func assertCompletedTextTurn(
        _ events: [LLMStreamEvent],
        provider: LiveSmokeProvider,
        adapterID: LLMAdapterID,
        model: String,
        streamMode: LLMGenerationOptions.StreamMode
    ) -> Bool {
        let text = events.compactMap { event -> String? in
            if case .textDelta(let value) = event { return value }
            return nil
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let completed = events.contains { event in
            if case .runCompleted = event { return true }
            return false
        }

        var passed = true
        if text.isEmpty {
            XCTFail("\(provider.name ?? provider.id.rawValue) \(adapterID.rawValue) \(model) \(streamMode.rawValue) produced no text.")
            passed = false
        }
        if !completed {
            XCTFail("\(provider.name ?? provider.id.rawValue) \(adapterID.rawValue) \(model) \(streamMode.rawValue) did not complete.")
            passed = false
        }
        return passed
    }

    private func runProviderOperation(
        provider: LiveSmokeProvider,
        adapterID: LLMAdapterID,
        model: String? = nil,
        operation: String,
        _ work: () async throws -> Bool
    ) async throws -> Bool {
        do {
            return try await work()
        } catch {
            let modelSuffix = model.map { " \($0)" } ?? ""
            if let reason = unavailableReason(from: error) {
                throw XCTSkip("\(provider.name ?? provider.id.rawValue) \(adapterID.rawValue)\(modelSuffix) \(operation) unavailable: \(reason)")
            }
            XCTFail("\(provider.name ?? provider.id.rawValue) \(adapterID.rawValue)\(modelSuffix) \(operation) failed: \(error)")
            return false
        }
    }

    private func unavailableReason(from error: Error) -> String? {
        if let providerError = error as? LLMProviderError {
            switch providerError {
            case .network(let message):
                return message
            case .provider(let statusCode, let message, _):
                if [408, 429, 500, 502, 503, 504].contains(statusCode) {
                    return "Provider returned \(statusCode): \(message)"
                }
                return nil
            case .cancelled:
                return providerError.localizedDescription
            case .invalidConfiguration,
                 .invalidURL,
                 .authUnavailable,
                 .unsupportedCapability,
                 .unsupportedParameter,
                 .decoding:
                return nil
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.localizedDescription
        }
        return nil
    }

    private func collectEvents(
        _ stream: AsyncThrowingStream<LLMStreamEvent, Error>
    ) async throws -> [LLMStreamEvent] {
        var events: [LLMStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func loadSuite() throws -> LiveSmokeSuite {
        guard let url = Self.localConfigFileNames
            .map({ Self.configDirectoryURL.appendingPathComponent($0) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("Create LiveLLMProviders.json next to \(Self.templateConfigFileName) to run live LLM smoke tests.")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LiveSmokeSuite.self, from: data)
    }

    private static var configDirectoryURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    }

}

private struct LiveSmokeSuite: Decodable {
    var enabled: Bool?
    var defaultRequestTimeoutSeconds: Double?
    var defaultStreamIdleTimeoutSeconds: Double?
    var providers: [LiveSmokeProvider]
}

private struct LiveSmokeProvider: Decodable {
    var id: LLMProviderID
    var name: String?
    var enabled: Bool?
    var baseURL: String?
    var apiKey: String?
    var models: [String]
    var adapterIDs: [LLMAdapterID]
    var authKind: LLMAuthKind?
    var checkModels: Bool?
    var headers: [String: String]?
    var options: [String: String]?

    var primaryModel: String? {
        resolvedModelsOrEmpty.first
    }

    func resolvedModels() throws -> [String] {
        let models = resolvedModelsOrEmpty
        guard !models.isEmpty else {
            throw LiveSmokeConfigurationError.missingModel(id.rawValue)
        }
        return models
    }

    private var resolvedModelsOrEmpty: [String] {
        var seen = Set<String>()
        return models.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return nil }
            seen.insert(trimmed)
            return trimmed
        }
    }
}

private enum LiveSmokeConfigurationError: LocalizedError {
    case missingModel(String)

    var errorDescription: String? {
        switch self {
        case .missingModel(let providerID):
            return "Missing model for live LLM smoke provider \(providerID)."
        }
    }
}
