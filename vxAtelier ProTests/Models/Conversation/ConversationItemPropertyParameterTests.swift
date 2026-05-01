import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ConversationItemPropertyParameterTests: XCTestCase {
    private var testEnv: TestEnvironment!
    
    override func setUp() {
        super.setUp()
        testEnv = TestEnvironment()
    }
    
    override func tearDown() {
        testEnv = nil
        super.tearDown()
    }
    
    func testPropertyAccess() {
        let conversation = testEnv.createConversation()
        XCTAssertNotNil(conversation.timestamp)
        XCTAssertFalse(conversation.title.isEmpty)
        XCTAssertNotNil(conversation.options)
        XCTAssertEqual(conversation.status, .active)
        XCTAssertEqual(conversation.purpose, .user)
        XCTAssertEqual(conversation.tokenCount, 0)
        XCTAssertEqual(conversation.usedTokenCount, 0)
        XCTAssertTrue(conversation.turns.isEmpty)
        XCTAssertNil(conversation.project)
    }
    
    func testParameterAccess() {
        let optionsFactory = ConversationOptionsFactory()
        let options = optionsFactory.create()
        let conversation = ConversationItem(timestamp: Date(), title: "Parameter Access Test", options: options)
        XCTAssertTrue(conversation.options.hasParameterValue(name: "system_prompt"))
        XCTAssertTrue(conversation.options.hasParameterValue(name: "temperature"))
        XCTAssertTrue(conversation.options.hasParameterValue(name: "max_tokens"))
        XCTAssertTrue(conversation.options.hasParameterValue(name: "model"))
        let systemPrompt: String = conversation.options.getParameterValue(name: "system_prompt", defaultValue: "")
        XCTAssertFalse(systemPrompt.isEmpty)
        let temperature: Double = conversation.options.getParameterValue(name: "temperature", defaultValue: 0.0)
        XCTAssertEqual(temperature, 0.7)
        let maxTokens: Int = conversation.options.getParameterValue(name: "max_tokens", defaultValue: 0)
        XCTAssertEqual(maxTokens, 1000)
        let model: String = conversation.options.getParameterValue(name: "model", defaultValue: "")
        XCTAssertEqual(model, "test-model")
    }
    
    func testParameterEdgeCases() {
        let conversation = testEnv.createConversation()
        XCTAssertFalse(conversation.options.hasParameterValue(name: "non_existent_param"))
        let defaultValue = "default"
        let nonExistentValue: String = conversation.options.getParameterValue(name: "non_existent_param", defaultValue: defaultValue)
        XCTAssertEqual(nonExistentValue, defaultValue)
        let temperatureAsString: String = conversation.options.getParameterValue(name: "temperature", defaultValue: "wrong type")
        XCTAssertEqual(temperatureAsString, "wrong type")
        let maxTokensAsDouble: Double = conversation.options.getParameterValue(name: "max_tokens", defaultValue: -1.0)
        XCTAssertEqual(maxTokensAsDouble, -1.0)
    }
}
