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
        XCTAssertTrue(registry.profile(for: .openAICodexChatGPTSubscription).isEnabled)
        XCTAssertEqual(LLMProviderRegistry.providerID(fromProviderName: "LM Studio"), .lmStudio)
        XCTAssertEqual(LLMProviderRegistry.providerID(fromProviderName: "OpenRouter"), .openRouter)
    }

    func testBundledDefaultsProvideProviderDefaultModels() {
        let defaults = LLMDefaultsCatalog.bundled

        XCTAssertEqual(defaults.defaultModelID(for: .openAIPlatform), "gpt-5.4-nano")
        XCTAssertEqual(defaults.defaultModelID(for: .openAICodexChatGPTSubscription), "gpt-5.5")
        XCTAssertEqual(defaults.defaultModelID(for: .anthropic), "claude-sonnet-4-6")
        XCTAssertEqual(defaults.defaultModelID(for: .openRouter), "openai/gpt-5.4-nano")
        XCTAssertEqual(defaults.defaultModelID(for: .xAI), "grok-4.3")
        XCTAssertEqual(defaults.defaultModelID(for: .deepSeek), "deepseek-v4-flash")
        XCTAssertNil(defaults.defaultModelID(for: .customOpenAICompatible))
    }

    func testCapabilityTaxonomyCoversContentAndRuntimeFeatures() {
        XCTAssertTrue(LLMModelCapability.allCases.contains(.text))
        XCTAssertTrue(LLMModelCapability.allCases.contains(.image))
        XCTAssertTrue(LLMModelCapability.allCases.contains(.tools))
        XCTAssertTrue(LLMModelCapability.allCases.contains(.reasoning))
    }

    func testBundledDefaultsProvideCurrentModelMetadata() {
        let defaults = LLMDefaultsCatalog.bundled

        let openAI = defaults.modelDefaults(providerID: .openAIPlatform, modelID: "gpt-5.4-nano")
        XCTAssertEqual(openAI?.contextWindow, 400000)
        XCTAssertTrue(openAI?.capabilities?.contains(.text) ?? false)
        XCTAssertTrue(openAI?.capabilities?.contains(.image) ?? false)
        XCTAssertTrue(openAI?.capabilities?.contains(.file) ?? false)
        XCTAssertTrue(openAI?.capabilities?.contains(.reasoning) ?? false)

        let anthropic = defaults.modelDefaults(providerID: .anthropic, modelID: "claude-sonnet-4-6")
        XCTAssertEqual(anthropic?.contextWindow, 1000000)
        XCTAssertTrue(anthropic?.capabilities?.contains(.text) ?? false)
        XCTAssertTrue(anthropic?.capabilities?.contains(.image) ?? false)

        let xAI = defaults.modelDefaults(providerID: .xAI, modelID: "grok-4.3")
        XCTAssertEqual(xAI?.contextWindow, 1000000)
        XCTAssertTrue(xAI?.capabilities?.contains(.jsonSchema) ?? false)

        let deepSeek = defaults.modelDefaults(providerID: .deepSeek, modelID: "deepseek-v4-flash")
        XCTAssertEqual(deepSeek?.contextWindow, 1000000)
        XCTAssertTrue(deepSeek?.capabilities?.contains(.tools) ?? false)
    }

    func testBundledDefaultsProvideConservativeFallbackCandidate() {
        let catalog = try! LLMDefaultsCatalog(data: Data("""
        {
          "providerDefaults": [],
          "rules": []
        }
        """.utf8))
        let candidate = catalog.modelDescriptor(providerID: .customOpenAICompatible, modelID: "unknown-model")

        XCTAssertEqual(candidate.capabilities, [.text])
        XCTAssertEqual(candidate.displayName, "unknown-model")
    }

    func testCatalogCanProvideMinimalUnknownModelDefaults() throws {
        let defaults = try LLMDefaultsCatalog(data: Data("""
        {
          "providerDefaults": [],
          "rules": [
            {
              "modelDefaults": {
                "capabilities": ["text"]
              }
            }
          ]
        }
        """.utf8))
        let candidate = defaults.modelDescriptor(
            providerID: .openAIPlatform,
            modelID: "unknown-future-model"
        )

        XCTAssertEqual(candidate.capabilities, [.text])
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
                "capabilities": ["text", "streaming"]
              }
            }
          ]
        }
        """.utf8))

        XCTAssertEqual(catalog.defaultModelID(for: .openAIPlatform), "unit-model")
        XCTAssertEqual(catalog.modelDefaults(providerID: .openAIPlatform, modelID: "unit-anything")?.capabilities, [.text, .streaming])
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
                "capabilities": ["text"]
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
                "capabilities": ["text"]
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
                  "capabilities": ["text", "streaming"]
              }
            },
            {
              "match": {
                "providerRegex": "^openAIPlatform$",
                "modelRegex": "^vision-"
              },
              "modelDefaults": {
                  "capabilities": ["image", "jsonObject"]
              }
            },
            {
              "match": {
                "adapterID": "openAIChatCompletions"
              },
              "parameterAvailability": [
                {
                  "parameter": "max_output_tokens",
                  "enabled": true
                }
              ],
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
              "parameterAvailability": [
                {
                  "parameter": "max_output_tokens",
                  "required": true,
                  "defaultValue": 4096
                },
                {
                  "parameter": "temperature",
                  "available": false
                }
              ],
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
              "parameterAvailability": [
                {
                  "parameter": "max_output_tokens"
                }
              ],
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
        XCTAssertEqual(modelDefaults?.capabilities, [.image, .jsonObject])

        let mapping = catalog.parameterMappings(
            providerID: .openAIPlatform,
            adapterID: .openAIChatCompletions,
            modelID: "gpt-5.4-nano"
        ).first { $0.semanticParameterID == .maxOutputTokens }
        XCTAssertEqual(mapping?.wireKey, "max_completion_tokens")
        let mappingJSON = try JSONEncoder().encode(mapping)
        XCTAssertFalse(String(data: mappingJSON, encoding: .utf8)?.contains("required") ?? true)

        let availability = catalog.parameterAvailability(
            providerID: .openAIPlatform,
            adapterID: .openAIChatCompletions,
            modelID: "gpt-5.4-nano"
        )
        let maxTokenAvailability = availability.first { $0.semanticParameterID == .maxOutputTokens }
        XCTAssertTrue(maxTokenAvailability?.isRequired ?? false)
        XCTAssertTrue(maxTokenAvailability?.isEnabled ?? false)
        XCTAssertEqual(maxTokenAvailability?.defaultValue, .integer(4096))
        XCTAssertFalse(availability.first { $0.semanticParameterID == .temperature }?.isAvailable ?? true)

        let aggregatorMapping = catalog.parameterMappings(
            providerID: .openRouter,
            adapterID: .openAICompatibleChatCompletions,
            modelID: "openai/gpt-5-mini"
        ).first { $0.semanticParameterID == .maxOutputTokens }
        XCTAssertEqual(aggregatorMapping?.wireKey, "max_completion_tokens")
    }

    func testModelMetadataDecoderUsesProviderMetadataOverDefaults() {
        let profile = LLMProviderRegistry.shared.profile(for: .openRouter)
        let models = LLMModelMetadataDecoder.openAICompatibleCandidates(
            from: [
                .object([
                    "id": .string("vision-model"),
                    "context_window": .integer(999),
                    "modalities": .array([.string("image")]),
                    "capabilities": .array([.string("tools")])
                ])
            ],
            profile: profile
        )

        XCTAssertEqual(models.first?.contextWindow, 999)
        XCTAssertTrue(models.first?.capabilities.contains(.image) ?? false)
        XCTAssertTrue(models.first?.capabilities.contains(.tools) ?? false)
    }

    func testModelMetadataDecoderFillsMissingFieldsFromDefaults() {
        let profile = LLMProviderRegistry.shared.profile(for: .openRouter)
        let models = LLMModelMetadataDecoder.openAICompatibleCandidates(
            from: [.object(["id": .string("fallback-model")])],
            profile: profile
        )

        XCTAssertEqual(models.first?.contextWindow, 128000)
        XCTAssertTrue(models.first?.capabilities.contains(.text) ?? false)
        XCTAssertTrue(models.first?.capabilities.contains(.streaming) ?? false)
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
