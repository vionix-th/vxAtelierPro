import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

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

    func testSemanticParameterValuesAreTypedFields() {
        let options = ConversationOptions()
        options.setParameterValue(.systemPrompt, value: .string("System"))
        options.setParameterValue(.temperature, value: .number(0.8))
        options.setParameterValue(.maxOutputTokens, value: .integer(2048))
        options.setParameterValue(.model, value: .string("unit-model"))

        XCTAssertEqual(options.systemPrompt, "System")
        XCTAssertEqual(options.temperature, 0.8)
        XCTAssertEqual(options.maxOutputTokens, 2048)
        XCTAssertEqual(options.selectedModelID, "unit-model")
        XCTAssertEqual(options.parameterValue(.systemPrompt), .string("System"))
        XCTAssertEqual(options.parameterValue(.temperature), .number(0.8))
        XCTAssertEqual(options.parameterValue(.maxOutputTokens), .integer(2048))
        XCTAssertEqual(options.parameterValue(.model), .string("unit-model"))
    }

    func testParameterEnablementOverridesDoNotClearTypedValues() {
        let options = ConversationOptions()
        options.temperature = 0.9
        let mapping = LLMParameterMappingDescriptor(
            adapterID: .openAIChatCompletions,
            semanticParameterID: .temperature,
            wireKey: "temperature"
        )

        XCTAssertTrue(options.isParameterEnabled(.temperature, mapping: mapping))
        options.setParameterEnabled(.temperature, enabled: false)
        XCTAssertFalse(options.isParameterEnabled(.temperature, mapping: mapping))
        XCTAssertEqual(options.temperature, 0.9)
    }

    func testGenerationOptionsOmitDisabledOptionalParameters() {
        let options = ConversationOptions()
        options.temperature = 0.9
        options.maxOutputTokens = 1000
        options.setParameterEnabled(.temperature, enabled: false)
        let mappings: [LLMParameterID: LLMParameterMappingDescriptor] = [
            .temperature: LLMParameterMappingDescriptor(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .temperature,
                wireKey: "temperature"
            ),
            .maxOutputTokens: LLMParameterMappingDescriptor(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .maxOutputTokens,
                wireKey: "max_tokens"
            )
        ]

        let generationOptions = options.generationOptions(
            resolvedModelID: "model",
            mappings: mappings
        )

        XCTAssertNil(generationOptions.temperature)
        XCTAssertEqual(generationOptions.maxOutputTokens, 1000)
        XCTAssertEqual(options.temperature, 0.9)
    }

    func testProjectionUsesSemanticPresentationAndMappings() {
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test",
            defaultModel: "gpt-4.1-nano",
            providerID: .openAIPlatform
        )
        config.defaultAdapterIDEnum = .openAIChatCompletions
        let options = ConversationOptions(apiConfiguration: config)
        options.temperature = 0.7

        let controls = ConversationParameterProjection.controls(
            for: options,
            apiConfiguration: config
        )
        let temperature = controls.first { $0.parameterID == .temperature }

        XCTAssertEqual(temperature?.valueType, .float)
        XCTAssertEqual(temperature?.controlType, .slider)
        XCTAssertEqual(temperature?.displayName, AiParameterPresentationCatalog.displayName(for: .temperature))
        XCTAssertEqual(temperature?.value, .number(0.7))
        XCTAssertTrue(temperature?.isEnabled ?? false)
    }

    func testToolEnableDisable() {
        let options = ConversationOptions()
        options.setToolEnabled("web_search", enabled: true)
        XCTAssertTrue(options.isToolEnabled("web_search"))
        options.setToolEnabled("web_search", enabled: false)
        XCTAssertFalse(options.isToolEnabled("web_search"))
    }
}
