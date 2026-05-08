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
        let reasoningEffort = model.parameterMappings.first {
            $0.endpointFamilyEnum == .chatCompletions && $0.semanticParameterIDEnum == .reasoningEffort
        }
        XCTAssertEqual(reasoningEffort?.wireKey, "reasoning_effort")
        XCTAssertFalse(reasoningEffort?.isCustomized ?? true)
    }

    func testConversationProjectionUsesSemanticDefinitionsAndPresentation() {
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test",
            defaultModel: "gpt-4.1-nano",
            providerID: .openAIPlatform
        )
        config.defaultEndpointFamilyEnum = .chatCompletions
        let options = ConversationOptions(apiConfiguration: config)
        options.temperature = 0.7

        let controls = ConversationParameterProjection.controls(
            for: options,
            apiConfiguration: config,
            modelContext: nil
        )

        let temperature = controls.first { $0.parameterID == .temperature }
        XCTAssertEqual(temperature?.valueType, .float)
        XCTAssertEqual(temperature?.controlType, .slider)
        XCTAssertEqual(temperature?.displayName, AiParameterPresentationCatalog.displayName(for: .temperature))
        XCTAssertEqual(temperature?.value, .number(0.7))
        XCTAssertTrue(temperature?.isEnabled ?? false)
    }

    func testDisabledOptionalParameterDoesNotReachGenerationOptions() {
        let options = ConversationOptions()
        options.temperature = 0.9
        options.setParameterEnabled(.temperature, enabled: false)
        let mappings: [LLMParameterID: LLMParameterMappingDescriptor] = [
            .temperature: LLMParameterMappingDescriptor(
                endpointFamily: .chatCompletions,
                semanticParameterID: .temperature,
                wireKey: "temperature"
            )
        ]

        let generationOptions = options.generationOptions(
            resolvedModelID: "model",
            resolvedEndpointFamily: .chatCompletions,
            mappings: mappings
        )

        XCTAssertNil(generationOptions.temperature)
    }
}
