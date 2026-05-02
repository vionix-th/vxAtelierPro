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
        try await runLiveSmoke(providerID: .openAIPlatform, endpointFamily: .responses)
    }

    func testOpenAIChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .openAIPlatform, endpointFamily: .chatCompletions)
    }

    func testAnthropicMessagesLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .anthropic, endpointFamily: .anthropicMessages)
    }

    func testOpenRouterChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .openRouter, endpointFamily: .chatCompletions)
    }

    func testLMStudioChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .lmStudio, endpointFamily: .chatCompletions)
    }

    func testOllamaChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .ollama, endpointFamily: .chatCompletions)
    }

    func testXAIChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .xAI, endpointFamily: .chatCompletions)
    }

    func testDeepSeekChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .deepSeek, endpointFamily: .chatCompletions)
    }

    func testCustomOpenAICompatibleChatCompletionsLiveSmoke() async throws {
        try await runLiveSmoke(providerID: .customOpenAICompatible, endpointFamily: .chatCompletions)
    }

    private func runLiveSmoke(providerID: LLMProviderID, endpointFamily: LLMEndpointFamily) async throws {
        let suite = try loadSuite()
        guard suite.enabled ?? true else {
            throw XCTSkip("Live LLM smoke tests are disabled in the local provider config.")
        }

        let candidates = suite.providers.filter { provider in
            provider.id == providerID && provider.endpointFamilies.contains(endpointFamily)
        }
        guard !candidates.isEmpty else {
            throw XCTSkip("No \(providerID.rawValue) \(endpointFamily.rawValue) entry in the local provider config.")
        }
        guard let provider = candidates.first(where: { $0.enabled ?? true }) else {
            throw XCTSkip("\(providerID.rawValue) \(endpointFamily.rawValue) is disabled in the local provider config.")
        }

        let adapter = LLMProviderRegistry.shared.adapter(for: providerID)
        let models = try provider.resolvedModels()
        let configuration = makeConfiguration(for: provider, suite: suite, endpointFamily: endpointFamily)

        if provider.checkModels ?? true {
            _ = try await runProviderOperation(provider: provider, endpointFamily: endpointFamily, operation: "models") {
                _ = try await adapter.fetchModels(configuration: configuration)
                return true
            }
        }

        for model in models {
            let nonStreamingActivity = activityName(provider: provider, endpointFamily: endpointFamily, model: model, streamMode: .disabled)
            recordActivity(named: nonStreamingActivity)
            let nonStreamingPassed = try await runProviderOperation(provider: provider, endpointFamily: endpointFamily, model: model, operation: "non-streaming turn") {
                let events = try await collectEvents(
                    adapter.stream(
                        makeRequest(providerID: providerID, endpointFamily: endpointFamily, model: model, streamMode: .disabled),
                        configuration: configuration
                    )
                )
                return assertCompletedTextTurn(events, provider: provider, endpointFamily: endpointFamily, model: model, streamMode: .disabled)
            }
            if nonStreamingPassed {
                recordActivity(named: "\(nonStreamingActivity) passed")
            }

            let streamingActivity = activityName(provider: provider, endpointFamily: endpointFamily, model: model, streamMode: .enabled)
            recordActivity(named: streamingActivity)
            let streamingPassed = try await runProviderOperation(provider: provider, endpointFamily: endpointFamily, model: model, operation: "streaming turn") {
                let events = try await collectEvents(
                    adapter.stream(
                        makeRequest(providerID: providerID, endpointFamily: endpointFamily, model: model, streamMode: .enabled),
                        configuration: configuration
                    )
                )
                return assertCompletedTextTurn(events, provider: provider, endpointFamily: endpointFamily, model: model, streamMode: .enabled)
            }
            if streamingPassed {
                recordActivity(named: "\(streamingActivity) passed")
            }
        }
    }

    private func makeConfiguration(
        for provider: LiveSmokeProvider,
        suite: LiveSmokeSuite,
        endpointFamily: LLMEndpointFamily
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
        configuration.defaultEndpointFamilyEnum = endpointFamily
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

    private func activityName(
        provider: LiveSmokeProvider,
        endpointFamily: LLMEndpointFamily,
        model: String,
        streamMode: LLMGenerationOptions.StreamMode
    ) -> String {
        "\(provider.name ?? provider.id.rawValue) / \(endpointFamily.rawValue) / \(model) / \(streamMode.rawValue)"
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
        endpointFamily: LLMEndpointFamily,
        model: String,
        streamMode: LLMGenerationOptions.StreamMode
    ) -> LLMRequest {
        LLMRequest(
            providerID: providerID,
            endpointFamily: endpointFamily,
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
        endpointFamily: LLMEndpointFamily,
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
            XCTFail("\(provider.name ?? provider.id.rawValue) \(endpointFamily.rawValue) \(model) \(streamMode.rawValue) produced no text.")
            passed = false
        }
        if !completed {
            XCTFail("\(provider.name ?? provider.id.rawValue) \(endpointFamily.rawValue) \(model) \(streamMode.rawValue) did not complete.")
            passed = false
        }
        return passed
    }

    private func runProviderOperation(
        provider: LiveSmokeProvider,
        endpointFamily: LLMEndpointFamily,
        model: String? = nil,
        operation: String,
        _ work: () async throws -> Bool
    ) async throws -> Bool {
        do {
            return try await work()
        } catch {
            let modelSuffix = model.map { " \($0)" } ?? ""
            if let reason = unavailableReason(from: error) {
                throw XCTSkip("\(provider.name ?? provider.id.rawValue) \(endpointFamily.rawValue)\(modelSuffix) \(operation) unavailable: \(reason)")
            }
            XCTFail("\(provider.name ?? provider.id.rawValue) \(endpointFamily.rawValue)\(modelSuffix) \(operation) failed: \(error)")
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
    var endpointFamilies: [LLMEndpointFamily]
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
