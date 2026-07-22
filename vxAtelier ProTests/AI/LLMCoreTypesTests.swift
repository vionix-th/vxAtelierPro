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
        let zen = registry.profile(for: .openCodeZen)
        XCTAssertEqual(zen.defaultBaseURL, "https://opencode.ai/zen/v1")
        XCTAssertEqual(zen.authKind, .bearerToken)
        XCTAssertEqual(zen.defaultAdapterID, .openAIResponses)
        XCTAssertEqual(zen.adapterSelectionPolicy, .model)
        XCTAssertEqual(
            Set(zen.supportedAdapterIDs),
            Set([.openAIResponses, .anthropicMessages, .openAICompatibleChatCompletions])
        )
        XCTAssertEqual(registry.profile(for: .appleIntelligence).transportKind, .localSystem)
        XCTAssertFalse(registry.profile(for: .appleIntelligence).requiresCredential)
        XCTAssertFalse(registry.profile(for: .appleIntelligence).requiresBaseURL)
        XCTAssertEqual(registry.profile(for: .appleIntelligence).defaultAdapterID, .foundationModels)
        XCTAssertEqual(LLMProviderRegistry.providerID(fromProviderName: "Apple Intelligence"), .appleIntelligence)
        XCTAssertEqual(LLMProviderRegistry.providerID(fromProviderName: "LM Studio"), .lmStudio)
        XCTAssertEqual(LLMProviderRegistry.providerID(fromProviderName: "OpenRouter"), .openRouter)
        XCTAssertEqual(LLMProviderRegistry.providerID(fromProviderName: "OpenCode Zen"), .openCodeZen)
        XCTAssertTrue(
            registry.adapter(for: .openAIResponses, providerID: .openCodeZen)
                is OpenCodeZenAdapter
        )
    }

    func testBundledDefaultsProvideProviderDefaultModels() {
        let defaults = LLMDefaultsCatalog.bundled

        XCTAssertEqual(defaults.defaultModelID(for: .openAIPlatform), "gpt-5.4-nano")
        XCTAssertEqual(defaults.defaultModelID(for: .openAICodexChatGPTSubscription), "gpt-5.5")
        XCTAssertEqual(defaults.defaultModelID(for: .openCodeZen), "gpt-5.6-terra")
        XCTAssertEqual(defaults.defaultModelID(for: .appleIntelligence), "apple-intelligence-default")
        XCTAssertEqual(defaults.defaultModelID(for: .anthropic), "claude-sonnet-4-6")
        XCTAssertEqual(defaults.defaultModelID(for: .openRouter), "openai/gpt-5.4-nano")
        XCTAssertEqual(defaults.defaultModelID(for: .xAI), "grok-4.3")
        XCTAssertEqual(defaults.defaultModelID(for: .deepSeek), "deepseek-v4-flash")
        XCTAssertNil(defaults.defaultModelID(for: .customOpenAICompatible))
    }

    func testOpenCodeZenCatalogRoutesAndEnrichesModels() throws {
        let metadata: [String: JSONValue] = [
            "name": .string("GPT-5.6 Terra"),
            "attachment": .boolean(true),
            "reasoning": .boolean(true),
            "tool_call": .boolean(true),
            "structured_output": .boolean(true),
            "modalities": .object([
                "input": .array([.string("text"), .string("image"), .string("pdf")])
            ]),
            "limit": .object(["context": .integer(1_050_000)]),
            "provider": .object(["npm": .string("@ai-sdk/openai")])
        ]

        let candidate = try XCTUnwrap(
            OpenCodeZenAdapter.candidate(modelID: "gpt-5.6-terra", metadata: metadata)
        )
        XCTAssertEqual(candidate.displayName, "GPT-5.6 Terra")
        XCTAssertEqual(candidate.adapterID, .openAIResponses)
        XCTAssertEqual(candidate.contextSize, 1_050_000)
        XCTAssertTrue(candidate.capabilities.contains(.image))
        XCTAssertTrue(candidate.capabilities.contains(.file))
        XCTAssertTrue(candidate.capabilities.contains(.tools))
        XCTAssertTrue(candidate.capabilities.contains(.jsonSchema))
        XCTAssertTrue(candidate.capabilities.contains(.reasoning))

        XCTAssertEqual(
            OpenCodeZenAdapter.adapterID(modelID: "claude-sonnet-4-6", metadata: nil),
            .anthropicMessages
        )
        XCTAssertEqual(
            OpenCodeZenAdapter.adapterID(modelID: "minimax-m3", metadata: nil),
            .openAICompatibleChatCompletions
        )
        XCTAssertNil(OpenCodeZenAdapter.adapterID(modelID: "gemini-3.5-flash", metadata: nil))
        XCTAssertNil(OpenCodeZenAdapter.candidate(
            modelID: "future-model",
            metadata: ["provider": .object(["npm": .string("@ai-sdk/future")])]
        ))
    }

    func testOpenCodeZenUsesAdapterSpecificAuthenticationHeaders() {
        func headers(for adapterID: LLMAdapterID) -> [String: String] {
            LLMProviderHeaderResolver.headers(for: LLMProviderConfiguration(
                providerID: .openCodeZen,
                authKind: OpenCodeZenAdapter.authKind(for: adapterID),
                baseURL: "https://opencode.ai/zen/v1",
                credential: .secret("zen-secret")
            ))
        }

        XCTAssertEqual(headers(for: .openAIResponses)["Authorization"], "Bearer zen-secret")
        XCTAssertEqual(headers(for: .openAICompatibleChatCompletions)["Authorization"], "Bearer zen-secret")
        XCTAssertEqual(headers(for: .anthropicMessages)["x-api-key"], "zen-secret")
        XCTAssertEqual(headers(for: .anthropicMessages)["anthropic-version"], "2023-06-01")
        XCTAssertNil(headers(for: .anthropicMessages)["Authorization"])
    }

    func testCapabilityTaxonomyCoversContentAndRuntimeFeatures() {
        XCTAssertTrue(LLMModelCapability.allCases.contains(.text))
        XCTAssertTrue(LLMModelCapability.allCases.contains(.image))
        XCTAssertTrue(LLMModelCapability.allCases.contains(.tools))
        XCTAssertTrue(LLMModelCapability.allCases.contains(.reasoning))
    }

    func testBundledDefaultsProvideCurrentModelMetadata() {
        let defaults = LLMDefaultsCatalog.bundled

        let openAI = defaults.modelDefaults(providerID: .openAIPlatform, adapterID: .openAIResponses, modelID: "gpt-5.4-nano")
        XCTAssertEqual(openAI?.contextSize, 400000)
        XCTAssertTrue(openAI?.capabilities?.contains(.text) ?? false)
        XCTAssertTrue(openAI?.capabilities?.contains(.image) ?? false)
        XCTAssertTrue(openAI?.capabilities?.contains(.file) ?? false)
        XCTAssertTrue(openAI?.capabilities?.contains(.reasoning) ?? false)

        let anthropic = defaults.modelDefaults(providerID: .anthropic, adapterID: .anthropicMessages, modelID: "claude-sonnet-4-6")
        XCTAssertEqual(anthropic?.contextSize, 1000000)
        XCTAssertTrue(anthropic?.capabilities?.contains(.text) ?? false)
        XCTAssertTrue(anthropic?.capabilities?.contains(.image) ?? false)

        let apple = defaults.modelDefaults(providerID: .appleIntelligence, adapterID: .foundationModels, modelID: "apple-intelligence-default")
        XCTAssertEqual(apple?.contextSize, 4096)
        XCTAssertTrue(apple?.capabilities?.contains(.text) ?? false)
        XCTAssertTrue(apple?.capabilities?.contains(.tools) ?? false)
        XCTAssertTrue(apple?.capabilities?.contains(.streaming) ?? false)

        let xAI = defaults.modelDefaults(providerID: .xAI, adapterID: .openAICompatibleChatCompletions, modelID: "grok-4.3")
        XCTAssertEqual(xAI?.contextSize, 1000000)
        XCTAssertTrue(xAI?.capabilities?.contains(.jsonSchema) ?? false)

        let deepSeek = defaults.modelDefaults(providerID: .deepSeek, adapterID: .openAICompatibleChatCompletions, modelID: "deepseek-v4-flash")
        XCTAssertEqual(deepSeek?.contextSize, 1000000)
        XCTAssertTrue(deepSeek?.capabilities?.contains(.tools) ?? false)
    }

    func testResolverProvidesUnknownFallbackProfile() {
        let catalog = try! LLMDefaultsCatalog(data: Data("""
        {
          "providerDefaults": [],
          "rules": []
        }
        """.utf8))
        let profile = LLMModelProfileResolver(
            defaultsCatalog: catalog,
            fallbackContextSize: 4096
        ).resolve(
            providerID: .customOpenAICompatible,
            adapterID: .openAICompatibleChatCompletions,
            modelID: "unknown-model",
            metadata: nil
        )

        XCTAssertEqual(profile.displayName, "unknown-model")
        XCTAssertEqual(profile.displayNameSource, .fallback)
        XCTAssertEqual(profile.contextSize, 4096)
        XCTAssertEqual(profile.capabilities[.text], LLMSupport(state: .unknown, source: .fallback))
    }

    func testCatalogCanProvideMinimalUnknownModelDefaults() throws {
        let defaults = try LLMDefaultsCatalog(data: Data("""
        {
          "providerDefaults": [],
          "rules": [
            {
              "level": "adapter",
              "modelDefaults": {
                "capabilities": ["text"]
              }
            }
          ]
        }
        """.utf8))
        let profile = LLMModelProfileResolver(
            defaultsCatalog: defaults,
            fallbackContextSize: 4096
        ).resolve(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "unknown-future-model",
            metadata: nil
        )

        XCTAssertEqual(profile.capabilities[.text], LLMSupport(state: .supported, source: .catalog))
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
              "level": "model",
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
        XCTAssertEqual(catalog.modelDefaults(providerID: .openAIPlatform, adapterID: .openAIResponses, modelID: "unit-anything")?.capabilities, [.text, .streaming])
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
              "level": "adapter",
              "match": {
                "adapterID": "openAIChatCompletions"
              },
              "parameters": [
                {
                  "id": "max_output_tokens",
                  "supported": true,
                  "mapping": {"kind": "key"}
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
              "level": "provider",
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
              "level": "model",
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
              "level": "adapter",
              "match": {"adapterID": "openAIChatCompletions"},
              "parameters": [
                {
                  "id": "max_output_tokens",
                  "supported": true,
                  "mapping": {"kind": "key", "key": "max_tokens"},
                  "enabledByDefault": true
                }
              ]
            },
            {
              "level": "adapter",
              "match": {"adapterID": "openAICompatibleChatCompletions"},
              "parameters": [
                {
                  "id": "max_output_tokens",
                  "supported": true,
                  "mapping": {"kind": "key", "key": "max_tokens"}
                }
              ]
            },
            {
              "level": "provider",
              "match": {"providerRegex": "^openAIPlatform$"},
              "modelDefaults": {"capabilities": ["text", "streaming"]}
            },
            {
              "level": "model",
              "match": {"providerRegex": "^openAIPlatform$", "modelRegex": "^vision-"},
              "modelDefaults": {"capabilities": ["image", "jsonObject"]}
            },
            {
              "level": "model",
              "match": {
                "modelRegex": "(^|.*/)gpt-5([-.].*)?$",
                "adapterID": "openAIChatCompletions"
              },
              "parameters": [
                {
                  "id": "max_output_tokens",
                  "mapping": {"kind": "key", "key": "max_completion_tokens"},
                  "required": true,
                  "defaultValue": 4096
                },
                {"id": "temperature", "supported": false}
              ]
            },
            {
              "level": "model",
              "match": {
                "modelRegex": "(^|.*/)gpt-5([-.].*)?$",
                "adapterID": "openAICompatibleChatCompletions"
              },
              "parameters": [
                {
                  "id": "max_output_tokens",
                  "mapping": {"kind": "key", "key": "max_completion_tokens"}
                }
              ]
            }
          ]
        }
        """.utf8))

        let modelDefaults = catalog.modelDefaults(providerID: .openAIPlatform, adapterID: .openAIChatCompletions, modelID: "vision-large")
        XCTAssertEqual(modelDefaults?.capabilities, [.image, .jsonObject])

        let mapping = catalog.parameterDefaults(
            providerID: .openAIPlatform,
            adapterID: .openAIChatCompletions,
            modelID: "gpt-5.4-nano"
        ).first { $0.parameterID == .maxOutputTokens }?.mapping
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
        XCTAssertEqual(parameterDefaults.first { $0.parameterID == .temperature }?.isSupported, false)

        let aggregatorMapping = catalog.parameterDefaults(
            providerID: .openRouter,
            adapterID: .openAICompatibleChatCompletions,
            modelID: "openai/gpt-5-mini"
        ).first { $0.parameterID == .maxOutputTokens }?.mapping
        XCTAssertEqual(aggregatorMapping?.wireKey, "max_completion_tokens")
    }

    func testModelMetadataDecoderUsesProviderMetadataOverDefaults() {
        let profile = LLMProviderRegistry.shared.profile(for: .openRouter)
        let models = LLMModelMetadataDecoder.openAICompatibleMetadata(
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
        let models = LLMModelMetadataDecoder.openAICompatibleMetadata(
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
