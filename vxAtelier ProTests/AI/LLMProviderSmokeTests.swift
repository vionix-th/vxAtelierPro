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

    func testConfiguredProvidersLiveSmoke() async throws {
        let suite = try loadSuite()
        guard suite.enabled ?? true else {
            throw XCTSkip("Live LLM smoke tests are disabled in the local provider config.")
        }

        for provider in suite.providers where provider.enabled ?? true {
            for adapterID in provider.adapterIDs {
                try await runLiveSmoke(suite: suite, provider: provider, adapterID: adapterID)
            }
        }
    }

    func testOpenAIChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .openAIPlatform, adapterID: .openAIChatCompletions)
    }

    func testOpenAIResponsesLiveFetchModelsCompletesDefaults() async throws {
        try await runLiveModelFetch(providerID: .openAIPlatform, adapterID: .openAIResponses)
    }

    func testCodexChatGPTSubscriptionResponsesLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .openAICodexChatGPTSubscription, adapterID: .openAIResponses)
    }

    func testCodexChatGPTSubscriptionStaticModelFetchCompletesDefaults() async throws {
        try await runLiveModelFetch(providerID: .openAICodexChatGPTSubscription, adapterID: .openAIResponses)
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
        try await runLiveSmoke(suite: suite, provider: provider, adapterID: adapterID)
    }

    private func runLiveSmoke(
        suite: LiveSmokeSuite,
        provider: LiveSmokeProvider,
        adapterID: LLMAdapterID
    ) async throws {
        let providerID = provider.id
        let adapter = LLMProviderRegistry.shared.adapter(for: adapterID, providerID: providerID)
        let models = try provider.resolvedModels()
        let configuration = try await makeConfiguration(for: provider, suite: suite, adapterID: adapterID)

        if provider.checkModels ?? true {
            _ = try await runProviderOperation(provider: provider, adapterID: adapterID, operation: "models") {
                _ = try await adapter.fetchModels(configuration: configuration)
                return true
            }
        }

        for model in models {
            let scenarios = liveSmokeScenarios(providerID: providerID, adapterID: adapterID, model: model)
            for scenario in scenarios {
                let activity = activityName(provider: provider, adapterID: adapterID, model: model, scenario: scenario)
                recordActivity(named: activity)
                let passed = try await runProviderOperation(provider: provider, adapterID: adapterID, model: model, operation: scenario.name) {
                    let events = try await collectEvents(
                        adapter.stream(
                            makeRequest(providerID: providerID, adapterID: adapterID, model: model, scenario: scenario),
                            configuration: configuration
                        )
                    )
                    return assertTurn(events, provider: provider, adapterID: adapterID, model: model, scenario: scenario)
                }
                if passed {
                    recordActivity(named: "\(activity) passed")
                }
            }
        }
    }

    private func runLiveModelFetch(providerID: LLMProviderID, adapterID: LLMAdapterID) async throws {
        let (suite, provider) = try loadEnabledProvider(providerID: providerID, adapterID: adapterID)
        let adapter = LLMProviderRegistry.shared.adapter(for: adapterID, providerID: providerID)
        let configuration = try await makeConfiguration(for: provider, suite: suite, adapterID: adapterID)
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
    ) async throws -> LLMProviderConfiguration {
        let item = makeAPIConfigurationItem(for: provider, suite: suite, adapterID: adapterID)
        return try await CodexChatGPTOAuthService.resolvedProviderConfiguration(for: item)
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
        if let credentialJSON = provider.credentialJSON {
            configuration.credentialJSON = credentialJSON
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
        case .codexChatGPTOAuth, .codexChatGPTDeviceCode:
            guard case .secret(let secret) = configuration.credential,
                  !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                XCTFail("\(provider.name ?? provider.id.rawValue) is enabled but credentialJSON did not produce a Codex ChatGPT access token.")
                return
            }
        case .none, .customHeaders:
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
        if provider.id == .openAICodexChatGPTSubscription {
            XCTAssertNil(descriptor.rawMetadataJSON)
        } else {
            XCTAssertNotNil(descriptor.rawMetadataJSON)
        }
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
        scenario: LiveSmokeScenario
    ) -> String {
        "\(provider.name ?? provider.id.rawValue) / \(adapterID.rawValue) / \(model) / \(scenario.name) / \(scenario.streamMode.rawValue)"
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
        scenario: LiveSmokeScenario
    ) -> LLMRequest {
        var request = LLMRequest.runtimeEquivalent(
            providerID: providerID,
            adapterID: adapterID,
            modelID: model,
            messages: scenario.messages,
            tools: scenario.tools,
            options: LLMGenerationOptions(
                systemPrompt: "You are a concise live smoke test assistant.",
                maxOutputTokens: scenario.maxOutputTokens,
                streamMode: scenario.streamMode
            )
        )
        let availability = LLMParameterAvailabilityMappingResolver.resolve(
            adapterID: adapterID,
            availability: request.parameterAvailability
        )
        request.options = LLMParameterAvailabilityResolver.resolvedOptions(
            from: request.options,
            conversationPreferences: [:],
            modelAvailability: availability
        )
        return request
    }

    private func assertTurn(
        _ events: [LLMStreamEvent],
        provider: LiveSmokeProvider,
        adapterID: LLMAdapterID,
        model: String,
        scenario: LiveSmokeScenario
    ) -> Bool {
        switch scenario.assertion {
        case .text:
            return assertCompletedTextTurn(
                events,
                provider: provider,
                adapterID: adapterID,
                model: model,
                scenario: scenario
            )
        case .toolCall(let expectedName):
            return assertCompletedToolCallTurn(
                events,
                expectedName: expectedName,
                provider: provider,
                adapterID: adapterID,
                model: model,
                scenario: scenario
            )
        }
    }

    private func assertCompletedTextTurn(
        _ events: [LLMStreamEvent],
        provider: LiveSmokeProvider,
        adapterID: LLMAdapterID,
        model: String,
        scenario: LiveSmokeScenario
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
            XCTFail("\(provider.name ?? provider.id.rawValue) \(adapterID.rawValue) \(model) \(scenario.name) produced no text.")
            passed = false
        }
        if !completed {
            XCTFail("\(provider.name ?? provider.id.rawValue) \(adapterID.rawValue) \(model) \(scenario.name) did not complete.")
            passed = false
        }
        return passed
    }

    private func assertCompletedToolCallTurn(
        _ events: [LLMStreamEvent],
        expectedName: String,
        provider: LiveSmokeProvider,
        adapterID: LLMAdapterID,
        model: String,
        scenario: LiveSmokeScenario
    ) -> Bool {
        let completedCalls = events.compactMap { event -> LLMToolCall? in
            if case .toolCallCompleted(let call) = event { return call }
            return nil
        }
        let deltaCalls = events.compactMap { event -> LLMToolCall? in
            if case .toolCallDelta(let call) = event { return call }
            return nil
        }
        let completed = events.contains { event in
            if case .runCompleted = event { return true }
            return false
        }

        var passed = true
        if !completedCalls.contains(where: { $0.name == expectedName }) &&
            !deltaCalls.contains(where: { $0.name == expectedName }) {
            XCTFail("\(provider.name ?? provider.id.rawValue) \(adapterID.rawValue) \(model) \(scenario.name) produced no \(expectedName) tool call.")
            passed = false
        }
        if !completed {
            XCTFail("\(provider.name ?? provider.id.rawValue) \(adapterID.rawValue) \(model) \(scenario.name) did not complete.")
            passed = false
        }
        return passed
    }

    private func liveSmokeScenarios(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        model: String
    ) -> [LiveSmokeScenario] {
        let request = LLMRequest.runtimeEquivalent(
            providerID: providerID,
            adapterID: adapterID,
            modelID: model,
            messages: [],
            options: LLMGenerationOptions()
        )
        let capabilities = Set(request.modelCapabilities)
        let streamPolicy = resolvedStreamPolicy(request: request, adapterID: adapterID)
        let maxOutputTokens = capabilities.contains(.reasoning) ? 128 : 32

        var scenarios: [LiveSmokeScenario] = []
        if streamPolicy.allowsBlockMode {
            scenarios.append(.text(name: "block text", streamMode: .disabled, maxOutputTokens: maxOutputTokens))
        } else if let reason = streamPolicy.blockSkipReason {
            recordActivity(named: "\(providerID.rawValue) / \(adapterID.rawValue) / \(model) / block text skipped: \(reason)")
        }

        if capabilities.contains(.streaming), streamPolicy.allowsStreaming {
            scenarios.append(.text(name: "stream text", streamMode: .enabled, maxOutputTokens: maxOutputTokens))
        } else {
            let reason = capabilities.contains(.streaming) ? (streamPolicy.streamingSkipReason ?? "stream disabled by metadata") : "model lacks streaming capability"
            recordActivity(named: "\(providerID.rawValue) / \(adapterID.rawValue) / \(model) / stream text skipped: \(reason)")
        }

        if capabilities.contains(.tools), adapterSupportsTools(adapterID) {
            let streamMode = streamPolicy.toolCallStreamMode(modelSupportsStreaming: capabilities.contains(.streaming))
            scenarios.append(.toolCall(streamMode: streamMode, maxOutputTokens: maxOutputTokens))
        } else {
            let reason = capabilities.contains(.tools) ? "adapter does not expose tool schema" : "model lacks tools capability"
            recordActivity(named: "\(providerID.rawValue) / \(adapterID.rawValue) / \(model) / tool call skipped: \(reason)")
        }

        return scenarios
    }

    private func resolvedStreamPolicy(request: LLMRequest, adapterID: LLMAdapterID) -> LiveSmokeStreamPolicy {
        let availability = LLMParameterAvailabilityMappingResolver.resolve(
            adapterID: adapterID,
            availability: request.parameterAvailability
        )
        guard let streamAvailability = availability[.stream] else {
            return LiveSmokeStreamPolicy(allowsBlockMode: true, allowsStreaming: true)
        }
        guard streamAvailability.isAvailable else {
            return LiveSmokeStreamPolicy(
                allowsBlockMode: true,
                allowsStreaming: false,
                streamingSkipReason: "stream parameter is unavailable"
            )
        }

        let defaultStreamValue = streamAvailability.defaultValue?.boolValue
        if streamAvailability.isRequired {
            if defaultStreamValue ?? streamAvailability.isEnabled {
                return LiveSmokeStreamPolicy(
                    allowsBlockMode: false,
                    allowsStreaming: true,
                    blockSkipReason: "stream parameter is required enabled"
                )
            }
            return LiveSmokeStreamPolicy(
                allowsBlockMode: true,
                allowsStreaming: false,
                streamingSkipReason: "stream parameter is required disabled"
            )
        }

        return LiveSmokeStreamPolicy(allowsBlockMode: true, allowsStreaming: true)
    }

    private func adapterSupportsTools(_ adapterID: LLMAdapterID) -> Bool {
        switch adapterID {
        case .openAIResponses, .openAIChatCompletions, .openAICompatibleChatCompletions, .anthropicMessages:
            return true
        }
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
    var credentialJSON: String?
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

private struct LiveSmokeScenario {
    var name: String
    var streamMode: LLMGenerationOptions.StreamMode
    var maxOutputTokens: Int
    var messages: [LLMMessage]
    var tools: [LLMToolDefinition]
    var assertion: LiveSmokeAssertion

    static func text(
        name: String,
        streamMode: LLMGenerationOptions.StreamMode,
        maxOutputTokens: Int
    ) -> Self {
        LiveSmokeScenario(
            name: name,
            streamMode: streamMode,
            maxOutputTokens: maxOutputTokens,
            messages: [
                LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Reply with only: ok")])
            ],
            tools: [],
            assertion: .text
        )
    }

    static func toolCall(
        streamMode: LLMGenerationOptions.StreamMode,
        maxOutputTokens: Int
    ) -> Self {
        let toolName = "live_smoke_echo"
        return LiveSmokeScenario(
            name: "tool call",
            streamMode: streamMode,
            maxOutputTokens: maxOutputTokens,
            messages: [
                LLMMessage(
                    role: "user",
                    content: [
                        LLMContentPart(kind: .text, text: "Call the live_smoke_echo tool once with value \"ok\". Do not answer in prose.")
                    ]
                )
            ],
            tools: [
                LLMToolDefinition(
                    name: toolName,
                    description: "Echoes a smoke-test value.",
                    parameters: .object([
                        "type": .string("object"),
                        "additionalProperties": .boolean(false),
                        "required": .array([.string("value")]),
                        "properties": .object([
                            "value": .object([
                                "type": .string("string"),
                                "description": .string("The smoke-test value to echo.")
                            ])
                        ])
                    ])
                )
            ],
            assertion: .toolCall(expectedName: toolName)
        )
    }
}

private enum LiveSmokeAssertion {
    case text
    case toolCall(expectedName: String)
}

private struct LiveSmokeStreamPolicy {
    var allowsBlockMode: Bool
    var allowsStreaming: Bool
    var blockSkipReason: String?
    var streamingSkipReason: String?

    func toolCallStreamMode(modelSupportsStreaming: Bool) -> LLMGenerationOptions.StreamMode {
        if allowsBlockMode {
            return .disabled
        }
        if modelSupportsStreaming, allowsStreaming {
            return .enabled
        }
        return .disabled
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
