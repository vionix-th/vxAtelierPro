import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMModelProfileRefactorTests: XCTestCase {
    private let resolver = LLMModelProfileResolver(fallbackContextSize: 4096)

    func testResolutionPrecedenceAndProvenance() {
        let metadata = LLMProviderModelMetadata(
            id: "gpt-5.4-nano",
            displayName: "Provider Name",
            providerID: .openAIPlatform,
            contextSize: 32_000,
            capabilityClaims: [LLMCapabilityClaim(capability: .streaming, state: .supported)],
            parameterSupportClaims: [LLMParameterSupportClaim(
                parameterID: .maxOutputTokens,
                state: .unsupported
            )]
        )
        let profile = resolver.resolve(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: metadata.id,
            metadata: metadata,
            overrides: LLMModelOverrides(
                displayName: "Override Name",
                contextSize: 64_000,
                capabilitySupport: [.streaming: .unsupported],
                parameterOverrides: [
                    .maxOutputTokens: LLMParameterOverrides(support: .supported)
                ]
            )
        )

        XCTAssertEqual(profile.displayName, "Override Name")
        XCTAssertEqual(profile.displayNameSource, .userOverride)
        XCTAssertEqual(profile.contextSize, 64_000)
        XCTAssertEqual(profile.contextSizeSource, .userOverride)
        XCTAssertEqual(profile.capabilities[.streaming], LLMSupport(state: .unsupported, source: .userOverride))
        XCTAssertEqual(profile.capabilities[.text]?.source, .catalog)
        XCTAssertEqual(profile.parameters[.maxOutputTokens]?.support, LLMSupport(state: .supported, source: .userOverride))
    }

    func testMissingProviderClaimsDoNotEraseCatalogClaims() {
        let metadata = LLMProviderModelMetadata(
            id: "gpt-5.4-nano",
            providerID: .openAIPlatform
        )
        let profile = resolver.resolve(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: metadata.id,
            metadata: metadata
        )

        XCTAssertEqual(profile.capabilities[.tools], LLMSupport(state: .supported, source: .catalog))
        XCTAssertEqual(profile.capabilities[.streaming], LLMSupport(state: .supported, source: .catalog))
        XCTAssertEqual(profile.parameters[.temperature]?.support, LLMSupport(state: .supported, source: .catalog))
    }

    func testPositiveProviderClaimWithoutInheritedMappingRemainsUnsupported() throws {
        let catalog = try LLMDefaultsCatalog(data: Data("""
        {"providerDefaults":[],"rules":[]}
        """.utf8))
        let profile = LLMModelProfileResolver(
            defaultsCatalog: catalog,
            fallbackContextSize: 4096
        ).resolve(
            providerID: .custom,
            adapterID: .openAIChatCompletionsLegacy,
            modelID: "future-model",
            metadata: LLMProviderModelMetadata(
                id: "future-model",
                providerID: .custom,
                parameterSupportClaims: [
                    LLMParameterSupportClaim(parameterID: .reasoningEffort, state: .supported)
                ]
            )
        )

        XCTAssertNil(profile.parameters[.reasoningEffort])
    }

    func testBundledProfilesResolveSupportedParametersWithMappingsAndOptionalSystemPrompt() {
        let profiles = [
            resolver.resolve(
                providerID: .openAIPlatform,
                adapterID: .openAIResponses,
                modelID: "gpt-5.4-nano",
                metadata: nil
            ),
            resolver.resolve(
                providerID: .anthropic,
                adapterID: .anthropicMessages,
                modelID: "claude-sonnet-4-6",
                metadata: nil
            ),
            resolver.resolve(
                providerID: .openRouter,
                adapterID: .openRouterChatCompletions,
                modelID: "openai/gpt-5.4-nano",
                metadata: nil
            )
        ]

        for profile in profiles {
            XCTAssertTrue(profile.parameters.values
                .filter { $0.support.state == .supported }
                .allSatisfy { $0.mapping != nil })
            XCTAssertEqual(profile.parameters[.systemPrompt]?.support.state, .supported)
            XCTAssertFalse(profile.parameters[.systemPrompt]?.isRequired ?? true)
            XCTAssertEqual(profile.parameters[.model]?.mapping?.encodingKind, .adapter)
            XCTAssertEqual(profile.parameters[.stream]?.mapping?.encodingKind, .adapter)
        }
    }

    func testRetainedUnsupportedParameterBlocksRequestResolution() {
        let mapping = LLMParameterMapping(
            adapterID: .openAIResponses,
            parameterID: .reasoningEffort,
            encodingKind: .preset,
            structuredPreset: .openAIResponsesReasoning
        )
        let profile = LLMParameterProfile(
            parameterID: .reasoningEffort,
            support: LLMSupport(state: .unsupported, source: .userOverride),
            mapping: mapping,
            mappingSource: .catalog,
            isRequired: false,
            isEnabledByDefault: false,
            defaultValue: nil,
            options: nil
        )
        XCTAssertThrowsError(try LLMGenerationOptionsResolver.resolve(
            options: LLMGenerationOptions(reasoning: "low"),
            conversationPreferences: [LLMParameterID.reasoningEffort.rawValue: true],
            parameterProfiles: [.reasoningEffort: profile]
        )) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidConfiguration("reasoning_effort is enabled but unavailable for the selected model and API.")
            )
        }
    }

    func testImpossibleSupportedParameterFailsAsInvalidConfiguration() {
        let profile = LLMParameterProfile(
            parameterID: .reasoningEffort,
            support: LLMSupport(state: .supported, source: .userOverride),
            mapping: nil,
            mappingSource: nil,
            isRequired: false,
            isEnabledByDefault: false,
            defaultValue: nil,
            options: nil
        )

        XCTAssertThrowsError(try LLMGenerationOptionsResolver.resolve(
            options: LLMGenerationOptions(reasoning: "low"),
            conversationPreferences: [LLMParameterID.reasoningEffort.rawValue: true],
            parameterProfiles: [.reasoningEffort: profile]
        )) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidConfiguration("reasoning_effort has no valid definition for the selected model and API.")
            )
        }
    }

    func testConversationHistoryValidatorRejectsDanglingToolCall() {
        let messages = [
            LLMMessage(
                role: "assistant",
                content: [],
                toolCalls: [LLMToolCall(
                    id: "call-1",
                    callID: "call-1",
                    index: 0,
                    name: "lookup",
                    argumentsJSON: "{}"
                )]
            )
        ]

        XCTAssertThrowsError(try ConversationHistoryValidator.validate(messages)) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidConversationState("Assistant tool calls must be followed by tool results.")
            )
        }
    }

    func testAdvisoryFeaturesReachRemoteTransportWithoutCapabilityPreflight() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        var requestCount = 0
        MockLLMURLProtocol.requestHandler = { request in
            requestCount += 1
            let data = request.httpBodyStream.flatMap { stream -> Data? in
                stream.open()
                defer { stream.close() }
                var data = Data()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let count = stream.read(buffer, maxLength: 4096)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
                return data
            } ?? request.httpBody ?? Data()
            let body = try JSONDecoder().decode(JSONValue.self, from: data)
            XCTAssertEqual(body.objectValue?.bool("stream"), true)
            XCTAssertNotNil(body.objectValue?.array("tools"))
            XCTAssertNotNil(body.objectValue?.object("reasoning"))
            XCTAssertNotNil(body.objectValue?.object("text")?.object("format"))
            let input = try XCTUnwrap(body.objectValue?.array("input"))
            let content = try XCTUnwrap(input.first?.objectValue?.array("content"))
            XCTAssertTrue(content.contains { $0.objectValue?.string("type") == "input_image" })

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["content-type": "text/event-stream"]
            )!
            let data = Data("""
            data: {"type":"response.created","response":{"id":"resp_contract","model":"gpt-test"}}

            data: {"type":"response.completed","response":{"id":"resp_contract","model":"gpt-test"}}

            """.utf8)
            return (response, data)
        }

        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "gpt-test",
            activeParameters: [
                LLMActiveParameter(parameterID: .responseFormat, mapping: LLMParameterMapping(
                    adapterID: .openAIResponses,
                    parameterID: .responseFormat,
                    encodingKind: .preset,
                    structuredPreset: .openAIResponsesTextFormat
                )),
                LLMActiveParameter(parameterID: .reasoningEffort, mapping: LLMParameterMapping(
                    adapterID: .openAIResponses,
                    parameterID: .reasoningEffort,
                    encodingKind: .preset,
                    structuredPreset: .openAIResponsesReasoning
                )),
                LLMActiveParameter(parameterID: .stream, mapping: LLMParameterMapping(
                    adapterID: .openAIResponses,
                    parameterID: .stream,
                    encodingKind: .adapter
                ))
            ],
            messages: [LLMMessage(
                role: "user",
                content: [
                    LLMContentPart(kind: .text, text: "Inspect"),
                    LLMContentPart(kind: .image, mimeType: "image/png", dataBase64: "aW1n")
                ]
            )],
            tools: [LLMToolDefinition(
                name: "lookup",
                description: "Lookup",
                parameters: .object(["type": .string("object")])
            )],
            options: LLMGenerationOptions(
                responseFormat: .jsonSchema,
                reasoning: "low",
                streamMode: .enabled,
                providerSpecificOptions: [
                    "json_schema": .object([
                        "name": .string("answer"),
                        "schema": .object(["type": .string("object")])
                    ])
                ]
            )
        )
        let configuration = LLMProviderConfiguration(
            providerID: .openAIPlatform,
            baseURL: "https://unit.test/v1",
            credential: .secret("key")
        )
        let adapter = OpenAIResponsesAdapter()

        var events: [LLMGenerationEvent] = []
        for try await event in adapter.generateEvents(
            request,
            configuration: configuration,
            toolExecutor: nil
        ) {
            events.append(event)
        }

        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(events.contains(.generationCompleted(responseID: "resp_contract", modelID: "gpt-test")))
    }

    func testRefreshPreservesOverridesAndPersistsNoCatalogRows() throws {
        let environment = TestEnvironment()
        let configuration = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test",
            providerID: .openAIPlatform
        )
        let model = ModelItem(modelID: "gpt-5.4-nano", apiConfiguration: configuration)
        model.capabilityOverrides = [
            ModelCapabilityOverrideItem(capability: .streaming, support: .unsupported)
        ]
        model.parameterOverrides = [
            ModelParameterOverrideItem(
                adapterID: .openAIResponses,
                parameterID: .maxOutputTokens,
                support: .supported,
                mapping: LLMParameterMapping(
                    adapterID: .openAIResponses,
                    parameterID: .maxOutputTokens,
                    encodingKind: .key,
                    wireKey: "custom_max_tokens"
                )
            )
        ]
        environment.modelContext.insert(configuration)
        environment.modelContext.insert(model)

        let manager = QueryManager(modelContext: environment.modelContext)
        try manager.upsertModelMetadata([
            LLMProviderModelMetadata(
                id: model.modelID,
                displayName: "Fetched",
                providerID: .openAIPlatform,
                capabilityClaims: [LLMCapabilityClaim(capability: .streaming, state: .supported)]
            )
        ], for: configuration)

        XCTAssertEqual(model.capabilityOverrides.first?.support, .unsupported)
        XCTAssertEqual(model.parameterOverrides.first?.wireKey, "custom_max_tokens")
        XCTAssertEqual(model.modelProfile.capabilities[.streaming]?.source, .userOverride)
    }

    func testRemovingOverrideRestoresProviderThenCatalogResolution() {
        let metadata = LLMProviderModelMetadata(
            id: "gpt-5.4-nano",
            providerID: .openAIPlatform,
            capabilityClaims: [LLMCapabilityClaim(capability: .streaming, state: .unsupported)]
        )
        let overridden = resolver.resolve(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: metadata.id,
            metadata: metadata,
            overrides: LLMModelOverrides(capabilitySupport: [.streaming: .supported])
        )
        let reset = resolver.resolve(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: metadata.id,
            metadata: metadata
        )
        let catalogOnly = resolver.resolve(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: metadata.id,
            metadata: LLMProviderModelMetadata(
                id: metadata.id,
                providerID: metadata.providerID
            )
        )

        XCTAssertEqual(overridden.capabilities[.streaming]?.source, .userOverride)
        XCTAssertEqual(reset.capabilities[.streaming], LLMSupport(state: .unsupported, source: .provider))
        XCTAssertEqual(catalogOnly.capabilities[.streaming], LLMSupport(state: .supported, source: .catalog))
    }

    func testExportImportRoundTripsMetadataAndOverrides() {
        let configuration = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test",
            providerID: .openAIPlatform
        )
        let model = ModelItem(modelID: "gpt-test", apiConfiguration: configuration)
        model.providerContextSize = 12_000
        model.providerSupportedCapabilitiesRaw = [LLMModelCapability.tools.rawValue]
        model.providerUnsupportedParametersRaw = [LLMParameterID.temperature.rawValue]
        model.contextSizeOverride = 24_000
        model.capabilityOverrides = [
            ModelCapabilityOverrideItem(capability: .streaming, support: .supported)
        ]
        model.parameterOverrides = [
            ModelParameterOverrideItem(
                adapterID: .openAIResponses,
                parameterID: .maxOutputTokens,
                support: .supported,
                mapping: LLMParameterMapping(
                    adapterID: .openAIResponses,
                    parameterID: .maxOutputTokens,
                    encodingKind: .key,
                    wireKey: "custom_max_tokens"
                ),
                requiredOverride: true,
                optionsOverrideKind: .value,
                options: ["small", "large"]
            )
        ]

        let originalProfile = model.modelProfile
        let restored = try ModelExportData(model).toDataItem(apiConfigurations: [configuration])

        XCTAssertEqual(restored.providerContextSize, 12_000)
        XCTAssertEqual(restored.contextSizeOverride, 24_000)
        XCTAssertEqual(restored.providerUnsupportedParametersRaw, [LLMParameterID.temperature.rawValue])
        XCTAssertEqual(restored.capabilityOverrides.first?.support, .supported)
        XCTAssertEqual(restored.modelProfile, originalProfile)
        XCTAssertEqual(restored.parameterOverrides.first?.wireKey, "custom_max_tokens")
        XCTAssertEqual(restored.parameterOverrides.first?.requiredOverride, true)
        XCTAssertEqual(restored.parameterOverrides.first?.options, ["small", "large"])
    }
}
