import XCTest
import SwiftData
@testable import vxAtelier_Pro_debug

@MainActor
final class ConversationOptionsAndArgumentTests: XCTestCase {
    private var testEnv: TestEnvironment!

    override func setUp() {
        super.setUp()
        testEnv = TestEnvironment()
    }

    override func tearDown() {
        testEnv = nil
        super.tearDown()
    }

    // MARK: - Parameter Management
    func testAddAndRemoveParameters() throws {
        let options = ConversationOptions()
        let param = AiRequestArgument(
            name: "temperature",
            displayName: "Temperature",
            valueType: .float,
            controlType: .slider,
            minValue: 0.0,
            maxValue: 2.0,
            step: 0.01,
            defaultValue: 1.0
        )
        options.parameters.append(param)
        XCTAssertEqual(options.parameters.count, 1)
        options.parameters.removeAll()
        XCTAssertEqual(options.parameters.count, 0)
    }

    // MARK: - API/Model/Voice/Search Config
    func testApiConfigurationAssignment() throws {
        let options = ConversationOptions()
        let apiConfig = APIConfigurationItem(name: "OpenAI", apiKey: "sk-test", baseURL: "https://api.openai.com", chatCompletionsEndpoint: "/v1/chat/completions", modelsEndpoint: "/v1/models")
        options.apiConfiguration = apiConfig
        XCTAssertEqual(options.apiConfiguration?.name, "OpenAI")
    }

    // MARK: - Edge Cases
    func testRequiredParameterEnforcement() throws {
        let options = ConversationOptions()
        let param = AiRequestArgument(
            name: "system_prompt",
            displayName: "System Prompt",
            required: true,
            valueType: .string,
            controlType: .textField
        )
        options.parameters.append(param)
        XCTAssertTrue(options.parameters.first?.required ?? false)
        // Required parameter should be enabled by default
        XCTAssertTrue(options.parameters.first?.isEnabled ?? false)
    }

    func testOptionalParameterToggle() throws {
        let options = ConversationOptions()
        let param = AiRequestArgument(
            name: "top_p",
            displayName: "Top P",
            required: false,
            valueType: .float,
            controlType: .slider
        )
        options.parameters.append(param)
        XCTAssertFalse(options.parameters.first?.required ?? true)
        XCTAssertFalse(options.parameters.first?.isEnabled ?? true)
        options.parameters.first?.toggleEnabled()
        XCTAssertTrue(options.parameters.first?.isEnabled ?? false)
    }

    func testParameterValueTypeEnforcement() throws {
        let argString = AiRequestArgument(name: "s", displayName: "S", required: true, valueType: .string, controlType: .textField, defaultValue: "abc")
        XCTAssertEqual(argString.stringValue ?? "", "abc")
        let argInt = AiRequestArgument(name: "i", displayName: "I", required: true, valueType: .integer, controlType: .stepper, defaultValue: 42)
        XCTAssertEqual(argInt.intValue ?? 0, 42)
        let argFloat = AiRequestArgument(name: "f", displayName: "F", required: true, valueType: .float, controlType: .slider, defaultValue: 3.14)
        XCTAssertEqual(argFloat.floatValue ?? 1.23 , 3.14)
        let argBool = AiRequestArgument(name: "b", displayName: "B", required: true, valueType: .boolean, controlType: .toggle, defaultValue: true)
        XCTAssertEqual(argBool.boolValue ?? false, true)
    }

    // MARK: - Tool Config
    func testToolEnableDisable() throws {
        let options = ConversationOptions()
        options.setToolEnabled("web_search", enabled: true)
        XCTAssertTrue(options.isToolEnabled("web_search"))
        options.setToolEnabled("web_search", enabled: false)
        XCTAssertFalse(options.isToolEnabled("web_search"))
    }
}
