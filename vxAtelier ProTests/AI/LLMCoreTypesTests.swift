import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMCoreTypesTests: XCTestCase {
    func testProviderRegistryProfiles() {
        let registry = LLMProviderRegistry.shared

        XCTAssertEqual(registry.profile(for: .openAIPlatform).defaultAdapterID, .openAIResponses)
        XCTAssertTrue(registry.profile(for: .openAIPlatform).supportedAdapterIDs.contains(.openAIChatCompletions))
        XCTAssertFalse(registry.profile(for: .openAIChatGPTSubscription).isEnabled)
        XCTAssertEqual(LLMProviderRegistry.providerID(fromProviderName: "LM Studio"), .lmStudio)
        XCTAssertEqual(LLMProviderRegistry.providerID(fromProviderName: "OpenRouter"), .openRouter)
    }

    func testBundledDefaultsProvideProviderDefaultModels() {
        let defaults = LLMDefaultsCatalog.bundled

        XCTAssertEqual(defaults.defaultModelID(for: .openAIPlatform), "gpt-5.4-nano")
        XCTAssertEqual(defaults.defaultModelID(for: .anthropic), "claude-sonnet-4-6")
        XCTAssertEqual(defaults.defaultModelID(for: .openRouter), "openai/gpt-5.4-nano")
        XCTAssertEqual(defaults.defaultModelID(for: .xAI), "grok-4.3")
        XCTAssertEqual(defaults.defaultModelID(for: .deepSeek), "deepseek-v4-flash")
        XCTAssertNil(defaults.defaultModelID(for: .customOpenAICompatible))
    }

    func testModalityTaxonomyIsMediaOnly() {
        XCTAssertEqual(Set(LLMModality.allCases), [.text, .image, .audio, .file, .video])
        XCTAssertTrue(LLMSchemaFeature.allCases.contains(.tools))
        XCTAssertTrue(LLMSchemaFeature.allCases.contains(.reasoning))
    }

    func testBundledDefaultsProvideCurrentModelMetadata() {
        let defaults = LLMDefaultsCatalog.bundled

        let openAI = defaults.modelDefaults(providerID: .openAIPlatform, modelID: "gpt-5.4-nano")
        XCTAssertEqual(openAI?.contextWindow, 400000)
        XCTAssertEqual(openAI?.modalities, [.text, .image, .file])
        XCTAssertFalse(openAI?.supportedParameters?.contains("temperature") ?? true)
        XCTAssertTrue(openAI?.schemaFeatures?.contains(.reasoning) ?? false)

        let anthropic = defaults.modelDefaults(providerID: .anthropic, modelID: "claude-sonnet-4-6")
        XCTAssertEqual(anthropic?.contextWindow, 1000000)
        XCTAssertEqual(anthropic?.modalities, [.text, .image])

        let xAI = defaults.modelDefaults(providerID: .xAI, modelID: "grok-4.3")
        XCTAssertEqual(xAI?.contextWindow, 1000000)
        XCTAssertTrue(xAI?.schemaFeatures?.contains(.jsonSchema) ?? false)

        let deepSeek = defaults.modelDefaults(providerID: .deepSeek, modelID: "deepseek-v4-flash")
        XCTAssertEqual(deepSeek?.contextWindow, 1000000)
        XCTAssertTrue(deepSeek?.supportedParameters?.contains("tools") ?? false)
    }

    func testBundledDefaultsProvideConservativeFallbackDescriptor() {
        let catalog = try! LLMDefaultsCatalog(data: Data("""
        {
          "providerDefaults": [],
          "rules": []
        }
        """.utf8))
        let descriptor = catalog.modelDescriptor(providerID: .customOpenAICompatible, modelID: "unknown-model")

        XCTAssertEqual(descriptor.modalities, [.text])
        XCTAssertTrue(descriptor.supportedParameters.isEmpty)
        XCTAssertTrue(descriptor.schemaFeatures.isEmpty)
        XCTAssertEqual(descriptor.displayName, "unknown-model")
    }

    func testCatalogCanProvideMinimalUnknownModelDefaults() throws {
        let defaults = try LLMDefaultsCatalog(data: Data("""
        {
          "providerDefaults": [],
          "rules": [
            {
              "modelDefaults": {
                "modalities": ["text"],
                "supportedParameters": [],
                "schemaFeatures": []
              }
            }
          ]
        }
        """.utf8))
        let descriptor = defaults.modelDescriptor(
            providerID: .openAIPlatform,
            modelID: "unknown-future-model"
        )

        XCTAssertEqual(descriptor.modalities, [.text])
        XCTAssertTrue(descriptor.supportedParameters.isEmpty)
        XCTAssertTrue(descriptor.schemaFeatures.isEmpty)
    }

    func testDefaultsCatalogDecodesValidJSON() throws {
        let catalog = try LLMDefaultsCatalog(data: Data("""
        {
          "providerDefaults": [
            {
              "provider": "openAIPlatform",
              "defaultModel": "unit-model"
            }
          ],
          "rules": [
            {
              "match": {
                "providerRegex": "^openAIPlatform$",
                "modelRegex": "^unit-"
              },
              "modelDefaults": {
                "adapterIDs": ["openAIResponses"],
                "modalities": ["text"],
                "schemaFeatures": ["streaming"]
              }
            }
          ]
        }
        """.utf8))

        XCTAssertEqual(catalog.defaultModelID(for: .openAIPlatform), "unit-model")
        XCTAssertEqual(catalog.modelDefaults(providerID: .openAIPlatform, modelID: "unit-anything")?.modalities, [.text])
    }

    func testDefaultsCatalogRejectsInvalidEnumValues() {
        XCTAssertThrowsError(try LLMDefaultsCatalog(data: Data("""
        {
          "providerDefaults": [
            {
              "provider": "invalidProvider",
              "defaultModel": "invalid"
            }
          ],
          "rules": []
        }
        """.utf8)))
    }

    func testDefaultsCatalogRejectsMissingRequiredMappingFields() {
        XCTAssertThrowsError(try LLMDefaultsCatalog(data: Data("""
        {
          "providerDefaults": [],
          "rules": [
            {
              "match": {
                "adapterID": "openAIChatCompletions"
              },
              "parameterMappings": [
                {
                  "wireKey": "max_tokens"
                }
              ]
            }
          ]
        }
        """.utf8)))
    }

    func testDefaultsCatalogRejectsInvalidRegexSyntax() {
        XCTAssertThrowsError(try LLMDefaultsCatalog(data: Data("""
        {
          "providerDefaults": [],
          "rules": [
            {
              "match": {
                "providerRegex": "["
              },
              "modelDefaults": {
                "modalities": ["text"]
              }
            }
          ]
        }
        """.utf8))) { error in
            guard case LLMDefaultsCatalogError.invalidRegex(let field, let pattern, _) = error else {
                return XCTFail("Expected invalidRegex, got \(error)")
            }
            XCTAssertEqual(field, "match.providerRegex")
            XCTAssertEqual(pattern, "[")
        }
    }

    func testDefaultsCatalogRejectsEmptyRegex() {
        XCTAssertThrowsError(try LLMDefaultsCatalog(data: Data("""
        {
          "providerDefaults": [],
          "rules": [
            {
              "match": {
                "modelRegex": ""
              },
              "modelDefaults": {
                "modalities": ["text"]
              }
            }
          ]
        }
        """.utf8))) { error in
            guard case LLMDefaultsCatalogError.emptyRegex(let field) = error else {
                return XCTFail("Expected emptyRegex, got \(error)")
            }
            XCTAssertEqual(field, "match.modelRegex")
        }
    }

    func testDefaultsCatalogAppliesRegexRulesInOrder() throws {
        let catalog = try LLMDefaultsCatalog(data: Data("""
        {
          "providerDefaults": [],
          "rules": [
            {
              "match": {
                "providerRegex": "^openAIPlatform$"
              },
              "modelDefaults": {
                  "modalities": ["text"],
                  "schemaFeatures": ["streaming"]
              }
            },
            {
              "match": {
                "providerRegex": "^openAIPlatform$",
                "modelRegex": "^vision-"
              },
              "modelDefaults": {
                  "modalities": ["image"],
                  "schemaFeatures": ["jsonObject"]
              }
            },
            {
              "match": {
                "adapterID": "openAIChatCompletions"
              },
              "parameterMappings": [
                {
                  "parameter": "max_output_tokens",
                  "encoding": "scalarKey",
                  "wireKey": "max_tokens"
                }
              ]
            },
            {
              "match": {
                "modelRegex": "(^|.*/)gpt-5([-.].*)?$",
                "adapterID": "openAIChatCompletions"
              },
              "parameterMappings": [
                {
                  "parameter": "max_output_tokens",
                  "encoding": "scalarKey",
                  "wireKey": "max_completion_tokens"
                }
              ]
            },
            {
              "match": {
                "adapterID": "openAICompatibleChatCompletions"
              },
              "parameterMappings": [
                {
                  "parameter": "max_output_tokens",
                  "encoding": "scalarKey",
                  "wireKey": "max_tokens"
                }
              ]
            },
            {
              "match": {
                "modelRegex": "(^|.*/)gpt-5([-.].*)?$",
                "adapterID": "openAICompatibleChatCompletions"
              },
              "parameterMappings": [
                {
                  "parameter": "max_output_tokens",
                  "encoding": "scalarKey",
                  "wireKey": "max_completion_tokens"
                }
              ]
            }
          ]
        }
        """.utf8))

        let modelDefaults = catalog.modelDefaults(providerID: .openAIPlatform, modelID: "vision-large")
        XCTAssertEqual(modelDefaults?.modalities, [.image])
        XCTAssertEqual(modelDefaults?.schemaFeatures, [.jsonObject])

        let mapping = catalog.parameterMappings(
            providerID: .openAIPlatform,
            adapterID: .openAIChatCompletions,
            modelID: "gpt-5.4-nano"
        ).first { $0.semanticParameterID == .maxOutputTokens }
        XCTAssertEqual(mapping?.wireKey, "max_completion_tokens")

        let aggregatorMapping = catalog.parameterMappings(
            providerID: .openRouter,
            adapterID: .openAICompatibleChatCompletions,
            modelID: "openai/gpt-5-mini"
        ).first { $0.semanticParameterID == .maxOutputTokens }
        XCTAssertEqual(aggregatorMapping?.wireKey, "max_completion_tokens")
    }

    func testModelMetadataDecoderUsesProviderMetadataOverDefaults() {
        let profile = LLMProviderRegistry.shared.profile(for: .openRouter)
        let models = LLMModelMetadataDecoder.openAICompatibleDescriptors(
            from: [
                .object([
                    "id": .string("vision-model"),
                    "context_window": .integer(999),
                    "modalities": .array([.string("image")]),
                    "supported_parameters": .array([.string("tools")])
                ])
            ],
            profile: profile,
            adapterIDs: [.openAICompatibleChatCompletions]
        )

        XCTAssertEqual(models.first?.contextWindow, 999)
        XCTAssertEqual(models.first?.modalities, [.image])
        XCTAssertEqual(models.first?.supportedParameters, ["tools"])
        XCTAssertEqual(models.first?.schemaFeatures.contains(.streaming), true)
    }

    func testModelMetadataDecoderFillsMissingFieldsFromDefaults() {
        let profile = LLMProviderRegistry.shared.profile(for: .openRouter)
        let models = LLMModelMetadataDecoder.openAICompatibleDescriptors(
            from: [.object(["id": .string("fallback-model")])],
            profile: profile,
            adapterIDs: [.openAICompatibleChatCompletions]
        )

        XCTAssertEqual(models.first?.contextWindow, 128000)
        XCTAssertEqual(models.first?.modalities, [.text])
        XCTAssertTrue(models.first?.schemaFeatures.contains(.streaming) ?? false)
    }

    func testLLMToolSettingsRegistryUsesAppSettingsDescriptors() {
        XCTAssertEqual(
            Set(LLMToolSettingsRegistry.knownSettings.keys),
            Set(AppSettings.settingDescriptors.keys)
        )
        XCTAssertNil(LLMToolSettingsRegistry.knownSettings["defaultModel"])
        XCTAssertEqual(
            LLMToolSettingsRegistry.knownSettings[AppSettings.Keys.defaultAvatarSize]?.intRange,
            16...128
        )
    }

    func testAPIConfigurationCanonicalProviderFields() {
        let config = APIConfigurationItem(
            name: "OpenRouter",
            apiKey: "key",
            baseURL: "https://openrouter.ai/api/v1",
            providerID: .openRouter
        )

        XCTAssertEqual(config.providerIDEnum, .openRouter)
        XCTAssertEqual(config.defaultAdapterIDEnum, .openAICompatibleChatCompletions)
        XCTAssertEqual(config.makeLLMProviderConfiguration().baseURL, "https://openrouter.ai/api/v1")
    }

    func testMessageContentPartsAndDisplayTextOrdering() {
        let message = MessageItem(
            role: "assistant",
            contentParts: [
                MessageContentPartItem(index: 1, kind: .text, text: "world"),
                MessageContentPartItem(index: 0, kind: .text, text: "Hello ")
            ]
        )

        XCTAssertEqual(message.displayText, "Hello world")
        XCTAssertEqual(message.asDomainMessage().displayText, "Hello world")
        XCTAssertEqual(message.orderedContentParts.compactMap(\.text).joined(), "Hello world")
    }

    func testToolCallAssemblerMergesDeltasByIndexWhenIDMissing() {
        var assembler = LLMToolCallAssembler()

        _ = assembler.merge(LLMToolCall(id: "call_1", callID: "call_1", index: 0, name: "lookup", argumentsJSON: "{\"q\""))
        _ = assembler.merge(LLMToolCall(id: "", callID: nil, index: 0, name: "", argumentsJSON: ":\"test\"}"))

        XCTAssertEqual(assembler.assembled.count, 1)
        XCTAssertEqual(assembler.assembled.first?.id, "call_1")
        XCTAssertEqual(assembler.assembled.first?.name, "lookup")
        XCTAssertEqual(assembler.assembled.first?.argumentsJSON, "{\"q\":\"test\"}")
    }
}
