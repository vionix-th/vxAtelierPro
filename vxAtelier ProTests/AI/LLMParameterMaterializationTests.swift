import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMParameterMaterializationTests: XCTestCase {
    func testCustomizedModelMappingSurvivesDefaultMaterialization() {
        let model = ModelItem(descriptor: LLMModelDescriptor(
            id: "gpt-5.4-nano",
            providerID: .openAIPlatform,
            endpointFamilies: [.chatCompletions],
            modalities: [.text],
            schemaFeatures: [.streaming]
        ))
        let mapping = model.parameterMappings.first {
            $0.endpointFamilyEnum == .chatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        mapping?.wireKey = "custom_max_tokens"
        mapping?.markCustomized()

        model.materializeDefaultParameterMappings(preserveCustomized: true)

        XCTAssertEqual(mapping?.wireKey, "custom_max_tokens")
    }

    func testModelMaterializesDefaultParameterMappingsFromCatalog() {
        let model = ModelItem(descriptor: LLMModelDescriptor(
            id: "gpt-4.1-nano",
            providerID: .openAIPlatform,
            endpointFamilies: [.chatCompletions],
            modalities: [.text],
            schemaFeatures: [.streaming]
        ))

        let mapping = model.parameterMappings.first {
            $0.endpointFamilyEnum == .chatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }

        XCTAssertEqual(mapping?.wireKey, "max_tokens")
        XCTAssertEqual(mapping?.valueType, LLMParameterValueType.integer.rawValue)
        XCTAssertEqual(mapping?.controlType, AiArgumentControlType.stepper.rawValue)
    }

    func testResetDefaultParameterMappingsRestoresEndpointDefaults() {
        let model = ModelItem(descriptor: LLMModelDescriptor(
            id: "gpt-5.4-nano",
            providerID: .openAIPlatform,
            endpointFamilies: [.chatCompletions],
            modalities: [.text],
            schemaFeatures: [.streaming]
        ))
        let maxTokens = model.parameterMappings.first {
            $0.endpointFamilyEnum == .chatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        maxTokens?.wireKey = "custom_max_tokens"
        maxTokens?.markCustomized()
        model.parameterMappings.append(ModelParameterMappingItem(
            endpointFamily: .chatCompletions,
            semanticParameterID: .reasoningEffort,
            wireKey: "reasoning_effort",
            isCustomized: true
        ))

        model.resetDefaultParameterMappings(endpointFamily: .chatCompletions)

        let resetMaxTokens = model.parameterMappings.first {
            $0.endpointFamilyEnum == .chatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        XCTAssertEqual(resetMaxTokens?.wireKey, "max_completion_tokens")
        XCTAssertFalse(resetMaxTokens?.isCustomized ?? true)
        XCTAssertFalse(model.parameterMappings.contains {
            $0.endpointFamilyEnum == .chatCompletions && $0.semanticParameterIDEnum == .reasoningEffort
        })
    }

    func testConversationArgumentSetupUsesSemanticDefinitionsAndPresentation() {
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test",
            defaultModel: "gpt-4.1-nano",
            providerID: .openAIPlatform
        )
        config.defaultEndpointFamilyEnum = .chatCompletions
        let options = ConversationOptions(apiConfiguration: config, shouldSetupParameters: false)
        let existingTemperature = AiRequestArgument(
            name: LLMParameterID.temperature.rawValue,
            displayName: "Old Temperature",
            required: false,
            valueType: .float,
            controlType: .textField,
            defaultValue: 0.7
        )
        existingTemperature.isEnabled = true
        options.parameters = [existingTemperature]

        options.setupAiRequestArguments(for: config, modelContext: nil)

        let temperature = options.parameters.first { $0.name == LLMParameterID.temperature.rawValue }
        XCTAssertEqual(temperature?.valueType, LLMParameterValueType.float.rawValue)
        XCTAssertEqual(temperature?.controlType, AiArgumentControlType.slider.rawValue)
        XCTAssertEqual(temperature?.displayName, AiParameterPresentationCatalog.displayName(for: .temperature))
        XCTAssertEqual(temperature?.floatValue, 0.7)
        XCTAssertTrue(temperature?.isEnabled ?? false)
    }

    func testDisabledOptionalParameterDoesNotReachGenerationOptions() {
        let options = ConversationOptions(shouldSetupParameters: false)
        options.temperature = 0.9
        let temperature = AiRequestArgument(
            name: LLMParameterID.temperature.rawValue,
            displayName: AiParameterPresentationCatalog.displayName(for: .temperature),
            valueType: .float,
            controlType: .slider,
            defaultValue: 0.9
        )
        temperature.isEnabled = false
        options.parameters = [temperature]

        let generationOptions = options.generationOptions(resolvedModelID: "model", resolvedEndpointFamily: .chatCompletions)

        XCTAssertNil(generationOptions.temperature)
    }
}
