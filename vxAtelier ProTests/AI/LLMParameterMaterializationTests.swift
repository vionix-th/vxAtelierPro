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
        let config = APIConfigurationItem(name: "OpenAI", baseURL: "https://unit.test", providerID: .openAIPlatform)
        config.defaultAdapterIDEnum = .openAIChatCompletions
        let model = ModelItem(modelID: "gpt-5.4-nano", apiConfiguration: config)
        let mapping = model.parameterMappings.first {
            $0.adapterIDEnum == .openAIChatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        mapping?.wireKey = "custom_max_tokens"
        mapping?.markCustomized()

        model.materializeDefaultParameterMappings(preserveCustomized: true)

        XCTAssertEqual(mapping?.wireKey, "custom_max_tokens")
    }

    func testModelMaterializesDefaultParameterMappingsFromCatalog() {
        let config = APIConfigurationItem(name: "OpenAI", baseURL: "https://unit.test", providerID: .openAIPlatform)
        config.defaultAdapterIDEnum = .openAIChatCompletions
        let model = ModelItem(modelID: "gpt-4.1-nano", apiConfiguration: config)

        let mapping = model.parameterMappings.first {
            $0.adapterIDEnum == .openAIChatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }

        XCTAssertEqual(mapping?.wireKey, "max_tokens")
        XCTAssertEqual(mapping?.valueType, LLMParameterValueType.integer.rawValue)
        XCTAssertEqual(mapping?.controlType, AiArgumentControlType.stepper.rawValue)
    }

    func testModelMaterializesDefaultParameterAvailabilityFromCatalog() {
        let config = APIConfigurationItem(name: "Anthropic", baseURL: "https://unit.test", providerID: .anthropic)
        config.defaultAdapterIDEnum = .anthropicMessages
        let model = ModelItem(modelID: "claude-sonnet-4-5", apiConfiguration: config)

        let maxTokens = model.parameterAvailability.first {
            $0.adapterIDEnum == .anthropicMessages && $0.semanticParameterIDEnum == .maxOutputTokens
        }

        XCTAssertTrue(maxTokens?.isAvailable ?? false)
        XCTAssertTrue(maxTokens?.isRequired ?? false)
        XCTAssertEqual(maxTokens?.defaultJSONValue, .integer(4096))
        XCTAssertEqual(maxTokens?.valueType, LLMParameterValueType.integer.rawValue)
    }

    func testResetDefaultParameterMappingsRestoresAdapterDefaults() {
        let config = APIConfigurationItem(name: "OpenAI", baseURL: "https://unit.test", providerID: .openAIPlatform)
        config.defaultAdapterIDEnum = .openAIChatCompletions
        let model = ModelItem(modelID: "gpt-5.4-nano", apiConfiguration: config)
        let maxTokens = model.parameterMappings.first {
            $0.adapterIDEnum == .openAIChatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        maxTokens?.wireKey = "custom_max_tokens"
        maxTokens?.markCustomized()
        model.parameterMappings.append(ModelParameterMappingItem(
            adapterID: .openAIChatCompletions,
            semanticParameterID: .reasoningEffort,
            wireKey: "reasoning_effort",
            isCustomized: true
        ))

        model.resetDefaultParameterMappings(adapterID: .openAIChatCompletions)

        let resetMaxTokens = model.parameterMappings.first {
            $0.adapterIDEnum == .openAIChatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        XCTAssertEqual(resetMaxTokens?.wireKey, "max_completion_tokens")
        XCTAssertFalse(resetMaxTokens?.isCustomized ?? true)
        let reasoningEffort = model.parameterMappings.first {
            $0.adapterIDEnum == .openAIChatCompletions && $0.semanticParameterIDEnum == .reasoningEffort
        }
        XCTAssertEqual(reasoningEffort?.wireKey, "reasoning_effort")
        XCTAssertFalse(reasoningEffort?.isCustomized ?? true)
    }

    func testCustomizedModelAvailabilitySurvivesDefaultMaterialization() {
        let config = APIConfigurationItem(name: "OpenAI", baseURL: "https://unit.test", providerID: .openAIPlatform)
        config.defaultAdapterIDEnum = .openAIChatCompletions
        let model = ModelItem(modelID: "gpt-4.1-nano", apiConfiguration: config)
        let temperature = model.parameterAvailability.first {
            $0.adapterIDEnum == .openAIChatCompletions && $0.semanticParameterIDEnum == .temperature
        }
        temperature?.isEnabled = true
        temperature?.defaultJSONValue = .number(0.3)
        temperature?.markCustomized()

        model.materializeDefaultParameterAvailability(preserveCustomized: true)

        XCTAssertEqual(temperature?.defaultJSONValue, .number(0.3))
        XCTAssertTrue(temperature?.isEnabled ?? false)
    }

    func testResetDefaultParameterAvailabilityRestoresAdapterDefaults() {
        let config = APIConfigurationItem(name: "OpenAI", baseURL: "https://unit.test", providerID: .openAIPlatform)
        config.defaultAdapterIDEnum = .openAIChatCompletions
        let model = ModelItem(modelID: "gpt-5.4-nano", apiConfiguration: config)
        let temperature = model.parameterAvailability.first {
            $0.adapterIDEnum == .openAIChatCompletions && $0.semanticParameterIDEnum == .temperature
        }
        temperature?.isAvailable = true
        temperature?.markCustomized()
        model.parameterAvailability.append(ModelParameterAvailabilityItem(
            adapterID: .openAIChatCompletions,
            semanticParameterID: .serviceTier,
            isCustomized: true
        ))

        model.resetDefaultParameterAvailability(adapterID: .openAIChatCompletions)

        let resetTemperature = model.parameterAvailability.first {
            $0.adapterIDEnum == .openAIChatCompletions && $0.semanticParameterIDEnum == .temperature
        }
        XCTAssertFalse(resetTemperature?.isAvailable ?? true)
        XCTAssertFalse(resetTemperature?.isCustomized ?? true)
        XCTAssertNil(model.parameterAvailability.first {
            $0.adapterIDEnum == .openAIChatCompletions && $0.semanticParameterIDEnum == .serviceTier
        })
    }

    func testConversationProjectionUsesSemanticDefinitionsAndPresentation() {
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
        options.setParameterEnabled(.temperature, enabled: true)

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
        XCTAssertTrue(temperature?.isAvailable ?? false)
        XCTAssertTrue(temperature?.isMapped ?? false)
        XCTAssertTrue(temperature?.canToggleEnabled ?? false)
        XCTAssertTrue(temperature?.isValueEditable ?? false)
    }

    func testConversationProjectionSeparatesAvailabilityRequiredAndEnabledState() {
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test",
            defaultModel: "unit-model",
            providerID: .openAIPlatform
        )
        config.defaultAdapterIDEnum = .openAIChatCompletions
        let model = ModelItem(modelID: "unit-model", apiConfiguration: config)
        model.parameterAvailability = [
            ModelParameterAvailabilityItem(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .maxOutputTokens,
                isAvailable: true,
                isRequired: true
            ),
            ModelParameterAvailabilityItem(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .temperature,
                isAvailable: false
            ),
            ModelParameterAvailabilityItem(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .topP,
                isAvailable: true
            )
        ]
        model.parameterMappings = [
            ModelParameterMappingItem(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .maxOutputTokens,
                wireKey: "max_tokens"
            ),
            ModelParameterMappingItem(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .topP,
                wireKey: "top_p"
            )
        ]
        config.models = [model]
        let options = ConversationOptions(apiConfiguration: config)
        options.selectedModelID = "unit-model"
        options.setParameterEnabled(.topP, enabled: false)

        let controls = ConversationParameterProjection.controls(
            for: options,
            apiConfiguration: config
        )

        let required = controls.first { $0.parameterID == .maxOutputTokens }
        XCTAssertTrue(required?.required ?? false)
        XCTAssertTrue(required?.isEnabled ?? false)
        XCTAssertFalse(required?.canToggleEnabled ?? true)
        XCTAssertTrue(required?.isValueEditable ?? false)

        let optional = controls.first { $0.parameterID == .topP }
        XCTAssertFalse(optional?.required ?? true)
        XCTAssertTrue(optional?.isAvailable ?? false)
        XCTAssertTrue(optional?.isMapped ?? false)
        XCTAssertFalse(optional?.isEnabled ?? true)
        XCTAssertTrue(optional?.canToggleEnabled ?? false)
        XCTAssertTrue(optional?.isValueEditable ?? false)

        let unavailable = controls.first { $0.parameterID == .temperature }
        XCTAssertFalse(unavailable?.isAvailable ?? true)
        XCTAssertFalse(unavailable?.isMapped ?? true)
        XCTAssertFalse(unavailable?.isEnabled ?? true)
        XCTAssertFalse(unavailable?.canToggleEnabled ?? true)
        XCTAssertFalse(unavailable?.isValueEditable ?? true)
    }

    func testDisabledOptionalParameterDoesNotReachGenerationOptions() {
        let options = ConversationOptions()
        options.temperature = 0.9
        options.setParameterEnabled(.temperature, enabled: false)
        let modelAvailability: [LLMParameterID: LLMParameterAvailabilityDescriptor] = [
            .temperature: LLMParameterAvailabilityDescriptor(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .temperature
            )
        ]

        let generationOptions = LLMParameterAvailabilityResolver.resolvedOptions(
            from: options.generationOptions(resolvedModelID: "model"),
            conversationPreferences: options.parameterInclusionPreferences,
            modelAvailability: modelAvailability
        )

        XCTAssertNil(generationOptions.temperature)
    }

    func testConversationOptionsNormalizeAddsAllKnownParameterEnabledStates() {
        let options = ConversationOptions()
        options.parameterEnabledStates = [:]

        options.normalizeKnownParameters()

        for parameterID in LLMParameterID.allCases {
            XCTAssertNotNil(options.parameterEnabledStates[parameterID.rawValue], parameterID.rawValue)
        }
    }

    func testConversationOptionsNormalizationPreservesUnknownParameterValues() {
        let options = ConversationOptions()
        options.parameterValuesJSON = #"{"future_parameter":{"nested":true}}"#

        options.normalizeKnownParameters()

        XCTAssertTrue(options.parameterValuesJSON.contains("future_parameter"))
        XCTAssertTrue(options.parameterValuesJSON.contains("nested"))
    }

    func testConversationOptionsReconcileAppliesAvailabilityWithoutDeletingValues() {
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test",
            defaultModel: "unit-model",
            providerID: .openAIPlatform
        )
        config.defaultAdapterIDEnum = .openAIChatCompletions
        let model = ModelItem(modelID: "unit-model", apiConfiguration: config)
        model.parameterAvailability = [
            ModelParameterAvailabilityItem(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .maxOutputTokens,
                isAvailable: true,
                isRequired: true,
                isEnabled: false,
                defaultValue: .integer(1024)
            ),
            ModelParameterAvailabilityItem(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .temperature,
                isAvailable: false,
                isRequired: false,
                isEnabled: true,
                defaultValue: .number(0.2)
            ),
            ModelParameterAvailabilityItem(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .topP,
                isAvailable: true,
                isRequired: false,
                isEnabled: true,
                defaultValue: .number(0.8)
            ),
            ModelParameterAvailabilityItem(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .stream,
                isAvailable: true,
                isRequired: true,
                isEnabled: false,
                defaultValue: .boolean(true)
            )
        ]
        config.models = [model]

        let options = ConversationOptions(apiConfiguration: config)
        options.selectedModelID = "unit-model"
        options.temperature = 0.7
        options.setParameterEnabled(.temperature, enabled: true)
        options.setParameterEnabled(.topP, enabled: false)

        options.reconcileParameters(apiConfiguration: config, modelID: "unit-model")

        XCTAssertTrue(options.isParameterEnabled(.maxOutputTokens))
        XCTAssertEqual(options.maxOutputTokens, 1024)
        XCTAssertFalse(options.isParameterEnabled(.temperature))
        XCTAssertEqual(options.temperature, 0.7)
        XCTAssertFalse(options.isParameterEnabled(.topP))
        XCTAssertEqual(options.topP, 0.8)
        XCTAssertTrue(options.isParameterEnabled(.stream))
        XCTAssertEqual(options.streamMode, .enabled)
    }

    func testConversationOptionsReconcilePreservesValuesAcrossModelSwitch() {
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test",
            defaultModel: "model-a",
            providerID: .openAIPlatform
        )
        config.defaultAdapterIDEnum = .openAIChatCompletions
        let modelA = ModelItem(modelID: "model-a", apiConfiguration: config)
        modelA.parameterAvailability = [
            ModelParameterAvailabilityItem(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .temperature,
                isAvailable: true,
                isRequired: false,
                isEnabled: true,
                defaultValue: .number(0.3)
            )
        ]
        let modelB = ModelItem(modelID: "model-b", apiConfiguration: config)
        modelB.parameterAvailability = [
            ModelParameterAvailabilityItem(
                adapterID: .openAIChatCompletions,
                semanticParameterID: .temperature,
                isAvailable: false,
                isRequired: false,
                isEnabled: false,
                defaultValue: .number(0.9)
            )
        ]
        config.models = [modelA, modelB]

        let options = ConversationOptions(apiConfiguration: config)
        options.selectedModelID = "model-a"
        options.temperature = 0.6
        options.setParameterEnabled(.temperature, enabled: true)

        options.selectedModelID = "model-b"

        XCTAssertFalse(options.isParameterEnabled(.temperature))
        XCTAssertEqual(options.temperature, 0.6)
    }
}
