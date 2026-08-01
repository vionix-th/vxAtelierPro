import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMGenerationAdapterEncodingTests: XCTestCase {
    func testOpenAIResponsesReplayIncludesFunctionCallItemsBeforeOutputs() throws {
        let adapter = OpenAIResponsesAdapter()
        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
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
        let adapter = OpenAIChatCompletionsAdapter()
        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIChatCompletions,
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
        let adapter = OpenAIResponsesAdapter()
        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
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
        let adapter = OpenAIResponsesAdapter()
        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
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
        let adapter = AnthropicMessagesAdapter()
        let request = LLMGenerationRequest(
            providerID: .anthropic,
            adapterID: .anthropicMessages,
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
        let adapter = AnthropicMessagesAdapter()
        let request = LLMGenerationRequest(
            providerID: .anthropic,
            adapterID: .anthropicMessages,
            modelID: "claude-test",
            messages: [
                LLMMessage(
                    role: "user",
                    content: [LLMContentPart(kind: .image, mimeType: "image/heic", dataBase64: "aW1n")]
                )
            ]
        )

        XCTAssertThrowsError(try adapter.anthropicMessages(from: request)) { error in
            XCTAssertEqual(error as? LLMProviderError, .requestEncoding("Anthropic image content does not support image/heic."))
        }
    }

    func testAnthropicGroupsAdjacentToolResults() throws {
        let adapter = AnthropicMessagesAdapter()
        let request = LLMGenerationRequest(
            providerID: .anthropic,
            adapterID: .anthropicMessages,
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
            providerSpecificOptions: [
                "json_schema": .object([
                    "name": .string("answer"),
                    "strict": .boolean(true),
                    "schema": .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ])
                ]),
                "custom_flag": .integer(7)
            ]
        )

        try OpenAIEncoding.applyMappedOptions(
            options,
            to: &body,
            parameters: [
                LLMActiveParameter(parameterID: .responseFormat, mapping: LLMParameterMapping(
                    adapterID: .openAIChatCompletions,
                    parameterID: .responseFormat,
                    encodingKind: .preset,
                    structuredPreset: .openAIChatResponseFormat
                ))
            ]
        )

        let responseFormat = try XCTUnwrap(body["response_format"]?.objectValue)
        XCTAssertEqual(responseFormat.string("type"), "json_schema")
        XCTAssertEqual(responseFormat.object("json_schema")?.string("name"), "answer")
        XCTAssertEqual(body["custom_flag"], .integer(7))
        XCTAssertNil(body["json_schema"])
    }

    func testKeyMappingsReplaceAdapterOwnedFieldEncoding() throws {
        let adapter = OpenAIChatCompletionsAdapter()
        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIChatCompletions,
            modelID: "semantic-model",
            activeParameters: [
                LLMActiveParameter(parameterID: .model, mapping: LLMParameterMapping(
                    adapterID: .openAIChatCompletions,
                    parameterID: .model,
                    encodingKind: .key,
                    wireKey: "model_name"
                )),
                LLMActiveParameter(parameterID: .systemPrompt, mapping: LLMParameterMapping(
                    adapterID: .openAIChatCompletions,
                    parameterID: .systemPrompt,
                    encodingKind: .key,
                    wireKey: "system_prompt"
                )),
                LLMActiveParameter(parameterID: .stream, mapping: LLMParameterMapping(
                    adapterID: .openAIChatCompletions,
                    parameterID: .stream,
                    encodingKind: .key,
                    wireKey: "use_stream"
                ))
            ],
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Answer")])],
            options: LLMGenerationOptions(
                systemPrompt: "Be concise.",
                modelID: "semantic-model",
                streamMode: .enabled
            )
        )

        let body = try adapter.makeBody(for: request, stream: true)

        XCTAssertNil(body["model"])
        XCTAssertNil(body["stream"])
        XCTAssertEqual(body["model_name"], .string("semantic-model"))
        XCTAssertEqual(body["system_prompt"], .string("Be concise."))
        XCTAssertEqual(body["use_stream"], .boolean(true))
        XCTAssertEqual(body.array("messages")?.count, 1)
    }

    func testOpenAIResponsesJsonSchemaEncodingUsesTextFormat() throws {
        let adapter = OpenAIResponsesAdapter()
        let resolved = try Self.resolvedDefaults(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "gpt-test",
            options: LLMGenerationOptions(
                responseFormat: .jsonSchema,
                reasoning: "medium",
                reasoningSummary: "auto",
                providerSpecificOptions: [
                    "json_schema": .object([
                        "name": .string("answer"),
                        "schema": .object(["type": .string("object")])
                    ])
                ]
            )
        )
        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "gpt-test",
            activeParameters: resolved.activeParameters,
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Answer")])],
            options: resolved.options
        )

        let body = try adapter.makeBody(for: request, stream: false)
        let text = try XCTUnwrap(body["text"]?.objectValue)
        let format = try XCTUnwrap(text.object("format"))
        XCTAssertEqual(format.string("type"), "json_schema")
        XCTAssertEqual(format.string("name"), "answer")
        XCTAssertNil(body["json_schema"])
    }

    func testOpenAIResponsesStructuredMappingsMergeSiblingFields() throws {
        let adapter = OpenAIResponsesAdapter()
        let resolved = try Self.resolvedDefaults(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "gpt-5.5",
            options: LLMGenerationOptions(
                responseFormat: .jsonSchema,
                reasoning: "high",
                reasoningSummary: "auto",
                textVerbosity: "high",
                providerSpecificOptions: [
                    "json_schema": .object([
                        "name": .string("answer"),
                        "schema": .object(["type": .string("object")])
                    ])
                ]
            )
        )
        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "gpt-5.5",
            activeParameters: resolved.activeParameters,
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Answer")])],
            options: resolved.options
        )

        let body = try adapter.makeBody(for: request, stream: false)

        XCTAssertEqual(body.object("text")?.object("format")?.string("type"), "json_schema")
        XCTAssertEqual(body.object("text")?.string("verbosity"), "high")
        XCTAssertEqual(body.object("reasoning")?.string("effort"), "high")
        XCTAssertEqual(body.object("reasoning")?.string("summary"), "auto")
    }

    func testOpenAIChatRejectsReservedProviderExtraCollision() {
        let adapter = OpenAIChatCompletionsAdapter()
        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIChatCompletions,
            modelID: "gpt-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Answer")])],
            options: LLMGenerationOptions(providerSpecificOptions: ["messages": .array([])])
        )

        XCTAssertThrowsError(try adapter.makeBody(for: request, stream: true)) { error in
            XCTAssertEqual(error as? LLMProviderError, .requestEncoding("providerSpecificOptions.messages cannot override a reserved request field."))
        }
    }

    func testOpenAIResponsesRejectsReservedProviderExtraCollision() {
        let adapter = OpenAIResponsesAdapter()
        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "gpt-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Answer")])],
            options: LLMGenerationOptions(providerSpecificOptions: ["text": .object(["format": .object(["type": .string("text")])])])
        )

        XCTAssertThrowsError(try adapter.makeBody(for: request, stream: false)) { error in
            XCTAssertEqual(error as? LLMProviderError, .requestEncoding("providerSpecificOptions.text cannot override a reserved request field."))
        }
    }

    func testJsonSchemaEncodingRequiresProviderExtraObject() {
        var body: [String: JSONValue] = [:]
        let options = LLMGenerationOptions(responseFormat: .jsonSchema)

        XCTAssertThrowsError(try OpenAIEncoding.applyMappedOptions(
            options,
            to: &body,
            parameters: [
                LLMActiveParameter(parameterID: .responseFormat, mapping: LLMParameterMapping(
                    adapterID: .openAIChatCompletions,
                    parameterID: .responseFormat,
                    encodingKind: .preset,
                    structuredPreset: .openAIChatResponseFormat
                ))
            ]
        )) { error in
            XCTAssertEqual(error as? LLMProviderError, .requestEncoding("response_format json_schema requires providerSpecificOptions.json_schema object."))
        }
    }

    func testModernOpenAIChatMapsMaxOutputTokensToMaxCompletionTokens() throws {
        let adapter = OpenAIChatCompletionsAdapter()
        let resolved = try Self.resolvedDefaults(
            providerID: .openAIPlatform,
            adapterID: .openAIChatCompletions,
            modelID: "gpt-5.4-nano",
            options: LLMGenerationOptions(
                temperature: 0.7,
                topP: 0.9,
                maxOutputTokens: 16,
                stop: ["END"],
                reasoning: "low"
            )
        )
        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIChatCompletions,
            modelID: "gpt-5.4-nano",
            activeParameters: resolved.activeParameters,
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "ok")])],
            options: resolved.options
        )

        let body = try adapter.makeBody(for: request, stream: false)
        XCTAssertEqual(body["max_completion_tokens"], .integer(16))
        XCTAssertEqual(body["reasoning_effort"], .string("low"))
        XCTAssertNil(body["max_tokens"])
        XCTAssertEqual(body["temperature"], .number(0.7))
        XCTAssertEqual(body["top_p"], .number(0.9))
        XCTAssertEqual(body["stop"], .array([.string("END")]))
    }

    func testLegacyOpenAIChatMapsMaxOutputTokensToMaxTokens() throws {
        let adapter = OpenAIChatCompletionsLegacyAdapter()
        let resolved = try Self.resolvedDefaults(
            providerID: .custom,
            adapterID: .openAIChatCompletionsLegacy,
            modelID: "gpt-4.1-nano",
            options: LLMGenerationOptions(maxOutputTokens: 16)
        )
        let request = LLMGenerationRequest(
            providerID: .custom,
            adapterID: .openAIChatCompletionsLegacy,
            modelID: "gpt-4.1-nano",
            activeParameters: resolved.activeParameters,
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "ok")])],
            options: resolved.options
        )

        let body = try adapter.makeBody(for: request, stream: false)
        XCTAssertEqual(body["max_tokens"], .integer(16))
        XCTAssertNil(body["max_completion_tokens"])
    }

    func testOpenRouterEncodesNestedReasoningAndTopK() throws {
        let adapter = OpenRouterChatCompletionsAdapter()
        let resolved = try Self.resolvedDefaults(
            providerID: .openRouter,
            adapterID: .openRouterChatCompletions,
            modelID: "openai/gpt-5.4-nano",
            options: LLMGenerationOptions(
                maxOutputTokens: 32,
                topK: 40,
                reasoning: "high"
            )
        )
        let request = LLMGenerationRequest(
            providerID: .openRouter,
            adapterID: .openRouterChatCompletions,
            modelID: "openai/gpt-5.4-nano",
            activeParameters: resolved.activeParameters,
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "ok")])],
            options: resolved.options
        )

        let body = try adapter.makeBody(for: request, stream: false)
        XCTAssertEqual(body["max_completion_tokens"], .integer(32))
        XCTAssertEqual(body["top_k"], .integer(40))
        XCTAssertEqual(body.object("reasoning")?.string("effort"), "high")
        XCTAssertNil(body["reasoning_effort"])
    }

    func testCodexResponsesUsesMappedRouteParametersFromDefaults() throws {
        let adapter = OpenAIResponsesAdapter()
        let resolved = try Self.resolvedDefaults(
            providerID: .openAICodexChatGPTSubscription,
            adapterID: .openAIResponses,
            modelID: "gpt-5.4-mini",
            options: LLMGenerationOptions(streamMode: .enabled)
        )
        let request = LLMGenerationRequest(
            providerID: .openAICodexChatGPTSubscription,
            adapterID: .openAIResponses,
            modelID: "gpt-5.4-mini",
            activeParameters: resolved.activeParameters,
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "ok")])],
            options: resolved.options
        )

        let body = try adapter.makeBody(for: request, stream: true)
        XCTAssertEqual(body["stream"], .boolean(true))
        XCTAssertEqual(body["store"], .boolean(false))
        XCTAssertNil(body["max_output_tokens"])
    }

    func testAnthropicMessagesUsesRequiredDefaultMaxTokens() throws {
        let adapter = AnthropicMessagesAdapter()
        let resolved = try Self.resolvedDefaults(
            providerID: .anthropic,
            adapterID: .anthropicMessages,
            modelID: "claude-test",
            options: LLMGenerationOptions(maxOutputTokens: AppDefaults.Anthropic.max_tokens)
        )
        let request = LLMGenerationRequest(
            providerID: .anthropic,
            adapterID: .anthropicMessages,
            modelID: "claude-test",
            activeParameters: resolved.activeParameters,
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "ok")])],
            options: resolved.options
        )

        let body = try adapter.makeBody(for: request, stream: false)
        XCTAssertEqual(body["max_tokens"], .integer(AppDefaults.Anthropic.max_tokens))
    }

    func testAnthropicRejectsInvalidToolArgumentJSON() {
        let adapter = AnthropicMessagesAdapter()
        let request = LLMGenerationRequest(
            providerID: .anthropic,
            adapterID: .anthropicMessages,
            modelID: "claude-test",
            messages: [
                LLMMessage(
                    role: "assistant",
                    content: [],
                    toolCalls: [
                        LLMToolCall(id: "tool_1", callID: "tool_1", index: 0, name: "lookup", argumentsJSON: "{")
                    ]
                )
            ]
        )

        XCTAssertThrowsError(try adapter.anthropicMessages(from: request)) { error in
            XCTAssertEqual(error as? LLMProviderError, .requestEncoding("Anthropic tool_use arguments must be valid JSON object."))
        }
    }

    func testAnthropicRejectsNonObjectToolArgumentJSON() {
        let adapter = AnthropicMessagesAdapter()
        let request = LLMGenerationRequest(
            providerID: .anthropic,
            adapterID: .anthropicMessages,
            modelID: "claude-test",
            messages: [
                LLMMessage(
                    role: "assistant",
                    content: [],
                    toolCalls: [
                        LLMToolCall(id: "tool_1", callID: "tool_1", index: 0, name: "lookup", argumentsJSON: "[]")
                    ]
                )
            ]
        )

        XCTAssertThrowsError(try adapter.anthropicMessages(from: request)) { error in
            XCTAssertEqual(error as? LLMProviderError, .requestEncoding("Anthropic tool_use arguments must decode to a JSON object."))
        }
    }

    func testOpenRouterReasoningPresetIsLegalOnlyForOpenRouter() throws {
        let valid = LLMGenerationRequest(
            providerID: .openRouter,
            adapterID: .openRouterChatCompletions,
            modelID: "openai/gpt-test",
            activeParameters: [
                LLMActiveParameter(parameterID: .reasoningEffort, mapping: LLMParameterMapping(
                    adapterID: .openRouterChatCompletions,
                    parameterID: .reasoningEffort,
                    encodingKind: .preset,
                    structuredPreset: .openRouterReasoning
                ))
            ],
            messages: [],
            options: LLMGenerationOptions(reasoning: "high")
        )
        XCTAssertNoThrow(try valid.validateActiveParameterMappings())

        for adapterID in LLMAdapterID.allCases where adapterID != .openRouterChatCompletions {
            let invalid = LLMGenerationRequest(
                providerID: adapterID == .foundationModels ? .appleIntelligence : .custom,
                adapterID: adapterID,
                modelID: "test-model",
                activeParameters: [
                    LLMActiveParameter(parameterID: .reasoningEffort, mapping: LLMParameterMapping(
                        adapterID: adapterID,
                        parameterID: .reasoningEffort,
                        encodingKind: .preset,
                        structuredPreset: .openRouterReasoning
                    ))
                ],
                messages: [],
                options: LLMGenerationOptions(reasoning: "high")
            )
            XCTAssertThrowsError(try invalid.validateActiveParameterMappings(), adapterID.rawValue)
        }
    }

    func testActiveParameterMappingValidationRejectsInvalidDefinitions() {
        func request(
            adapterID: LLMAdapterID = .openAIChatCompletions,
            parameters: [LLMActiveParameter]
        ) -> LLMGenerationRequest {
            LLMGenerationRequest(
                providerID: .custom,
                adapterID: adapterID,
                modelID: "test-model",
                activeParameters: parameters,
                messages: [],
                options: LLMGenerationOptions(topP: 0.9, maxOutputTokens: 16)
            )
        }

        let maxTokens = LLMActiveParameter(parameterID: .maxOutputTokens, mapping: LLMParameterMapping(
            adapterID: .openAIChatCompletions,
            parameterID: .maxOutputTokens,
            wireKey: "max_completion_tokens"
        ))
        XCTAssertThrowsError(try request(parameters: [maxTokens, maxTokens]).validateActiveParameterMappings())

        XCTAssertThrowsError(try request(parameters: [
            LLMActiveParameter(parameterID: .maxOutputTokens, mapping: LLMParameterMapping(
                adapterID: .openAIResponses,
                parameterID: .maxOutputTokens,
                wireKey: "max_output_tokens"
            ))
        ]).validateActiveParameterMappings())

        XCTAssertThrowsError(try request(parameters: [
            LLMActiveParameter(parameterID: .maxOutputTokens, mapping: LLMParameterMapping(
                adapterID: .openAIChatCompletions,
                parameterID: .topP,
                wireKey: "top_p"
            ))
        ]).validateActiveParameterMappings())

        XCTAssertThrowsError(try request(parameters: [
            LLMActiveParameter(parameterID: .maxOutputTokens, mapping: LLMParameterMapping(
                adapterID: .openAIChatCompletions,
                parameterID: .maxOutputTokens,
                encodingKind: .key,
                wireKey: ""
            ))
        ]).validateActiveParameterMappings())

        XCTAssertThrowsError(try request(parameters: [
            LLMActiveParameter(parameterID: .reasoningEffort, mapping: LLMParameterMapping(
                adapterID: .openAIChatCompletions,
                parameterID: .reasoningEffort,
                encodingKind: .preset,
                structuredPreset: .anthropicThinking
            ))
        ]).validateActiveParameterMappings())

        XCTAssertThrowsError(try request(adapterID: .foundationModels, parameters: [
            LLMActiveParameter(parameterID: .topP, mapping: LLMParameterMapping(
                adapterID: .foundationModels,
                parameterID: .topP,
                encodingKind: .adapter
            ))
        ]).validateActiveParameterMappings())
    }

    private static func resolvedDefaults(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        modelID: String,
        options: LLMGenerationOptions
    ) throws -> LLMResolvedGenerationParameters {
        let profile = LLMModelProfileResolver(fallbackContextSize: 4096).resolve(
            providerID: providerID,
            adapterID: adapterID,
            modelID: modelID,
            metadata: nil
        )
        let providedParameterIDs = options.testProvidedParameterIDs
        return try LLMGenerationOptionsResolver.resolve(
            options: options,
            conversationPreferences: Dictionary(uniqueKeysWithValues: providedParameterIDs.map {
                ($0.rawValue, true)
            }),
            providedParameterIDs: providedParameterIDs,
            parameterProfiles: profile.parameters
        )
    }
}
