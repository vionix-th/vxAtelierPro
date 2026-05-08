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
        XCTAssertFalse(conversation.options.systemPrompt.isEmpty)
        XCTAssertEqual(conversation.options.temperature, 0.7)
        XCTAssertEqual(conversation.options.maxOutputTokens, 1000)
        XCTAssertEqual(conversation.options.modelOverride, "test-model")
    }
    
    func testInitializationWithCustomParameters() {
        let optionsFactory = ConversationOptionsFactory()
        let options = optionsFactory.createWithCustomPrompt("Custom system prompt")
        options.setParameterValue(.temperature, value: .number(0.9))
        options.setParameterValue(.maxOutputTokens, value: .integer(2000))
        let conversation = ConversationItem(timestamp: Date(), title: "Test Custom Parameters", options: options)
        XCTAssertEqual(conversation.options.systemPrompt, "Custom system prompt")
        XCTAssertEqual(conversation.options.temperature, 0.9)
        XCTAssertEqual(conversation.options.maxOutputTokens, 2000)
    }
}
