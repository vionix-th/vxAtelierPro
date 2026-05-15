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

    func testParameterInclusionPreferencesDoNotClearTypedValues() {
        let options = ConversationOptions()
        options.temperature = 0.9
        let availability = LLMParameterAvailabilityDescriptor(
            adapterID: .openAIChatCompletions,
            semanticParameterID: .temperature
        )

        XCTAssertTrue(LLMParameterAvailabilityResolver.isParameterSendable(
            .temperature,
            value: options.parameterValue(.temperature),
            conversationPreference: options.parameterInclusionPreference(.temperature),
            modelAvailability: availability
        ))
        options.setParameterEnabled(.temperature, enabled: false)
        XCTAssertFalse(LLMParameterAvailabilityResolver.isParameterSendable(
            .temperature,
            value: options.parameterValue(.temperature),
            conversationPreference: options.parameterInclusionPreference(.temperature),
            modelAvailability: availability
        ))
        XCTAssertEqual(options.temperature, 0.9)
    }

    func testGenerationOptionsOmitDisabledOptionalParameters() {
        let options = ConversationOptions()
        options.temperature = 0.9
        options.maxOutputTokens = 1000
        options.setParameterEnabled(.temperature, enabled: false)
        let modelAvailability: [LLMParameterID: LLMParameterAvailabilityDescriptor] = [
            .temperature: LLMParameterAvailabilityDescriptor(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .temperature,
                defaultValue: .number(0.4)
            ),
            .maxOutputTokens: LLMParameterAvailabilityDescriptor(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .maxOutputTokens
            )
        ]

        let generationOptions = LLMParameterAvailabilityResolver.resolvedOptions(
            from: options.generationOptions(resolvedModelID: "model"),
            conversationPreferences: options.parameterInclusionPreferences,
            modelAvailability: modelAvailability
        )
        let sendableAvailability = LLMParameterAvailabilityResolver.sendableModelAvailability(
            for: options.generationOptions(resolvedModelID: "model"),
            conversationPreferences: options.parameterInclusionPreferences,
            modelAvailability: modelAvailability
        )

        XCTAssertNil(generationOptions.temperature)
        XCTAssertNil(sendableAvailability[.temperature])
        XCTAssertEqual(generationOptions.maxOutputTokens, 1000)
        XCTAssertEqual(options.temperature, 0.9)
    }

    func testMandatoryParameterCannotBeDisabledByConversationPreference() {
        let options = ConversationOptions()
        options.maxOutputTokens = 1000
        options.setParameterEnabled(.maxOutputTokens, enabled: false)
        let modelAvailability: [LLMParameterID: LLMParameterAvailabilityDescriptor] = [
            .maxOutputTokens: LLMParameterAvailabilityDescriptor(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .maxOutputTokens,
                isRequired: true
            )
        ]

        let generationOptions = LLMParameterAvailabilityResolver.resolvedOptions(
            from: options.generationOptions(resolvedModelID: "model"),
            conversationPreferences: options.parameterInclusionPreferences,
            modelAvailability: modelAvailability
        )
        let sendableAvailability = LLMParameterAvailabilityResolver.sendableModelAvailability(
            for: options.generationOptions(resolvedModelID: "model"),
            conversationPreferences: options.parameterInclusionPreferences,
            modelAvailability: modelAvailability
        )

        XCTAssertEqual(generationOptions.maxOutputTokens, 1000)
        XCTAssertNotNil(sendableAvailability[.maxOutputTokens])
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
        config.models = [ModelItem(modelID: "gpt-4.1-nano", apiConfiguration: config)]
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

    func testAllSemanticParametersHaveConversationConversionCoverage() {
        let options = ConversationOptions()

        for parameterID in LLMParameterID.allCases {
            options.setParameterValue(parameterID, value: Self.sampleValue(for: parameterID))

            XCTAssertEqual(options.parameterValue(parameterID), Self.expectedConversationValue(for: parameterID))
            XCTAssertEqual(parameterID.definition.id, parameterID)
            XCTAssertFalse(AiParameterPresentationCatalog.presentation(for: parameterID).displayName.isEmpty)
            XCTAssertFalse(AiParameterPresentationCatalog.presentation(for: parameterID).description.isEmpty)
        }

        let availability = Dictionary(uniqueKeysWithValues: LLMParameterID.allCases
            .filter(\.isProviderMappable)
            .map {
                ($0, LLMParameterAvailabilityDescriptor(
                    adapterID: .openAIChatCompletions,
                    semanticParameterID: $0
                ))
            })
        let generationOptions = LLMParameterAvailabilityResolver.resolvedOptions(
            from: options.generationOptions(resolvedModelID: "fallback-model"),
            conversationPreferences: options.parameterInclusionPreferences,
            modelAvailability: availability
        )

        for parameterID in LLMParameterID.allCases {
            XCTAssertEqual(generationOptions.jsonValue(for: parameterID), Self.expectedGenerationValue(for: parameterID))
        }
    }

    func testToolEnableDisable() {
        let options = ConversationOptions()
        options.setToolEnabled("web_search", enabled: true)
        XCTAssertTrue(options.isToolEnabled("web_search"))
        options.setToolEnabled("web_search", enabled: false)
        XCTAssertFalse(options.isToolEnabled("web_search"))
    }

    private static func sampleValue(for parameterID: LLMParameterID) -> JSONValue {
        switch parameterID {
        case .model:
            return .string("unit-model")
        case .systemPrompt:
            return .string("System")
        case .maxOutputTokens:
            return .integer(2048)
        case .temperature:
            return .number(0.8)
        case .topP:
            return .number(0.9)
        case .stopSequences:
            return .string("END\nSTOP")
        case .responseFormat:
            return .string("json_schema")
        case .reasoningEffort:
            return .string("high")
        case .reasoningSummary:
            return .string("auto")
        case .serviceTier:
            return .string("priority")
        case .stream:
            return .boolean(true)
        case .store:
            return .boolean(false)
        case .toolChoice:
            return .string("auto")
        case .parallelToolCalls:
            return .boolean(true)
        case .promptCacheKey:
            return .string("cache-key")
        case .previousResponseID:
            return .string("resp_previous")
        case .include:
            return .array([.string("reasoning.encrypted_content")])
        case .textVerbosity:
            return .string("medium")
        case .frequencyPenalty:
            return .number(0.1)
        case .presencePenalty:
            return .number(0.2)
        case .logitBias:
            return .object(["42": .integer(1)])
        case .seed:
            return .integer(123)
        case .user:
            return .string("user-id")
        case .safetyIdentifier:
            return .string("safety-id")
        }
    }

    private static func expectedConversationValue(for parameterID: LLMParameterID) -> JSONValue {
        switch parameterID {
        case .model:
            return .string("unit-model")
        case .systemPrompt:
            return .string("System")
        case .maxOutputTokens:
            return .integer(2048)
        case .temperature:
            return .number(0.8)
        case .topP:
            return .number(0.9)
        case .stopSequences:
            return .string("END\nSTOP")
        case .responseFormat:
            return .string("json_schema")
        case .reasoningEffort:
            return .string("high")
        case .reasoningSummary:
            return .string("auto")
        case .serviceTier:
            return .string("priority")
        case .stream:
            return .boolean(true)
        case .store:
            return .boolean(false)
        case .toolChoice:
            return .string("auto")
        case .parallelToolCalls:
            return .boolean(true)
        case .promptCacheKey:
            return .string("cache-key")
        case .previousResponseID:
            return .string("resp_previous")
        case .include:
            return .array([.string("reasoning.encrypted_content")])
        case .textVerbosity:
            return .string("medium")
        case .frequencyPenalty:
            return .number(0.1)
        case .presencePenalty:
            return .number(0.2)
        case .logitBias:
            return .object(["42": .integer(1)])
        case .seed:
            return .integer(123)
        case .user:
            return .string("user-id")
        case .safetyIdentifier:
            return .string("safety-id")
        }
    }

    private static func expectedGenerationValue(for parameterID: LLMParameterID) -> JSONValue {
        switch parameterID {
        case .model:
            return .string("unit-model")
        case .systemPrompt:
            return .string("System")
        case .maxOutputTokens:
            return .integer(2048)
        case .temperature:
            return .number(0.8)
        case .topP:
            return .number(0.9)
        case .stopSequences:
            return .array([.string("END"), .string("STOP")])
        case .responseFormat:
            return .string("json_schema")
        case .reasoningEffort:
            return .string("high")
        case .reasoningSummary:
            return .string("auto")
        case .serviceTier:
            return .string("priority")
        case .stream:
            return .boolean(true)
        case .store:
            return .boolean(false)
        case .toolChoice:
            return .string("auto")
        case .parallelToolCalls:
            return .boolean(true)
        case .promptCacheKey:
            return .string("cache-key")
        case .previousResponseID:
            return .string("resp_previous")
        case .include:
            return .array([.string("reasoning.encrypted_content")])
        case .textVerbosity:
            return .string("medium")
        case .frequencyPenalty:
            return .number(0.1)
        case .presencePenalty:
            return .number(0.2)
        case .logitBias:
            return .object(["42": .integer(1)])
        case .seed:
            return .integer(123)
        case .user:
            return .string("user-id")
        case .safetyIdentifier:
            return .string("safety-id")
        }
    }
}
