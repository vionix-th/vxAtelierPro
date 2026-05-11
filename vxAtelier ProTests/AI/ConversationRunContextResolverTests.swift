import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ConversationRunContextResolverTests: XCTestCase {
    func testResolverAndFactoryResolveModelFromSelectedAPIConfiguration() throws {
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
        configA.defaultAdapterIDEnum = .openAIChatCompletions
        configB.defaultAdapterIDEnum = .openAIChatCompletions
        let modelA = ModelItem(modelID: "gpt-test", apiConfiguration: configA)
        let modelB = ModelItem(modelID: "gpt-test", apiConfiguration: configB)
        let mappingA = modelA.parameterMappings.first {
            $0.adapterIDEnum == .openAIChatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        mappingA?.wireKey = "max_tokens_a"
        mappingA?.markCustomized()
        let mappingB = modelB.parameterMappings.first {
            $0.adapterIDEnum == .openAIChatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        mappingB?.wireKey = "max_tokens_b"
        mappingB?.markCustomized()

        let options = ConversationOptions(apiConfiguration: configB)
        options.selectedModelID = "gpt-test"
        options.maxOutputTokens = 256
        let conversation = ConversationItem("Scoped model", options: options)

        env.modelContext.insert(configA)
        env.modelContext.insert(configB)
        env.modelContext.insert(modelA)
        env.modelContext.insert(modelB)
        env.modelContext.insert(conversation)

        let context = try ConversationRunContextResolver(
            toolCatalog: StaticLLMToolCatalog([])
        ).resolve(
            conversation: conversation,
            apiConfig: configB
        )
        let request = try LLMRequestFactory().makeRequest(from: context)

        let maxOutputMapping = request.parameterMappings.first {
            $0.adapterID == .openAIChatCompletions && $0.semanticParameterID == .maxOutputTokens
        }
        XCTAssertEqual(
            maxOutputMapping?.wireKey,
            "max_tokens_b",
            "Resolved wire key: \(maxOutputMapping?.wireKey ?? "nil")"
        )
    }

    func testResolverFailsWhenNoPersistedModelExists() throws {
        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test",
            defaultModel: "gpt-missing",
            providerID: .openAIPlatform
        )
        config.defaultAdapterIDEnum = .openAIResponses
        let options = ConversationOptions(apiConfiguration: config)
        let conversation = ConversationItem("No descriptor", options: options)
        env.modelContext.insert(config)
        env.modelContext.insert(conversation)

        XCTAssertThrowsError(try ConversationRunContextResolver(
            toolCatalog: StaticLLMToolCatalog([])
        ).resolve(
            conversation: conversation,
            apiConfig: config
        )) { error in
            XCTAssertEqual(error as? LLMProviderError, .invalidConfiguration("Model gpt-missing is not available for OpenAI."))
        }
    }

    func testRequestFactoryProducesStableRequestFromFixedContext() throws {
        let profile = LLMProviderRegistry.shared.profile(for: .openAIPlatform)
        let options = LLMGenerationOptions(
            modelID: "gpt-test",
            streamMode: .disabled
        )
        let context = ConversationRunContext(
            conversationID: TestEnvironment().createConversation().id,
            providerConfiguration: LLMProviderConfiguration(
                providerID: .openAIPlatform,
                baseURL: "https://unit.test/v1",
                credential: .secret("key")
            ),
            providerProfile: profile,
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "gpt-test",
            modelCapabilities: [.text, .tools, .strictTools, .jsonSchema, .jsonObject, .reasoning, .usage, .streaming],
            parameterMappings: LLMParameterMappingCatalog.defaults(
                providerID: .openAIPlatform,
                adapterID: .openAIResponses,
                modelID: "gpt-test"
            ),
            parameterAvailability: LLMParameterAvailabilityCatalog.defaults(
                providerID: .openAIPlatform,
                adapterID: .openAIResponses,
                modelID: "gpt-test"
            ),
            messages: [
                LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])
            ],
            tools: [],
            options: options
        )

        let factory = LLMRequestFactory()
        let first = try factory.makeRequest(from: context)
        let second = try factory.makeRequest(from: context)

        XCTAssertEqual(first, second)
    }
}
