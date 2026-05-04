import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMCoreTypesTests: XCTestCase {
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
}
