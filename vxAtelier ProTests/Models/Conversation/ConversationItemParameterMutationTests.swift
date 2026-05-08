import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ConversationItemParameterMutationTests: XCTestCase {
    private var testEnv: TestEnvironment!

    override func setUp() {
        super.setUp()
        testEnv = TestEnvironment()
    }

    override func tearDown() {
        testEnv = nil
        super.tearDown()
    }

    func testUpdateTypedParameters() {
        let optionsFactory = ConversationOptionsFactory()
        let options = optionsFactory.create()
        let conversation = ConversationItem(timestamp: Date(), title: "Parameter Update Test", options: options)
        let newSystemPrompt = "New system prompt"
        let newTemperature = 0.9
        let newMaxTokens = 2000
        let newModel = "new-test-model"

        conversation.options.setParameterValue(.systemPrompt, value: .string(newSystemPrompt))
        conversation.options.setParameterValue(.temperature, value: .number(newTemperature))
        conversation.options.setParameterValue(.maxOutputTokens, value: .integer(newMaxTokens))
        conversation.options.setParameterValue(.model, value: .string(newModel))

        XCTAssertEqual(conversation.options.systemPrompt, newSystemPrompt)
        XCTAssertEqual(conversation.options.temperature, newTemperature)
        XCTAssertEqual(conversation.options.maxOutputTokens, newMaxTokens)
        XCTAssertEqual(conversation.options.modelOverride, newModel)
    }

    func testTypedParameterValueConversions() {
        let options = ConversationOptions(avatarImageData: nil, apiConfiguration: nil)
        options.setParameterValue(.stopSequences, value: .string("END\nSTOP"))
        options.setParameterValue(.responseFormat, value: .string("json_schema"))
        options.setParameterValue(.reasoningEffort, value: .string("high"))
        options.setParameterValue(.serviceTier, value: .string("priority"))

        XCTAssertEqual(options.stopSequences, ["END", "STOP"])
        XCTAssertEqual(options.responseFormat, .jsonSchema)
        XCTAssertEqual(options.reasoning, "high")
        XCTAssertEqual(options.serviceTier, "priority")
        XCTAssertEqual(options.parameterValue(.stopSequences), .string("END\nSTOP"))
        XCTAssertEqual(options.parameterValue(.responseFormat), .string("json_schema"))
    }
}
