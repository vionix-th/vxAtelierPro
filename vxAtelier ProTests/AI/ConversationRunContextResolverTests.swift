import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ConversationRunContextResolverTests: XCTestCase {
    func testResolverAndFactoryResolveModelFromSelectedAPIConfiguration() async throws {
        let env = TestEnvironment()
        let configA = APIConfigurationItem(
            name: "OpenAI A",
            apiKey: "key-a",
            baseURL: "https://unit.test/a",
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let configB = APIConfigurationItem(
            name: "OpenAI B",
            apiKey: "key-b",
            baseURL: "https://unit.test/b",
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        configA.adapterID = LLMAdapterID.openAIChatCompletions.rawValue
        configB.adapterID = LLMAdapterID.openAIChatCompletions.rawValue
        let modelA = ModelItem(modelID: "gpt-test", apiConfiguration: configA)
        let modelB = ModelItem(modelID: "gpt-test", apiConfiguration: configB)
        modelA.parameterOverrides = [ModelParameterOverrideItem(
            adapterID: .openAIChatCompletions,
            parameterID: .maxOutputTokens,
            mapping: LLMParameterMapping(
                adapterID: .openAIChatCompletions,
                parameterID: .maxOutputTokens,
                wireKey: "max_tokens_a"
            )
        )]
        modelB.parameterOverrides = [ModelParameterOverrideItem(
            adapterID: .openAIChatCompletions,
            parameterID: .maxOutputTokens,
            mapping: LLMParameterMapping(
                adapterID: .openAIChatCompletions,
                parameterID: .maxOutputTokens,
                wireKey: "max_tokens_b"
            )
        )]

        let options = ConversationOptions(apiConfiguration: configB)
        options.selectedModelID = "gpt-test"
        options.maxOutputTokens = 256
        options.setParameterEnabled(.maxOutputTokens, enabled: true)
        let conversation = ConversationItem("Scoped model", options: options)

        env.modelContext.insert(configA)
        env.modelContext.insert(configB)
        env.modelContext.insert(modelA)
        env.modelContext.insert(modelB)
        env.modelContext.insert(conversation)

        let context = try await ConversationRunContextResolver(
            toolCatalog: StaticLLMToolCatalog([])
        ).resolve(
            conversation: conversation,
            apiConfig: configB
        )
        let request = LLMGenerationRequestFactory().makeRequest(from: context)

        let maxOutputMapping = request.activeParameters.first {
            $0.parameterID == .maxOutputTokens
        }?.mapping
        XCTAssertEqual(
            maxOutputMapping?.wireKey,
            "max_tokens_b",
            "Resolved wire key: \(maxOutputMapping?.wireKey ?? "nil")"
        )
    }

    func testResolverFailsWhenNoPersistedModelExists() async throws {
        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test",
            defaultModel: "gpt-missing",
            providerID: .openAIPlatform
        )
        config.adapterID = LLMAdapterID.openAIResponses.rawValue
        let options = ConversationOptions(apiConfiguration: config)
        let conversation = ConversationItem("No descriptor", options: options)
        env.modelContext.insert(config)
        env.modelContext.insert(conversation)

        do {
            _ = try await ConversationRunContextResolver(
                toolCatalog: StaticLLMToolCatalog([])
            ).resolve(
                conversation: conversation,
                apiConfig: config
            )
            XCTFail("Expected resolver to reject a missing persisted model.")
        } catch {
            XCTAssertEqual(error as? LLMProviderError, .invalidConfiguration("Model gpt-missing is not available for OpenAI."))
        }
    }

    func testRequestFactoryProducesStableRequestFromFixedContext() throws {
        let options = LLMGenerationOptions(
            modelID: "gpt-test",
            streamMode: .disabled
        )
        let context = ConversationRunContext(
            conversationID: TestEnvironment().createConversation().id,
            resolvedRoute: LLMResolvedProviderRoute(
                providerID: .openAIPlatform,
                adapterID: .openAIResponses,
                configuration: LLMProviderConfiguration(
                    providerID: .openAIPlatform,
                    baseURL: "https://unit.test/v1",
                    credential: .secret("key")
                )
            ),
            modelID: "gpt-test",
            activeParameters: [],
            messages: [
                LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])
            ],
            tools: [],
            options: options
        )

        let factory = LLMGenerationRequestFactory()
        let first = factory.makeRequest(from: context)
        let second = factory.makeRequest(from: context)

        XCTAssertEqual(first, second)
    }
}
