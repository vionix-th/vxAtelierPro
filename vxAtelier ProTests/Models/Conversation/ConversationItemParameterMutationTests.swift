import XCTest
import SwiftData
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
    
    func testUpdateParameters() {
        let optionsFactory = ConversationOptionsFactory()
        let options = optionsFactory.create()
        let conversation = ConversationItem(timestamp: Date(), title: "Parameter Update Test", options: options)
        let newSystemPrompt = "New system prompt"
        let newTemperature = 0.9
        let newMaxTokens = 2000
        let newModel = "new-test-model"
        if let param = conversation.options.parameters.first(where: { $0.name == "system_prompt" }) {
            param.setValue(newSystemPrompt)
        }
        if let param = conversation.options.parameters.first(where: { $0.name == "temperature" }) {
            param.setValue(newTemperature)
        }
        if let param = conversation.options.parameters.first(where: { $0.name == "max_output_tokens" }) {
            param.setValue(newMaxTokens)
        }
        if let param = conversation.options.parameters.first(where: { $0.name == "model" }) {
            param.setValue(newModel)
        }
        XCTAssertEqual(conversation.options.getParameterValue(name: "system_prompt", defaultValue: ""), newSystemPrompt)
        XCTAssertEqual(conversation.options.getParameterValue(name: "temperature", defaultValue: 0.0), newTemperature)
        XCTAssertEqual(conversation.options.getParameterValue(name: "max_output_tokens", defaultValue: 0), newMaxTokens)
        XCTAssertEqual(conversation.options.getParameterValue(name: "model", defaultValue: ""), newModel)
    }
    
    func testAddNewParameter() {
        let options = ConversationOptions(avatarImageData: nil, apiConfiguration: nil, shouldSetupParameters: false)
        let conversation = ConversationItem(timestamp: Date(), title: "Add Parameter Test", options: options)
        let stringParamName = "test_string"
        let stringValue = "test value"
        let stringParam = AiRequestArgument(name: stringParamName, displayName: "Test String", description: "A test string parameter", required: true, valueType: .string, controlType: .textField, defaultValue: stringValue)
        let floatParamName = "test_float"
        let floatValue = 42.0
        let floatParam = AiRequestArgument(name: floatParamName, displayName: "Test Float", description: "A test float parameter", required: true, valueType: .float, controlType: .slider, minValue: 0.0, maxValue: 100.0, step: 0.1, defaultValue: floatValue)
        let intParamName = "test_int"
        let intValue = 42
        let intParam = AiRequestArgument(name: intParamName, displayName: "Test Int", description: "A test integer parameter", required: true, valueType: .integer, controlType: .stepper, minValue: 0, maxValue: 100, step: 1, defaultValue: intValue)
        let boolParamName = "test_bool"
        let boolValue = true
        let boolParam = AiRequestArgument(name: boolParamName, displayName: "Test Bool", description: "A test boolean parameter", required: true, valueType: .boolean, controlType: .toggle, defaultValue: boolValue)
        conversation.options.parameters = [stringParam, floatParam, intParam, boolParam]
        XCTAssertTrue(conversation.options.hasParameterValue(name: stringParamName))
        XCTAssertEqual(stringParam.stringValue, stringValue)
        let stringParam2 = conversation.options.parameters.first { $0.name == stringParamName }!
        XCTAssertEqual(stringParam2.stringValue, stringValue)
        XCTAssertEqual(stringParam2.paramDescription, "A test string parameter")
        XCTAssertTrue(conversation.options.hasParameterValue(name: floatParamName))
        XCTAssertEqual(floatParam.floatValue, floatValue)
        let floatParam2 = conversation.options.parameters.first { $0.name == floatParamName }!
        XCTAssertEqual(floatParam2.floatValue, floatValue)
        XCTAssertEqual(floatParam2.minValue, 0.0)
        XCTAssertEqual(floatParam2.maxValue, 100.0)
        XCTAssertEqual(floatParam2.step, 0.1)
        XCTAssertTrue(conversation.options.hasParameterValue(name: intParamName))
        XCTAssertEqual(intParam.intValue, intValue)
        let intParam2 = conversation.options.parameters.first { $0.name == intParamName }!
        XCTAssertEqual(intParam2.intValue, intValue)
        XCTAssertEqual(intParam2.minValue, 0)
        XCTAssertEqual(intParam2.maxValue, 100)
        XCTAssertEqual(intParam2.step, 1)
        XCTAssertTrue(conversation.options.hasParameterValue(name: boolParamName))
        XCTAssertEqual(boolParam.boolValue, boolValue)
        let boolParam2 = conversation.options.parameters.first { $0.name == boolParamName }!
        XCTAssertEqual(boolParam2.boolValue, boolValue)
        XCTAssertEqual(stringParam.valueType, AiArgumentValueType.string.rawValue)
        XCTAssertEqual(stringParam.controlType, AiArgumentControlType.textField.rawValue)
        XCTAssertEqual(stringParam.displayName, "Test String")
        XCTAssertEqual(stringParam.paramDescription, "A test string parameter")
        XCTAssertTrue(stringParam.required)
    }
}
