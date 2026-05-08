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
        XCTAssertFalse(conversation.options.systemPrompt.isEmpty)
        XCTAssertEqual(conversation.options.temperature, 0.7)
        XCTAssertEqual(conversation.options.maxOutputTokens, 1000)
        XCTAssertEqual(conversation.options.selectedModelID, "test-model")
    }
    
    func testParameterEdgeCases() {
        let conversation = testEnv.createConversation()
        XCTAssertNil(conversation.options.temperature)
        XCTAssertNil(conversation.options.maxOutputTokens)
        XCTAssertNil(conversation.options.parameterValue(.reasoningEffort))
        XCTAssertEqual(conversation.options.parameterValue(.systemPrompt), .string(""))
    }
}
