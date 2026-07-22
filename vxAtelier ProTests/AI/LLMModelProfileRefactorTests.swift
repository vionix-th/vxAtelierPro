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
        XCTAssertEqual(profile.parameters[.temperature]?.support, LLMSupport(state: .unsupported, source: .catalog))
    }

    func testUnsupportedSupportStateDoesNotSuppressExplicitMappedParameter() {
        let mapping = LLMParameterMapping(
            adapterID: .openAIResponses,
            parameterID: .reasoningEffort,
            encodingKind: .structuredPreset,
            structuredPreset: .openAIResponsesReasoning
        )
        let profile = LLMParameterProfile(
            parameterID: .reasoningEffort,
            support: LLMSupport(state: .unsupported, source: .userOverride),
            mapping: mapping,
            isRequired: false,
            isEnabledByDefault: false,
            defaultValue: nil,
            options: nil
        )
        let resolved = LLMGenerationOptionsResolver.resolve(
            options: LLMGenerationOptions(reasoning: "low"),
            conversationPreferences: [LLMParameterID.reasoningEffort.rawValue: true],
            parameterProfiles: [.reasoningEffort: profile]
        )

        XCTAssertTrue(resolved.activeParameterIDs.contains(.reasoningEffort))
        XCTAssertEqual(resolved.options.reasoning, "low")
        XCTAssertEqual(resolved.mappings, [mapping])
    }

    func testEnabledUnmappedParameterFailsDuringEncoding() {
        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "gpt-test",
            activeParameterIDs: [.reasoningEffort],
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])],
            options: LLMGenerationOptions(reasoning: "low")
        )
        let adapter = OpenAIResponsesAdapter(
            profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform)
        )

        XCTAssertThrowsError(try adapter.makeBody(for: request, stream: false)) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .requestEncoding("No active wire mapping for reasoning_effort.")
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
            parameterMappings: [
                LLMParameterMapping(
                    adapterID: .openAIResponses,
                    parameterID: .responseFormat,
                    encodingKind: .structuredPreset,
                    structuredPreset: .openAIResponsesTextFormat
                ),
                LLMParameterMapping(
                    adapterID: .openAIResponses,
                    parameterID: .reasoningEffort,
                    encodingKind: .structuredPreset,
                    structuredPreset: .openAIResponsesReasoning
                )
            ],
            activeParameterIDs: [.responseFormat, .reasoningEffort, .stream],
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
        let adapter = OpenAIResponsesAdapter(
            profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform)
        )

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
        XCTAssertTrue(model.parameterMappingOverrides.isEmpty)
        XCTAssertTrue(model.parameterOverrides.isEmpty)
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

        let originalProfile = model.modelProfile
        let restored = ModelExportData(model).toDataItem(apiConfigurations: [configuration])

        XCTAssertEqual(restored.providerContextSize, 12_000)
        XCTAssertEqual(restored.contextSizeOverride, 24_000)
        XCTAssertEqual(restored.providerUnsupportedParametersRaw, [LLMParameterID.temperature.rawValue])
        XCTAssertEqual(restored.capabilityOverrides.first?.support, .supported)
        XCTAssertEqual(restored.modelProfile, originalProfile)
        XCTAssertTrue(restored.parameterMappingOverrides.isEmpty)
        XCTAssertTrue(restored.parameterOverrides.isEmpty)
    }
}
