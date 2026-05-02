import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ConversationItemInitializationTests: XCTestCase {
    private var testEnv: TestEnvironment!
    
    override func setUp() {
        super.setUp()
        testEnv = TestEnvironment()
    }
    
    override func tearDown() {
        testEnv = nil
        super.tearDown()
    }
    
    func testInitialization() {
        let title = "Test Conversation"
        let options = ConversationOptions()
        let timestamp = Date()
        let conversation = ConversationItem(timestamp: timestamp, title: title, options: options)
        XCTAssertEqual(conversation.title, title)
        XCTAssertEqual(conversation.timestamp, timestamp)
        XCTAssertTrue(conversation.turns.isEmpty)
        XCTAssertEqual(conversation.status, .active)
        XCTAssertEqual(conversation.purpose, .user)
        XCTAssertEqual(conversation.tokenCount, 0)
        XCTAssertNil(conversation.project)
    }
    
    func testInitializationWithParameters() {
        let optionsFactory = ConversationOptionsFactory()
        let options = optionsFactory.create()
        let conversation = ConversationItem(timestamp: Date(), title: "Test With Parameters", options: options)
        XCTAssertNotNil(conversation.options.getParameterValue(name: "system_prompt"))
        XCTAssertTrue(conversation.options.hasParameterValue(name: "system_prompt"))
        let temperature: Double = conversation.options.getParameterValue(name: "temperature", defaultValue: 0.0)
        XCTAssertEqual(temperature, 0.7)
        let maxTokens: Int = conversation.options.getParameterValue(name: "max_output_tokens", defaultValue: 0)
        XCTAssertEqual(maxTokens, 1000)
        let model: String = conversation.options.getParameterValue(name: "model", defaultValue: "")
        XCTAssertEqual(model, "test-model")
    }
    
    func testInitializationWithCustomParameters() {
        let optionsFactory = ConversationOptionsFactory()
        let options = optionsFactory.createWithCustomPrompt("Custom system prompt")
        options.setParameterValue(name: "temperature", value: 0.9)
        options.setParameterValue(name: "max_output_tokens", value: 2000)
        let conversation = ConversationItem(timestamp: Date(), title: "Test Custom Parameters", options: options)
        let prompt: String = conversation.options.getParameterValue(name: "system_prompt", defaultValue: "")
        XCTAssertEqual(prompt, "Custom system prompt")
        let temperature: Double = conversation.options.getParameterValue(name: "temperature", defaultValue: 0.0)
        XCTAssertEqual(temperature, 0.9)
        let maxTokens: Int = conversation.options.getParameterValue(name: "max_output_tokens", defaultValue: 0)
        XCTAssertEqual(maxTokens, 2000)
    }
}
