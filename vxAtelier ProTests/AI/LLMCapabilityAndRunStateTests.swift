import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMCapabilityAndRunStateTests: XCTestCase {
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
}
