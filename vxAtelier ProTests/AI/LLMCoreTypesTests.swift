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
        XCTAssertEqual(registry.profile(for: .appleIntelligence).transportKind, .localSystem)
        XCTAssertFalse(registry.profile(for: .appleIntelligence).requiresCredential)
        XCTAssertFalse(registry.profile(for: .appleIntelligence).requiresBaseURL)
        XCTAssertEqual(registry.profile(for: .appleIntelligence).defaultAdapterID, .foundationModels)
        XCTAssertEqual(LLMProviderRegistry.providerID(fromProviderName: "Apple Intelligence"), .appleIntelligence)
        XCTAssertEqual(LLMProviderRegistry.providerID(fromProviderName: "LM Studio"), .lmStudio)
        XCTAssertEqual(LLMProviderRegistry.providerID(fromProviderName: "OpenRouter"), .openRouter)
    }

    func testBundledDefaultsProvideProviderDefaultModels() {
        let defaults = LLMDefaultsCatalog.bundled

        XCTAssertEqual(defaults.defaultModelID(for: .openAIPlatform), "gpt-5.4-nano")
        XCTAssertEqual(defaults.defaultModelID(for: .openAICodexChatGPTSubscription), "gpt-5.5")
        XCTAssertEqual(defaults.defaultModelID(for: .appleIntelligence), "apple-intelligence-default")
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
        XCTAssertEqual(openAI?.contextSize, 400000)
        XCTAssertTrue(openAI?.capabilities?.contains(.text) ?? false)
        XCTAssertTrue(openAI?.capabilities?.contains(.image) ?? false)
        XCTAssertTrue(openAI?.capabilities?.contains(.file) ?? false)
        XCTAssertTrue(openAI?.capabilities?.contains(.reasoning) ?? false)

        let anthropic = defaults.modelDefaults(providerID: .anthropic, modelID: "claude-sonnet-4-6")
        XCTAssertEqual(anthropic?.contextSize, 1000000)
        XCTAssertTrue(anthropic?.capabilities?.contains(.text) ?? false)
        XCTAssertTrue(anthropic?.capabilities?.contains(.image) ?? false)

        let apple = defaults.modelDefaults(providerID: .appleIntelligence, modelID: "apple-intelligence-default")
        XCTAssertEqual(apple?.contextSize, 4096)
        XCTAssertTrue(apple?.capabilities?.contains(.text) ?? false)
        XCTAssertTrue(apple?.capabilities?.contains(.tools) ?? false)
        XCTAssertTrue(apple?.capabilities?.contains(.streaming) ?? false)

        let xAI = defaults.modelDefaults(providerID: .xAI, modelID: "grok-4.3")
        XCTAssertEqual(xAI?.contextSize, 1000000)
        XCTAssertTrue(xAI?.capabilities?.contains(.jsonSchema) ?? false)

        let deepSeek = defaults.modelDefaults(providerID: .deepSeek, modelID: "deepseek-v4-flash")
        XCTAssertEqual(deepSeek?.contextSize, 1000000)
        XCTAssertTrue(deepSeek?.capabilities?.contains(.tools) ?? false)
    }

    func testResolverProvidesUnknownFallbackContract() {
        let catalog = try! LLMDefaultsCatalog(data: Data("""
        {
          "providerDefaults": [],
          "rules": []
        }
        """.utf8))
        let contract = LLMModelContractResolver(
            defaultsCatalog: catalog,
            fallbackContextSize: 4096
        ).resolve(
            providerID: .customOpenAICompatible,
            adapterID: .openAICompatibleChatCompletions,
            modelID: "unknown-model",
            observation: nil
        )

        XCTAssertEqual(contract.displayName, "unknown-model")
        XCTAssertEqual(contract.displayNameSource, .fallback)
        XCTAssertEqual(contract.contextSize, 4096)
        XCTAssertEqual(contract.capabilities[.text], LLMResolvedSupport(state: .unknown, source: .fallback))
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
        let contract = LLMModelContractResolver(
            defaultsCatalog: defaults,
            fallbackContextSize: 4096
        ).resolve(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "unknown-future-model",
            observation: nil
        )

        XCTAssertEqual(contract.capabilities[.text], LLMResolvedSupport(state: .supported, source: .catalog))
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
        ).first { $0.parameterID == .maxOutputTokens }
        XCTAssertEqual(mapping?.wireKey, "max_completion_tokens")
        let mappingJSON = try JSONEncoder().encode(mapping)
        XCTAssertFalse(String(data: mappingJSON, encoding: .utf8)?.contains("required") ?? true)

        let parameterDefaults = catalog.parameterDefaults(
            providerID: .openAIPlatform,
            adapterID: .openAIChatCompletions,
            modelID: "gpt-5.4-nano"
        )
        let maxTokenDefaults = parameterDefaults.first { $0.parameterID == .maxOutputTokens }
        XCTAssertTrue(maxTokenDefaults?.isRequired ?? false)
        XCTAssertTrue(maxTokenDefaults?.isEnabledByDefault ?? false)
        XCTAssertEqual(maxTokenDefaults?.defaultValue, .integer(4096))
        XCTAssertEqual(parameterDefaults.first { $0.parameterID == .temperature }?.support, .unsupported)

        let aggregatorMapping = catalog.parameterMappings(
            providerID: .openRouter,
            adapterID: .openAICompatibleChatCompletions,
            modelID: "openai/gpt-5-mini"
        ).first { $0.parameterID == .maxOutputTokens }
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
                    "capabilities": .array([.string("tools")]),
                    "supports_streaming": .boolean(false),
                    "supported_parameters": .array([.string("temperature")])
                ])
            ],
            profile: profile
        )

        XCTAssertEqual(models.first?.contextSize, 999)
        XCTAssertTrue(models.first?.capabilityClaims.contains {
            $0.capability == .image && $0.state == .supported
        } ?? false)
        XCTAssertTrue(models.first?.capabilityClaims.contains {
            $0.capability == .tools && $0.state == .supported
        } ?? false)
        XCTAssertTrue(models.first?.capabilityClaims.contains {
            $0.capability == .streaming && $0.state == .unsupported
        } ?? false)
        XCTAssertEqual(
            models.first?.parameterSupportClaims,
            [LLMParameterSupportClaim(parameterID: .temperature, state: .supported)]
        )
    }

    func testModelMetadataDecoderLeavesMissingFieldsUnclaimed() {
        let profile = LLMProviderRegistry.shared.profile(for: .openRouter)
        let models = LLMModelMetadataDecoder.openAICompatibleCandidates(
            from: [.object(["id": .string("fallback-model")])],
            profile: profile
        )

        XCTAssertNil(models.first?.contextSize)
        XCTAssertEqual(models.first?.capabilityClaims, [])
        XCTAssertEqual(models.first?.parameterSupportClaims, [])
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
