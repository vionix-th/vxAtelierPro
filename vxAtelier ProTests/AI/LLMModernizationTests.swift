import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMModernizationTests: XCTestCase {
    func testProviderRegistryProfiles() {
        let registry = LLMProviderRegistry.shared

        XCTAssertEqual(registry.profile(for: .openAIPlatform).defaultEndpointFamily, .responses)
        XCTAssertTrue(registry.profile(for: .openAIPlatform).supportedEndpointFamilies.contains(.chatCompletions))
        XCTAssertFalse(registry.profile(for: .openAIChatGPTSubscription).isEnabled)
        XCTAssertEqual(LLMProviderRegistry.providerID(fromProviderName: "LM Studio"), .lmStudio)
        XCTAssertEqual(LLMProviderRegistry.providerID(fromProviderName: "OpenRouter"), .openRouter)
    }

    func testAPIConfigurationCanonicalProviderFields() {
        let config = APIConfigurationItem(
            name: "OpenRouter",
            apiKey: "key",
            baseURL: "https://openrouter.ai/api",
            providerID: .openRouter
        )

        XCTAssertEqual(config.providerIDEnum, .openRouter)
        XCTAssertEqual(config.defaultEndpointFamilyEnum, .chatCompletions)
        XCTAssertEqual(config.endpointPath(for: .chatCompletions), "/v1/chat/completions")
        XCTAssertEqual(config.endpointPath(for: .models), "/v1/models")
    }

    func testMessageContentPartsAndDisplayTextOrdering() {
        let message = MessageItem(
            role: "assistant",
            contentParts: [
                MessageContentPartItem(index: 1, kind: .text, text: "world"),
                MessageContentPartItem(index: 0, kind: .text, text: "Hello ")
            ]
        )

        XCTAssertEqual(message.displayText, "Hello world")
        XCTAssertEqual(message.asDomainMessage().displayText, "Hello world")
        XCTAssertEqual(message.orderedContentParts.compactMap(\.text).joined(), "Hello world")
    }

    func testToolCallAssemblerMergesDeltasByIndexWhenIDMissing() {
        var assembler = LLMToolCallAssembler()

        _ = assembler.merge(LLMToolCall(id: "call_1", callID: "call_1", index: 0, name: "lookup", argumentsJSON: "{\"q\""))
        _ = assembler.merge(LLMToolCall(id: "", callID: nil, index: 0, name: "", argumentsJSON: ":\"test\"}"))

        XCTAssertEqual(assembler.assembled.count, 1)
        XCTAssertEqual(assembler.assembled.first?.id, "call_1")
        XCTAssertEqual(assembler.assembled.first?.name, "lookup")
        XCTAssertEqual(assembler.assembled.first?.argumentsJSON, "{\"q\":\"test\"}")
    }

    func testOpenAIResponsesReplayIncludesFunctionCallItemsBeforeOutputs() throws {
        let adapter = OpenAIResponsesAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))
        let request = LLMRequest(
            providerID: .openAIPlatform,
            endpointFamily: .responses,
            modelID: "gpt-test",
            messages: [
                LLMMessage(
                    role: "assistant",
                    content: [LLMContentPart(kind: .text, text: "Checking.")],
                    toolCalls: [
                        LLMToolCall(id: "fc_1", callID: "call_1", index: 0, name: "lookup", argumentsJSON: "{\"q\":\"a\"}"),
                        LLMToolCall(id: "fc_2", callID: "call_2", index: 1, name: "lookup", argumentsJSON: "{\"q\":\"b\"}")
                    ]
                ),
                LLMMessage(
                    role: "tool",
                    content: [LLMContentPart(kind: .toolResult, text: "result a")],
                    toolCallID: "call_1"
                ),
                LLMMessage(
                    role: "tool",
                    content: [LLMContentPart(kind: .toolResult, text: "result b")],
                    toolCallID: "call_2"
                )
            ]
        )

        let input = try adapter.responsesInput(from: request)
        XCTAssertEqual(input.count, 5)
        XCTAssertEqual(input[1].objectValue?.string("type"), "function_call")
        XCTAssertEqual(input[1].objectValue?.string("id"), "fc_1")
        XCTAssertEqual(input[1].objectValue?.string("call_id"), "call_1")
        XCTAssertEqual(input[1].objectValue?.string("name"), "lookup")
        XCTAssertEqual(input[2].objectValue?.string("call_id"), "call_2")
        XCTAssertEqual(input[3].objectValue?.string("type"), "function_call_output")
        XCTAssertEqual(input[3].objectValue?.string("call_id"), "call_1")
        XCTAssertEqual(input[4].objectValue?.string("call_id"), "call_2")
    }

    func testOpenAIChatEncodesImageContentParts() throws {
        let adapter = OpenAIChatAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))
        let request = LLMRequest(
            providerID: .openAIPlatform,
            endpointFamily: .chatCompletions,
            modelID: "gpt-test",
            messages: [
                LLMMessage(
                    role: "user",
                    content: [
                        LLMContentPart(kind: .text, text: "Inspect"),
                        LLMContentPart(kind: .image, mimeType: "image/png", dataBase64: "aW1n")
                    ]
                )
            ]
        )

        let body = try adapter.makeBody(for: request, stream: false)
        let messages = try XCTUnwrap(body["messages"]?.arrayValue)
        let content = try XCTUnwrap(messages.first?.objectValue?["content"]?.arrayValue)
        XCTAssertEqual(content[0].objectValue?.string("type"), "text")
        XCTAssertEqual(content[1].objectValue?.string("type"), "image_url")
        XCTAssertEqual(content[1].objectValue?.object("image_url")?.string("url"), "data:image/png;base64,aW1n")
    }

    func testOpenAIResponsesEncodesImageContentParts() throws {
        let adapter = OpenAIResponsesAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))
        let request = LLMRequest(
            providerID: .openAIPlatform,
            endpointFamily: .responses,
            modelID: "gpt-test",
            messages: [
                LLMMessage(
                    role: "user",
                    content: [
                        LLMContentPart(kind: .text, text: "Inspect"),
                        LLMContentPart(kind: .image, sourceURL: "https://unit.test/image.png")
                    ]
                )
            ]
        )

        let body = try adapter.makeBody(for: request, stream: false)
        let input = try XCTUnwrap(body["input"]?.arrayValue)
        let content = try XCTUnwrap(input.first?.objectValue?["content"]?.arrayValue)
        XCTAssertEqual(content[0].objectValue?.string("type"), "input_text")
        XCTAssertEqual(content[1].objectValue?.string("type"), "input_image")
        XCTAssertEqual(content[1].objectValue?.string("image_url"), "https://unit.test/image.png")
    }

    func testOpenAIResponsesEncodesFileDataAsDataURL() throws {
        let adapter = OpenAIResponsesAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))
        let request = LLMRequest(
            providerID: .openAIPlatform,
            endpointFamily: .responses,
            modelID: "gpt-test",
            messages: [
                LLMMessage(
                    role: "user",
                    content: [
                        LLMContentPart(kind: .text, text: "Read"),
                        LLMContentPart(kind: .file, mimeType: "application/pdf", dataBase64: "cGRm", sourceURL: "https://unit.test/doc.pdf")
                    ]
                )
            ]
        )

        let body = try adapter.makeBody(for: request, stream: false)
        let input = try XCTUnwrap(body["input"]?.arrayValue)
        let content = try XCTUnwrap(input.first?.objectValue?["content"]?.arrayValue)
        let file = try XCTUnwrap(content[1].objectValue)
        XCTAssertEqual(file.string("type"), "input_file")
        XCTAssertEqual(file.string("filename"), "doc.pdf")
        XCTAssertEqual(file.string("file_data"), "data:application/pdf;base64,cGRm")
    }

    func testAnthropicEncodesImageContentParts() throws {
        let adapter = AnthropicMessagesAdapter(profile: LLMProviderRegistry.shared.profile(for: .anthropic))
        let request = LLMRequest(
            providerID: .anthropic,
            endpointFamily: .anthropicMessages,
            modelID: "claude-test",
            messages: [
                LLMMessage(
                    role: "user",
                    content: [
                        LLMContentPart(kind: .image, mimeType: "image/webp", dataBase64: "aW1n"),
                        LLMContentPart(kind: .text, text: "Inspect")
                    ]
                )
            ]
        )

        let messages = try adapter.anthropicMessages(from: request)
        let content = try XCTUnwrap(messages.first?.objectValue?.array("content"))
        let source = try XCTUnwrap(content[0].objectValue?.object("source"))
        XCTAssertEqual(content[0].objectValue?.string("type"), "image")
        XCTAssertEqual(source.string("type"), "base64")
        XCTAssertEqual(source.string("media_type"), "image/webp")
        XCTAssertEqual(content[1].objectValue?.string("text"), "Inspect")
    }

    func testAnthropicRejectsUnsupportedImageMediaType() {
        let adapter = AnthropicMessagesAdapter(profile: LLMProviderRegistry.shared.profile(for: .anthropic))
        let request = LLMRequest(
            providerID: .anthropic,
            endpointFamily: .anthropicMessages,
            modelID: "claude-test",
            messages: [
                LLMMessage(
                    role: "user",
                    content: [LLMContentPart(kind: .image, mimeType: "image/heic", dataBase64: "aW1n")]
                )
            ]
        )

        XCTAssertThrowsError(try adapter.anthropicMessages(from: request)) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedParameter("Anthropic image content does not support image/heic."))
        }
    }

    func testAnthropicGroupsAdjacentToolResults() throws {
        let adapter = AnthropicMessagesAdapter(profile: LLMProviderRegistry.shared.profile(for: .anthropic))
        let request = LLMRequest(
            providerID: .anthropic,
            endpointFamily: .anthropicMessages,
            modelID: "claude-test",
            messages: [
                LLMMessage(
                    role: "assistant",
                    content: [LLMContentPart(kind: .text, text: "Checking.")],
                    toolCalls: [
                        LLMToolCall(id: "tool_1", callID: "tool_1", index: 0, name: "lookup", argumentsJSON: "{\"q\":\"a\"}"),
                        LLMToolCall(id: "tool_2", callID: "tool_2", index: 1, name: "lookup", argumentsJSON: "{\"q\":\"b\"}")
                    ]
                ),
                LLMMessage(role: "tool", content: [LLMContentPart(kind: .toolResult, text: "result a")], toolCallID: "tool_1"),
                LLMMessage(role: "tool", content: [LLMContentPart(kind: .toolResult, text: "result b")], toolCallID: "tool_2")
            ]
        )

        let messages = try adapter.anthropicMessages(from: request)
        XCTAssertEqual(messages.count, 2)
        let assistantContent = try XCTUnwrap(messages[0].objectValue?.array("content"))
        XCTAssertEqual(assistantContent[1].objectValue?.string("type"), "tool_use")
        XCTAssertEqual(assistantContent[2].objectValue?.string("id"), "tool_2")
        let toolMessage = try XCTUnwrap(messages[1].objectValue)
        XCTAssertEqual(toolMessage.string("role"), "user")
        let toolResults = try XCTUnwrap(toolMessage.array("content"))
        XCTAssertEqual(toolResults.count, 2)
        XCTAssertEqual(toolResults[0].objectValue?.string("type"), "tool_result")
        XCTAssertEqual(toolResults[0].objectValue?.string("tool_use_id"), "tool_1")
        XCTAssertEqual(toolResults[1].objectValue?.string("tool_use_id"), "tool_2")
    }

    func testOpenAIChatJsonSchemaEncodingConsumesProviderExtra() throws {
        var body: [String: JSONValue] = [:]
        let options = LLMGenerationOptions(
            responseFormat: .jsonSchema,
            providerExtras: [
                "json_schema": .object([
                    "name": .string("answer"),
                    "strict": .boolean(true),
                    "schema": .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ])
                ]),
                "seed": .integer(7)
            ]
        )

        try OpenAICompatibleEncoding.applyOptions(
            options,
            to: &body,
            maxTokenKey: "max_tokens",
            responseFormatTarget: .chatCompletions,
            includeStop: true
        )

        let responseFormat = try XCTUnwrap(body["response_format"]?.objectValue)
        XCTAssertEqual(responseFormat.string("type"), "json_schema")
        XCTAssertEqual(responseFormat.object("json_schema")?.string("name"), "answer")
        XCTAssertEqual(body["seed"], .integer(7))
        XCTAssertNil(body["json_schema"])
    }

    func testOpenAIResponsesJsonSchemaEncodingUsesTextFormat() throws {
        let adapter = OpenAIResponsesAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))
        let request = LLMRequest(
            providerID: .openAIPlatform,
            endpointFamily: .responses,
            modelID: "gpt-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Answer")])],
            options: LLMGenerationOptions(
                responseFormat: .jsonSchema,
                providerExtras: [
                    "json_schema": .object([
                        "name": .string("answer"),
                        "schema": .object(["type": .string("object")])
                    ])
                ]
            )
        )

        let body = try adapter.makeBody(for: request, stream: false)
        let text = try XCTUnwrap(body["text"]?.objectValue)
        let format = try XCTUnwrap(text.object("format"))
        XCTAssertEqual(format.string("type"), "json_schema")
        XCTAssertEqual(format.string("name"), "answer")
        XCTAssertNil(body["json_schema"])
    }

    func testJsonSchemaEncodingRequiresProviderExtraObject() {
        var body: [String: JSONValue] = [:]
        let options = LLMGenerationOptions(responseFormat: .jsonSchema)

        XCTAssertThrowsError(try OpenAICompatibleEncoding.applyOptions(
            options,
            to: &body,
            maxTokenKey: "max_tokens",
            responseFormatTarget: .chatCompletions,
            includeStop: true
        )) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedParameter("response_format json_schema requires providerExtras.json_schema object."))
        }
    }

    func testOpenAIChatMapsGPT5MaxOutputTokensToMaxCompletionTokens() throws {
        let adapter = OpenAIChatAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))
        let request = LLMRequest(
            providerID: .openAIPlatform,
            endpointFamily: .chatCompletions,
            modelID: "gpt-5.4-nano",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "ok")])],
            options: LLMGenerationOptions(maxOutputTokens: 16)
        )

        let body = try adapter.makeBody(for: request, stream: false)
        XCTAssertEqual(body["max_completion_tokens"], .integer(16))
        XCTAssertNil(body["max_tokens"])
    }

    func testOpenAIChatMapsGPT41MaxOutputTokensToMaxTokens() throws {
        let adapter = OpenAIChatAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))
        let request = LLMRequest(
            providerID: .openAIPlatform,
            endpointFamily: .chatCompletions,
            modelID: "gpt-4.1-nano",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "ok")])],
            options: LLMGenerationOptions(maxOutputTokens: 16)
        )

        let body = try adapter.makeBody(for: request, stream: false)
        XCTAssertEqual(body["max_tokens"], .integer(16))
        XCTAssertNil(body["max_completion_tokens"])
    }

    func testAnthropicMessagesUsesRequiredDefaultMaxTokens() throws {
        let adapter = AnthropicMessagesAdapter(profile: LLMProviderRegistry.shared.profile(for: .anthropic))
        let request = LLMRequest(
            providerID: .anthropic,
            endpointFamily: .anthropicMessages,
            modelID: "claude-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "ok")])]
        )

        let body = try adapter.makeBody(for: request, stream: false)
        XCTAssertEqual(body["max_tokens"], .integer(AppDefaults.Anthropic.max_tokens))
    }

    func testCustomizedModelMappingSurvivesDefaultMaterialization() {
        let model = ModelItem(descriptor: LLMModelDescriptor(
            id: "gpt-5.4-nano",
            providerID: .openAIPlatform,
            endpointFamilies: [.chatCompletions],
            modalities: [.text],
            schemaFeatures: [.streaming]
        ))
        let mapping = model.parameterMappings.first {
            $0.endpointFamilyEnum == .chatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        mapping?.wireKey = "custom_max_tokens"
        mapping?.markCustomized()

        LLMParameterMappingCatalog.materializeDefaults(on: model, preserveCustomized: true)

        XCTAssertEqual(mapping?.wireKey, "custom_max_tokens")
    }

    func testDisabledOptionalParameterDoesNotReachGenerationOptions() {
        let options = ConversationOptions(shouldSetupParameters: false)
        options.temperature = 0.9
        let temperature = AiRequestArgument(
            name: LLMApplicationParameterID.temperature.rawValue,
            displayName: LLMApplicationParameterID.temperature.displayName,
            valueType: .float,
            controlType: .slider,
            defaultValue: 0.9
        )
        temperature.isEnabled = false
        options.parameters = [temperature]

        let generationOptions = options.generationOptions(resolvedModelID: "model", resolvedEndpointFamily: .chatCompletions)

        XCTAssertNil(generationOptions.temperature)
    }

    func testRequestBuilderResolvesModelFromSelectedAPIConfiguration() throws {
        let env = TestEnvironment()
        let configA = APIConfigurationItem(
            name: "OpenAI A",
            apiKey: "key-a",
            baseURL: "https://unit.test/a",
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let configB = APIConfigurationItem(
            name: "OpenAI B",
            apiKey: "key-b",
            baseURL: "https://unit.test/b",
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        configA.defaultEndpointFamilyEnum = .chatCompletions
        configB.defaultEndpointFamilyEnum = .chatCompletions
        let descriptor = LLMModelDescriptor(
            id: "gpt-test",
            providerID: .openAIPlatform,
            endpointFamilies: [.chatCompletions],
            modalities: [.text],
            supportedParameters: LLMProviderRegistry.shared.profile(for: .openAIPlatform).supportedParameters,
            parameterMappings: [],
            schemaFeatures: [.streaming]
        )
        let modelA = ModelItem(descriptor: descriptor, apiConfiguration: configA)
        let modelB = ModelItem(descriptor: descriptor, apiConfiguration: configB)
        let mappingA = modelA.parameterMappings.first {
            $0.endpointFamilyEnum == .chatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        mappingA?.wireKey = "max_tokens_a"
        mappingA?.markCustomized()
        let mappingB = modelB.parameterMappings.first {
            $0.endpointFamilyEnum == .chatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        mappingB?.wireKey = "max_tokens_b"
        mappingB?.markCustomized()

        let options = ConversationOptions(apiConfiguration: configB, shouldSetupParameters: false)
        options.modelOverride = "gpt-test"
        let conversation = ConversationItem("Scoped model", options: options)

        env.modelContext.insert(configA)
        env.modelContext.insert(configB)
        env.modelContext.insert(modelA)
        env.modelContext.insert(modelB)
        env.modelContext.insert(conversation)

        let request = try LLMConversationRequestBuilder().makeRequest(
            conversation: conversation,
            apiConfig: configB
        )

        let maxOutputMapping = request.modelDescriptor?.parameterMappings.first {
            $0.endpointFamily == .chatCompletions && $0.semanticParameterID == .maxOutputTokens
        }
        XCTAssertEqual(
            maxOutputMapping?.wireKey,
            "max_tokens_b",
            "Resolved wire key: \(maxOutputMapping?.wireKey ?? "nil"), descriptor config provider: \(request.modelDescriptor?.providerID.rawValue ?? "nil")"
        )
    }

    func testStreamModeAutoUsesNonStreamingWhenModelDoesNotSupportStreaming() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { request in
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
            XCTAssertEqual(body.objectValue?.bool("stream"), false)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_nonstream"]
            )!
            return (response, Data("{\"id\":\"resp\",\"model\":\"gpt-test\",\"output_text\":\"Done\"}".utf8))
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config, shouldSetupParameters: false)
        options.modelOverride = "gpt-test"
        options.streamMode = .auto
        let conversation = ConversationItem("Auto stream", options: options)
        let descriptor = LLMModelDescriptor(
            id: "gpt-test",
            providerID: .openAIPlatform,
            endpointFamilies: [.responses],
            modalities: [.text],
            supportedParameters: LLMProviderRegistry.shared.profile(for: .openAIPlatform).supportedParameters,
            schemaFeatures: [.usage]
        )
        env.modelContext.insert(config)
        env.modelContext.insert(ModelItem(descriptor: descriptor, apiConfiguration: config))
        env.modelContext.insert(conversation)

        try await LLMConversationExecutor.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        )

        let run = try XCTUnwrap(conversation.turns.first?.responseRuns.first)
        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.requestID, "req_nonstream")
    }

    func testStreamModeEnabledFailsPreflightWhenModelDoesNotSupportStreaming() async {
        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config, shouldSetupParameters: false)
        options.modelOverride = "gpt-test"
        options.streamMode = .enabled
        let conversation = ConversationItem("Stream required", options: options)
        let descriptor = LLMModelDescriptor(
            id: "gpt-test",
            providerID: .openAIPlatform,
            endpointFamilies: [.responses],
            modalities: [.text],
            supportedParameters: LLMProviderRegistry.shared.profile(for: .openAIPlatform).supportedParameters,
            schemaFeatures: [.usage]
        )
        env.modelContext.insert(config)
        env.modelContext.insert(ModelItem(descriptor: descriptor, apiConfiguration: config))
        env.modelContext.insert(conversation)

        await assertThrowsAsyncError(try await LLMConversationExecutor.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        ))

        XCTAssertTrue(conversation.turns.isEmpty)
    }

    func testCapabilityValidationRejectsUnsupportedImageContent() {
        let profile = LLMProviderRegistry.shared.profile(for: .lmStudio)
        let request = LLMRequest(
            providerID: .lmStudio,
            endpointFamily: .chatCompletions,
            modelID: "local-model",
            messages: [
                LLMMessage(role: "user", content: [LLMContentPart(kind: .image, dataBase64: "aW1n")])
            ]
        )

        XCTAssertThrowsError(try LLMCapabilityValidator.validate(request, profile: profile)) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedCapability("LM Studio does not support image content for local-model."))
        }
    }

    func testCapabilityValidationRejectsFileContentOutsideResponses() {
        let profile = LLMProviderRegistry.shared.profile(for: .openAIPlatform)
        let request = LLMRequest(
            providerID: .openAIPlatform,
            endpointFamily: .chatCompletions,
            modelID: "gpt-test",
            messages: [
                LLMMessage(role: "user", content: [LLMContentPart(kind: .file, dataBase64: "ZmlsZQ==")])
            ]
        )

        XCTAssertThrowsError(try LLMCapabilityValidator.validate(request, profile: profile)) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedCapability("OpenAI does not support file content for chatCompletions."))
        }
    }

    func testCapabilityValidationRejectsUnmatchedToolResult() {
        let profile = LLMProviderRegistry.shared.profile(for: .openAIPlatform)
        let request = LLMRequest(
            providerID: .openAIPlatform,
            endpointFamily: .responses,
            modelID: "gpt-test",
            messages: [
                LLMMessage(role: "tool", content: [LLMContentPart(kind: .toolResult, text: "result")], toolCallID: "call_missing")
            ]
        )

        XCTAssertThrowsError(try LLMCapabilityValidator.validate(request, profile: profile)) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedParameter("Tool result call_missing has no prior assistant tool call."))
        }
    }

    func testCapabilityValidationRejectsNonImmediateAnthropicToolResult() {
        let profile = LLMProviderRegistry.shared.profile(for: .anthropic)
        let request = LLMRequest(
            providerID: .anthropic,
            endpointFamily: .anthropicMessages,
            modelID: "claude-test",
            messages: [
                LLMMessage(
                    role: "assistant",
                    content: [LLMContentPart(kind: .text, text: "Checking")],
                    toolCalls: [LLMToolCall(id: "tool_1", callID: "tool_1", index: 0, name: "lookup", argumentsJSON: "{}")]
                ),
                LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "interrupt")]),
                LLMMessage(role: "tool", content: [LLMContentPart(kind: .toolResult, text: "result")], toolCallID: "tool_1")
            ]
        )

        XCTAssertThrowsError(try LLMCapabilityValidator.validate(request, profile: profile)) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedParameter("Anthropic tool_result must immediately follow its assistant tool_use."))
        }
    }

    func testResponseRunRejectsInvalidStatusTransition() throws {
        let run = ResponseRunItem(
            providerID: .openAIPlatform,
            endpointFamily: .responses,
            requestedModelID: "gpt-test",
            status: .pending
        )

        XCTAssertThrowsError(try run.transition(to: .completed)) { error in
            XCTAssertEqual(error as? LLMProviderError, .invalidConfiguration("Invalid response run transition pending -> completed."))
        }
        try run.transition(to: .streaming)
        try run.transition(to: .completed)
        XCTAssertEqual(run.status, .completed)
    }

    func testHTTPMetadataExtractsRequestAndRateLimitHeaders() throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://unit.test/v1/responses")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "x-request-id": "req_123",
                "retry-after": "3",
                "x-ratelimit-remaining-requests": "9"
            ]
        ))

        let metadata = LLMHTTPClient().metadata(from: response)
        XCTAssertEqual(metadata.statusCode, 200)
        XCTAssertEqual(metadata.requestID, "req_123")
        XCTAssertEqual(metadata.retryAfter, "3")
        XCTAssertEqual(metadata.rateLimitHeaders["x-ratelimit-remaining-requests"], "9")
    }

    func testHTTPMetadataRedactsSensitiveHeaders() throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://unit.test/v1/responses")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "x-request-id": "req_123",
                "authorization": "Bearer sk-test-secret",
                "set-cookie": "session=secret"
            ]
        ))

        let metadata = LLMHTTPClient().metadata(from: response)
        XCTAssertEqual(metadata.requestID, "req_123")
        XCTAssertEqual(metadata.headers["authorization"], "[redacted]")
        XCTAssertEqual(metadata.headers["set-cookie"], "[redacted]")
    }

    func testProviderErrorMessageIsRedactedAndLimited() async {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_secret"]
            )!
            return (response, Data("{\"error\":\"Bearer sk-test-secret should not leak\"}".utf8))
        }

        let client = LLMHTTPClient()
        let config = LLMHTTPClient.Configuration(baseURL: "https://unit.test", headers: [:])
        await assertThrowsAsyncError(try await client.getJSONWithMetadata(
            path: "/v1/models",
            configuration: config,
            responseType: JSONValue.self
        )) { error in
            guard case .provider(let statusCode, let message, let metadata) = error as? LLMProviderError else {
                XCTFail("Expected provider error")
                return
            }
            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(metadata?.requestID, "req_secret")
            XCTAssertFalse(message.contains("sk-test-secret"))
            XCTAssertTrue(message.contains("[redacted]"))
        }
    }

    func testHTTPClientAppliesTimeoutAndResponseSizeOptions() async {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.timeoutInterval, 7)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_large"]
            )!
            return (response, Data("{\"too\":\"large\"}".utf8))
        }

        let configItem = APIConfigurationItem(
            name: "Custom",
            apiKey: "",
            baseURL: "https://unit.test",
            providerID: .customOpenAICompatible
        )
        configItem.decodedOptions = [
            "request_timeout_seconds": "7",
            "max_response_body_bytes": "4"
        ]
        let profile = LLMProviderRegistry.shared.profile(for: .customOpenAICompatible)
        let config = LLMHTTPClient().makeConfiguration(for: configItem, profile: profile)

        await assertThrowsAsyncError(try await LLMHTTPClient().getJSONWithMetadata(
            path: "/v1/models",
            configuration: config,
            responseType: JSONValue.self
        )) { error in
            guard case .provider(let statusCode, let message, let metadata) = error as? LLMProviderError else {
                XCTFail("Expected provider error")
                return
            }
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(message, "Provider response exceeded configured size limit.")
            XCTAssertEqual(metadata?.requestID, "req_large")
        }
    }

    func testProviderFailureAfterRunCreationPersistsFailedResponseRun() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.host, "unit.test")
            XCTAssertEqual(request.url?.path, "/v1/responses")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_failed"]
            )!
            return (response, Data("{\"error\":\"boom\"}".utf8))
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config, shouldSetupParameters: false)
        options.modelOverride = "gpt-test"
        options.streamMode = .disabled
        let conversation = ConversationItem("Failure", options: options)
        env.modelContext.insert(config)
        env.modelContext.insert(conversation)

        await assertThrowsAsyncError(try await LLMConversationExecutor.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        ))

        XCTAssertEqual(conversation.turns.count, 1)
        let run = try XCTUnwrap(conversation.turns.first?.responseRuns.first)
        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.requestID, "req_failed")
        XCTAssertEqual(run.statusCode, 500)
        XCTAssertNotNil(run.responseMetadataJSON)
        XCTAssertNotNil(run.errorMessage)
        XCTAssertNotNil(run.completedAt)
    }

    func testRetryPolicyRetriesTransientProviderErrorOnce() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        var requestCount = 0
        MockLLMURLProtocol.requestHandler = { request in
            requestCount += 1
            if requestCount == 1 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: ["x-request-id": "req_first"]
                )!
                return (response, Data("{\"error\":\"temporary\"}".utf8))
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_second"]
            )!
            let body = Data("""
            {"id":"resp_retry","model":"gpt-test","output_text":"Done","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}
            """.utf8)
            return (response, body)
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config, shouldSetupParameters: false)
        options.modelOverride = "gpt-test"
        options.streamMode = .disabled
        options.retryPolicy = .oneRetryBeforeTools
        let conversation = ConversationItem("Retry", options: options)
        env.modelContext.insert(config)
        env.modelContext.insert(conversation)

        try await LLMConversationExecutor.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        )

        XCTAssertEqual(requestCount, 2)
        let run = try XCTUnwrap(conversation.turns.first?.responseRuns.first)
        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.requestID, "req_second")
    }

    func testRetryPolicyDoesNotRetryNonTransientProviderError() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        var requestCount = 0
        MockLLMURLProtocol.requestHandler = { request in
            requestCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_bad"]
            )!
            return (response, Data("{\"error\":\"bad request\"}".utf8))
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config, shouldSetupParameters: false)
        options.modelOverride = "gpt-test"
        options.streamMode = .disabled
        options.retryPolicy = .oneRetryBeforeTools
        let conversation = ConversationItem("No Retry", options: options)
        env.modelContext.insert(config)
        env.modelContext.insert(conversation)

        await assertThrowsAsyncError(try await LLMConversationExecutor.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        ))

        XCTAssertEqual(requestCount, 1)
        let run = try XCTUnwrap(conversation.turns.first?.responseRuns.first)
        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.requestID, "req_bad")
        XCTAssertEqual(run.statusCode, 400)
    }

    func testToolExecutionFailureMarksAwaitingRunFailed() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_tool"]
            )!
            let body = Data("""
            {"id":"resp_tool","model":"gpt-test","output":[{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup","arguments":"{}"}]}
            """.utf8)
            return (response, body)
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config, shouldSetupParameters: false)
        options.modelOverride = "gpt-test"
        options.streamMode = .disabled
        let conversation = ConversationItem("Tool failure", options: options)
        env.modelContext.insert(config)
        env.modelContext.insert(conversation)

        await assertThrowsAsyncError(try await LLMConversationExecutor.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        ))

        let run = try XCTUnwrap(conversation.turns.first?.responseRuns.first)
        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.requestID, "req_tool")
        XCTAssertNotNil(run.completedAt)
        XCTAssertEqual(conversation.turns.first?.events.first?.message.toolCallItems.first?.status, .failed)
    }

    func testConfigurableToolDefaultsRoundTripThroughConversationOptions() throws {
        let options = ConversationOptions(shouldSetupParameters: false)
        let defaults = ListShortcutsTool().defaultConfiguration()

        options.setToolConfiguration("list_shortcuts", configuration: defaults)

        let restored = try XCTUnwrap(options.getToolConfiguration("list_shortcuts"))
        XCTAssertEqual(restored["Restricted"]?.boolValue, false)
        XCTAssertEqual(restored["RestrictedList"]?.objectValue?["ID0001"]?.stringValue, "Shortcut Name A")
    }

    func testNonConfigurableToolDoesNotExposeConfiguration() {
        XCTAssertNil(RunShortcutTool() as? any ConfigurableAITool)
    }

    func testSuccessfulToolExecutionUsesTypedCallAndEmptyDefaultConfiguration() async throws {
        AIToolRegistry.shared.registerTool(UnitEchoTool())
        let fixture = makeToolExecutionFixture(toolName: UnitEchoTool.toolName)
        let conversation = fixture.conversation
        let turn = fixture.turn
        let toolCall = fixture.toolCall
        conversation.options.setToolEnabled(UnitEchoTool.toolName, enabled: true)

        try await LLMToolExecutionCoordinator().execute([toolCall], conversation: conversation, turn: turn)

        XCTAssertEqual(toolCall.status, .completed)
        XCTAssertEqual(toolCall.resultMessage?.displayText, "id=call_1 name=unit_echo_tool args={\"value\":\"ok\"} config=0 title=Tool Test turn=0")
        XCTAssertEqual(turn.events.first?.type, .toolResult)
    }

    func testListShortcutsToolReceivesJSONValueConfiguration() async throws {
        let env = TestEnvironment()
        let conversation = ConversationItem("Shortcuts", options: ConversationOptions(shouldSetupParameters: false))
        let turn = ConversationTurn(
            sequenceNumber: 0,
            userMessage: MessageItem(role: "user", text: "List shortcuts"),
            conversation: conversation
        )
        conversation.turns.append(turn)
        env.modelContext.insert(conversation)
        let call = ToolExecutionCall(
            id: "call_shortcuts",
            name: "list_shortcuts",
            argumentsJSON: "{}",
            configuration: [
                "Restricted": .boolean(true),
                "RestrictedList": .object([
                    "ID0001": .string("Shortcut Name A")
                ])
            ],
            context: ToolExecutionContext(conversation: conversation, turn: turn)
        )

        let result = try await ListShortcutsTool().execute(call)

        let data = try XCTUnwrap(result.data(using: .utf8))
        let shortcuts = try JSONDecoder().decode([[String: String]].self, from: data)
        XCTAssertEqual(shortcuts, [["id": "ID0001", "name": "Shortcut Name A"]])
    }

    func testDisabledToolCallFailsAndPersistsFailedStatus() async throws {
        let fixture = makeToolExecutionFixture(toolName: UnitEchoTool.toolName)
        let conversation = fixture.conversation
        let turn = fixture.turn
        let toolCall = fixture.toolCall
        conversation.options.setToolEnabled(UnitEchoTool.toolName, enabled: false)

        await assertThrowsAsyncError(try await LLMToolExecutionCoordinator().execute([toolCall], conversation: conversation, turn: turn)) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedCapability("Tool '\(UnitEchoTool.toolName)' is not enabled."))
        }

        XCTAssertEqual(toolCall.status, .failed)
        XCTAssertEqual(toolCall.errorMessage, "Tool '\(UnitEchoTool.toolName)' is not enabled.")
    }

    func testMissingToolCallFailsAndPersistsFailedStatus() async throws {
        let missingToolName = "unit_missing_tool"
        let fixture = makeToolExecutionFixture(toolName: missingToolName)
        let conversation = fixture.conversation
        let turn = fixture.turn
        let toolCall = fixture.toolCall
        conversation.options.setToolEnabled(missingToolName, enabled: true)

        await assertThrowsAsyncError(try await LLMToolExecutionCoordinator().execute([toolCall], conversation: conversation, turn: turn)) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedCapability("Tool not found: \(missingToolName)"))
        }

        XCTAssertEqual(toolCall.status, .failed)
        XCTAssertEqual(toolCall.errorMessage, "Tool not found: \(missingToolName)")
    }

    func testNonExecutableToolCallFailsAndPersistsFailedStatus() async throws {
        AIToolRegistry.shared.registerTool(UnitSchemaOnlyTool())
        let fixture = makeToolExecutionFixture(toolName: UnitSchemaOnlyTool.toolName)
        let conversation = fixture.conversation
        let turn = fixture.turn
        let toolCall = fixture.toolCall
        conversation.options.setToolEnabled(UnitSchemaOnlyTool.toolName, enabled: true)

        await assertThrowsAsyncError(try await LLMToolExecutionCoordinator().execute([toolCall], conversation: conversation, turn: turn)) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedCapability("Tool execution not supported: \(UnitSchemaOnlyTool.toolName)"))
        }

        XCTAssertEqual(toolCall.status, .failed)
        XCTAssertEqual(toolCall.errorMessage, "Tool execution not supported: \(UnitSchemaOnlyTool.toolName)")
    }

    func testHTTPMetadataFlowsIntoSuccessfulResponseRun() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "x-request-id": "req_header",
                    "retry-after": "4",
                    "x-ratelimit-remaining-requests": "8"
                ]
            )!
            let body = Data("""
            {"id":"resp_body","model":"gpt-test","output_text":"Done","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}
            """.utf8)
            return (response, body)
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config, shouldSetupParameters: false)
        options.modelOverride = "gpt-test"
        options.streamMode = .disabled
        let conversation = ConversationItem("Success", options: options)
        env.modelContext.insert(config)
        env.modelContext.insert(conversation)

        try await LLMConversationExecutor.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        )

        let run = try XCTUnwrap(conversation.turns.first?.responseRuns.first)
        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.requestID, "req_header")
        XCTAssertEqual(run.statusCode, 200)
        XCTAssertEqual(run.retryAfter, "4")
        XCTAssertNotNil(run.responseMetadataJSON)
        XCTAssertEqual(run.inputTokens, 1)
        XCTAssertEqual(run.outputTokens, 2)
        XCTAssertEqual(run.totalTokens, 3)
    }

    func testCancellationAfterRunCreationPersistsCancelledResponseRun() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { _ in
            throw URLError(.cancelled)
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config, shouldSetupParameters: false)
        options.modelOverride = "gpt-test"
        options.streamMode = .disabled
        let conversation = ConversationItem("Cancelled", options: options)
        env.modelContext.insert(config)
        env.modelContext.insert(conversation)

        await assertThrowsAsyncError(try await LLMConversationExecutor.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        )) { error in
            XCTAssertEqual(error as? LLMProviderError, .cancelled)
        }

        XCTAssertEqual(conversation.turns.count, 1)
        let run = try XCTUnwrap(conversation.turns.first?.responseRuns.first)
        XCTAssertEqual(run.status, .cancelled)
        XCTAssertNotNil(run.completedAt)
    }

    func testPreflightModelErrorRemovesNewUserTurn() async {
        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "Custom",
            apiKey: "",
            baseURL: "https://unit.test/v1",
            providerID: .customOpenAICompatible
        )
        let options = ConversationOptions(apiConfiguration: config, shouldSetupParameters: false)
        let conversation = ConversationItem("Preflight", options: options)
        env.modelContext.insert(config)
        env.modelContext.insert(conversation)

        await assertThrowsAsyncError(try await LLMConversationExecutor.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        ))

        XCTAssertTrue(conversation.turns.isEmpty)
    }

    func testOpenAIChatStreamingFixture() async throws {
        try installFixtureHandler(name: "openai_chat_stream", fileExtension: "sse")
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }

        let adapter = OpenAIChatAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))
        let request = LLMRequest.runtimeEquivalent(
            providerID: .openAIPlatform,
            endpointFamily: .chatCompletions,
            modelID: "gpt-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])],
            options: LLMGenerationOptions(streamMode: .enabled)
        )
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )

        let events = try await collectEvents(adapter.stream(request, configuration: config))
        XCTAssertTrue(events.contains(.textDelta("Hello")))
        XCTAssertTrue(events.contains(where: { event in
            if case .toolCallCompleted(let call) = event {
                return call.callID == "call_1" && call.name == "lookup" && call.argumentsJSON == "{\"q\":\"test\"}"
            }
            return false
        }))
        XCTAssertTrue(events.contains(.runCompleted(responseID: nil, modelID: nil)))
    }

    func testOpenAIResponsesStreamingFixture() async throws {
        try installFixtureHandler(name: "openai_responses_stream", fileExtension: "sse")
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }

        let adapter = OpenAIResponsesAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))
        let request = LLMRequest.runtimeEquivalent(
            providerID: .openAIPlatform,
            endpointFamily: .responses,
            modelID: "gpt-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])],
            options: LLMGenerationOptions(streamMode: .enabled)
        )
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )

        let events = try await collectEvents(adapter.stream(request, configuration: config))
        XCTAssertTrue(events.contains(.runStarted(requestID: "resp_fixture")))
        XCTAssertTrue(events.contains(.textDelta("Hello")))
        XCTAssertTrue(events.contains(.usage(LLMUsage(inputTokens: 5, outputTokens: 7, totalTokens: 12))))
        XCTAssertTrue(events.contains(.runCompleted(responseID: "resp_fixture", modelID: "gpt-4.1-mini")))
        XCTAssertTrue(events.contains(where: { event in
            if case .toolCallCompleted(let call) = event {
                return call.id == "fc_1" && call.callID == "call_1" && call.argumentsJSON == "{\"q\":\"test\"}"
            }
            return false
        }))
    }

    func testResponsesStreamWithoutCompletionEventFails() async throws {
        try installFixtureHandler(name: "cancellation", fileExtension: "sse")
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }

        let adapter = OpenAIResponsesAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))
        let request = LLMRequest(
            providerID: .openAIPlatform,
            endpointFamily: .responses,
            modelID: "gpt-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])],
            options: LLMGenerationOptions(streamMode: .enabled)
        )
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )

        await assertThrowsAsyncError(try await collectEvents(adapter.stream(request, configuration: config))) { error in
            XCTAssertEqual(error as? LLMProviderError, .decoding("Provider stream ended before completion event."))
        }
    }

    func testAnthropicStreamingFixture() async throws {
        try installFixtureHandler(name: "anthropic_messages_stream", fileExtension: "sse")
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }

        let adapter = AnthropicMessagesAdapter(profile: LLMProviderRegistry.shared.profile(for: .anthropic))
        let request = LLMRequest.runtimeEquivalent(
            providerID: .anthropic,
            endpointFamily: .anthropicMessages,
            modelID: "claude-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])],
            options: LLMGenerationOptions(streamMode: .enabled)
        )
        let config = APIConfigurationItem(
            name: "Anthropic",
            apiKey: "key",
            baseURL: "https://unit.test",
            defaultModel: "claude-test",
            providerID: .anthropic
        )

        let events = try await collectEvents(adapter.stream(request, configuration: config))
        XCTAssertTrue(events.contains(.runStarted(requestID: "msg_fixture")))
        XCTAssertTrue(events.contains(.textDelta("Hello")))
        XCTAssertTrue(events.contains(.runCompleted(responseID: nil, modelID: nil)))
        XCTAssertTrue(events.contains(where: { event in
            if case .toolCallCompleted(let call) = event {
                return call.callID == "toolu_1" && call.name == "lookup" && call.argumentsJSON == "{\"q\":\"test\"}"
            }
            return false
        }))
    }

    func testOpenAICompatibleModelMetadataFixtures() throws {
        let openRouterData = try fixtureJSON(name: "openrouter_models").objectValue?.array("data") ?? []
        let openRouterProfile = LLMProviderRegistry.shared.profile(for: .openRouter)
        let openRouterModels = LLMModelMetadataDecoder.openAICompatibleDescriptors(
            from: openRouterData,
            profile: openRouterProfile,
            endpointFamilies: [.chatCompletions]
        )
        XCTAssertEqual(openRouterModels.first?.id, "openai/gpt-4o-mini")
        XCTAssertEqual(openRouterModels.first?.displayName, "GPT-4o Mini")
        XCTAssertEqual(openRouterModels.first?.contextWindow, 128000)
        XCTAssertEqual(openRouterModels.first?.modalities, [.text])

        let lmStudioData = try fixtureJSON(name: "lmstudio_models").objectValue?.array("data") ?? []
        let lmStudioModels = LLMModelMetadataDecoder.openAICompatibleDescriptors(
            from: lmStudioData,
            profile: LLMProviderRegistry.shared.profile(for: .lmStudio),
            endpointFamilies: [.chatCompletions]
        )
        XCTAssertEqual(lmStudioModels.first?.id, "local-model")
        XCTAssertEqual(lmStudioModels.first?.modalities, [.text])

        let ollamaData = try fixtureJSON(name: "ollama_models").objectValue?.array("data") ?? []
        let ollamaModels = LLMModelMetadataDecoder.openAICompatibleDescriptors(
            from: ollamaData,
            profile: LLMProviderRegistry.shared.profile(for: .ollama),
            endpointFamilies: [.chatCompletions]
        )
        XCTAssertEqual(ollamaModels.first?.id, "llama3.2")
        XCTAssertEqual(ollamaModels.first?.endpointFamilies, [.chatCompletions])
    }

    func testMessageExportRoundtripPreservesPartsAndToolCalls() {
        let message = MessageItem(
            role: "assistant",
            contentParts: [
                MessageContentPartItem(index: 0, kind: .text, text: "Use tool")
            ]
        )
        message.toolCallItems = [
            ToolCallItem(callID: "call_1", providerCallID: "call_1", index: 0, name: "lookup", argumentsJSON: "{\"q\":\"test\"}")
        ]

        let exported = MessageExportData(message)
        let restored = exported.toDataItem()

        XCTAssertEqual(restored.displayText, "Use tool")
        XCTAssertEqual(restored.toolCallItems.count, 1)
        XCTAssertEqual(restored.toolCallItems.first?.argumentsJSON, "{\"q\":\"test\"}")
    }

    func testFixtureResourcesExist() throws {
        let names = [
            "openai_chat_stream",
            "openai_responses_stream",
            "anthropic_messages_stream",
            "openrouter_models",
            "lmstudio_models",
            "ollama_models",
            "malformed_stream",
            "retryable_failure",
            "cancellation"
        ]

        for name in names {
            let ext = name.contains("models") || name == "retryable_failure" ? "json" : "sse"
            XCTAssertNotNil(fixtureURL(name: name, fileExtension: ext), "Missing fixture \(name).\(ext)")
        }
    }

    private func installFixtureHandler(name: String, fileExtension ext: String) throws {
        let data = try fixtureData(name: name, fileExtension: ext)
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        MockLLMURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "x-request-id": "req_fixture",
                    "content-type": ext == "sse" ? "text/event-stream" : "application/json"
                ]
            )!
            return (response, data)
        }
    }

    private func fixtureData(name: String, fileExtension ext: String) throws -> Data {
        let url = try XCTUnwrap(fixtureURL(name: name, fileExtension: ext))
        return try Data(contentsOf: url)
    }

    private func fixtureURL(name: String, fileExtension ext: String) -> URL? {
        let bundle = Bundle(for: LLMModernizationTests.self)
        return bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "AI/Fixtures")
    }

    private func fixtureJSON(name: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: fixtureData(name: name, fileExtension: "json"))
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

    private func makeToolExecutionFixture(
        toolName: String
    ) -> (environment: TestEnvironment, conversation: ConversationItem, turn: ConversationTurn, toolCall: ToolCallItem) {
        let env = TestEnvironment()
        let conversation = ConversationItem("Tool Test", options: ConversationOptions(shouldSetupParameters: false))
        let userMessage = MessageItem(role: "user", text: "Run tool")
        let turn = ConversationTurn(sequenceNumber: 0, userMessage: userMessage, conversation: conversation)
        let toolCall = ToolCallItem(
            callID: "call_1",
            providerCallID: "provider_call_1",
            index: 0,
            name: toolName,
            argumentsJSON: "{\"value\":\"ok\"}"
        )
        conversation.turns.append(turn)
        env.modelContext.insert(conversation)
        return (env, conversation, turn, toolCall)
    }
}

private struct UnitEchoTool: ExecutableTool {
    static let toolName = "unit_echo_tool"

    let name = UnitEchoTool.toolName
    let description = "Echoes typed tool execution fields for unit tests."
    var parameters: any AIToolParameters { GenericToolParameters(properties: [:]) }

    func execute(_ call: ToolExecutionCall) async throws -> String {
        "id=\(call.id) name=\(call.name) args=\(call.argumentsJSON) config=\(call.configuration.count) title=\(call.context.conversation.title) turn=\(call.context.turn.sequenceNumber)"
    }
}

private struct UnitSchemaOnlyTool: AITool {
    static let toolName = "unit_schema_only_tool"

    let name = UnitSchemaOnlyTool.toolName
    let description = "Schema-only unit test tool."
    var parameters: any AIToolParameters { GenericToolParameters(properties: [:]) }
}

final class MockLLMURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "unit.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
