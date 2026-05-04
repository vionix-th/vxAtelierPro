import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMProviderAdapterEncodingTests: XCTestCase {
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
}
