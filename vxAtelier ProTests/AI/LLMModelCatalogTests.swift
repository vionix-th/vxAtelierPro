import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMModelCatalogTests: LLMTestCase {
    override func tearDown() {
        URLProtocol.unregisterClass(MockLLMURLProtocol.self)
        MockLLMURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testRemoteCatalogsRequestModelsWithResolvedAuthenticationAndDecodeMetadata() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        var requests: [URLRequest] = []
        MockLLMURLProtocol.requestHandler = { request in
            requests.append(request)
            let data: Data
            switch request.value(forHTTPHeaderField: "x-catalog") {
            case "anthropic":
                data = Data(#"{"data":[{"id":"claude-unit","display_name":"Claude Unit","context_window":200000}]}"#.utf8)
            case "openrouter":
                data = Data(#"{"data":[{"id":"openai/gpt-unit","name":"Router Unit","context_length":128000}]}"#.utf8)
            default:
                data = Data(#"{"data":[{"id":"gpt-unit","name":"GPT Unit","context_length":64000}]}"#.utf8)
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["content-type": "application/json"]
                )!,
                data
            )
        }

        let openAI = try await OpenAIModelCatalog(
            profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform)
        ).fetchModelMetadata(configuration: configuration(
            providerID: .openAIPlatform,
            authKind: .bearerToken,
            headers: ["x-catalog": "openai"]
        ))
        let anthropic = try await AnthropicModelCatalog(
            profile: LLMProviderRegistry.shared.profile(for: .anthropic)
        ).fetchModelMetadata(configuration: configuration(
            providerID: .anthropic,
            authKind: .xAPIKey,
            headers: ["x-catalog": "anthropic"]
        ))
        let openRouter = try await OpenRouterModelCatalog(
            profile: LLMProviderRegistry.shared.profile(for: .openRouter)
        ).fetchModelMetadata(configuration: configuration(
            providerID: .openRouter,
            authKind: .bearerToken,
            headers: ["x-catalog": "openrouter"]
        ))

        XCTAssertEqual(openAI.first?.id, "gpt-unit")
        XCTAssertEqual(openAI.first?.displayName, "GPT Unit")
        XCTAssertEqual(openAI.first?.contextSize, 64000)
        XCTAssertEqual(anthropic.first?.id, "claude-unit")
        XCTAssertEqual(anthropic.first?.displayName, "Claude Unit")
        XCTAssertEqual(anthropic.first?.contextSize, 200000)
        XCTAssertEqual(openRouter.first?.id, "openai/gpt-unit")
        XCTAssertEqual(openRouter.first?.displayName, "Router Unit")
        XCTAssertEqual(openRouter.first?.contextSize, 128000)
        XCTAssertEqual(requests.map(\.url?.path), ["/v1/models", "/v1/models", "/v1/models"])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-api-key"), "secret")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testCustomSelectsCatalogForEveryRemoteAdapter() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        MockLLMURLProtocol.requestHandler = { request in
            let data = Data(#"{"data":[{"id":"custom-model","display_name":"Custom Model"}]}"#.utf8)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["content-type": "application/json"]
                )!,
                data
            )
        }

        for adapterID in LLMAdapterID.allCases where adapterID.isRemote {
            let metadata = try await LLMProviderRegistry.shared.fetchModelMetadata(
                adapterID: adapterID,
                providerID: .custom,
                configuration: configuration(providerID: .custom, authKind: .none)
            )
            XCTAssertEqual(metadata.first?.id, "custom-model", adapterID.rawValue)
            XCTAssertEqual(metadata.first?.providerID, .custom, adapterID.rawValue)
        }
    }

    func testCodexCatalogReturnsStaticInventoryWithoutHTTP() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        MockLLMURLProtocol.requestHandler = { request in
            XCTFail("Codex static catalog must not issue an HTTP request: \(request)")
            throw URLError(.badServerResponse)
        }

        let metadata = try await LLMProviderRegistry.shared.fetchModelMetadata(
            adapterID: .openAIResponses,
            providerID: .openAICodexChatGPTSubscription,
            configuration: LLMProviderConfiguration(
                providerID: .openAICodexChatGPTSubscription,
                baseURL: "",
                credential: .secret("token")
            )
        )

        XCTAssertEqual(metadata.map(\.id), CodexChatGPTModels.modelIDs)
    }

    func testStandardIntegrationFetchesThroughCatalogWithoutAdapterResolution() async throws {
        let profile = LLMProviderRegistry.shared.profile(for: .openAIPlatform)
        let expected = LLMProviderModelMetadata(
            id: "catalog-only",
            providerID: .openAIPlatform
        )
        let catalog = RecordingModelCatalog(result: .success([expected]))
        let integration = StandardLLMProviderIntegration(
            profile: profile,
            catalogs: [.openAIResponses: catalog]
        )

        let metadata = try await integration.fetchModelMetadata(
            adapterID: .openAIResponses,
            configuration: LLMProviderConfiguration(
                providerID: .openAIPlatform,
                baseURL: "",
                credential: .secret("secret")
            )
        )

        XCTAssertEqual(metadata, [expected])
        XCTAssertEqual(catalog.receivedConfiguration?.baseURL, profile.defaultRoute?.defaultBaseURL)
        XCTAssertEqual(catalog.receivedConfiguration?.authKind, .bearerToken)
    }

    func testOpenCodeZenListsWithBearerAndFiltersForSelectedAdapter() async throws {
        let profile = LLMProviderRegistry.shared.profile(for: .openCodeZen)
        let catalog = RecordingModelCatalog(result: .success([
            metadata("gpt-5.6-terra"),
            metadata("claude-sonnet-4-6"),
            metadata("qwen3.6-plus"),
            metadata("deepseek-v4-flash"),
            metadata("future-model")
        ]))
        let integration = OpenCodeZenProviderIntegration(profile: profile, catalog: catalog)

        let models = try await integration.fetchModelMetadata(
            adapterID: .anthropicMessages,
            configuration: LLMProviderConfiguration(
                providerID: .openCodeZen,
                authKind: .xAPIKey,
                baseURL: "",
                credential: .secret("secret")
            )
        )

        XCTAssertEqual(models.map(\.id), ["claude-sonnet-4-6", "qwen3.6-plus"])
        XCTAssertEqual(catalog.receivedConfiguration?.authKind, .bearerToken)
        XCTAssertThrowsError(try integration.resolveRoute(
            adapterID: .anthropicMessages,
            modelID: "gpt-5.6-terra",
            configuration: LLMProviderConfiguration(
                providerID: .openCodeZen,
                baseURL: "https://opencode.ai/zen/v1"
            )
        ))
    }

    func testCatalogFailurePropagatesWithoutGenerationAdapterConstruction() async {
        let expected = LLMProviderError.network("catalog unavailable")
        let catalog = RecordingModelCatalog(result: .failure(expected))
        let profile = LLMProviderRegistry.shared.profile(for: .openAIPlatform)
        let integration = StandardLLMProviderIntegration(
            profile: profile,
            catalogs: [.openAIResponses: catalog]
        )

        await assertThrowsAsyncError(try await integration.fetchModelMetadata(
            adapterID: .openAIResponses,
            configuration: LLMProviderConfiguration(
                providerID: .openAIPlatform,
                baseURL: "https://unit.test/v1"
            )
        )) { error in
            XCTAssertEqual(error as? LLMProviderError, expected)
        }
    }

    private func configuration(
        providerID: LLMProviderID,
        authKind: LLMAuthKind,
        headers: [String: String] = [:]
    ) -> LLMProviderConfiguration {
        LLMProviderConfiguration(
            providerID: providerID,
            authKind: authKind,
            baseURL: "https://unit.test/v1",
            credential: .secret("secret"),
            customHeaders: headers
        )
    }

    private func metadata(_ id: String) -> LLMProviderModelMetadata {
        LLMProviderModelMetadata(id: id, providerID: .openCodeZen)
    }
}

private final class RecordingModelCatalog: LLMModelCatalog {
    let result: Result<[LLMProviderModelMetadata], Error>
    private(set) var receivedConfiguration: LLMProviderConfiguration?

    init(result: Result<[LLMProviderModelMetadata], Error>) {
        self.result = result
    }

    func fetchModelMetadata(
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata] {
        receivedConfiguration = configuration
        return try result.get()
    }
}
