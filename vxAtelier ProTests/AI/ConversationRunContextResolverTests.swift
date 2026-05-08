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
        configA.defaultEndpointFamilyEnum = .chatCompletions
        configB.defaultEndpointFamilyEnum = .chatCompletions
        let descriptor = LLMModelDescriptor(
            id: "gpt-test",
            providerID: .openAIPlatform,
            endpointFamilies: [.chatCompletions],
            modalities: [.text],
            parameterMappings: [],
            schemaFeatures: [.streaming]
        )
        let modelA = ModelItem(descriptor: descriptor, apiConfiguration: configA)
        let modelB = ModelItem(descriptor: descriptor, apiConfiguration: configB)
        let mappingA = modelA.parameterMappings.first {
            $0.endpointFamilyEnum == .chatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        mappingA?.wireKey = "max_tokens_a"
        mappingA?.markCustomized()
        let mappingB = modelB.parameterMappings.first {
            $0.endpointFamilyEnum == .chatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        mappingB?.wireKey = "max_tokens_b"
        mappingB?.markCustomized()

        let options = ConversationOptions(apiConfiguration: configB)
        options.selectedModelID = "gpt-test"
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

        let maxOutputMapping = request.modelDescriptor?.parameterMappings.first {
            $0.endpointFamily == .chatCompletions && $0.semanticParameterID == .maxOutputTokens
        }
        XCTAssertEqual(
            maxOutputMapping?.wireKey,
            "max_tokens_b",
            "Resolved wire key: \(maxOutputMapping?.wireKey ?? "nil"), descriptor config provider: \(request.modelDescriptor?.providerID.rawValue ?? "nil")"
        )
    }

    func testResolverSynthesizesDefaultDescriptorWhenNoMatchingModelExists() throws {
        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test",
            defaultModel: "gpt-missing",
            providerID: .openAIPlatform
        )
        config.defaultEndpointFamilyEnum = .responses
        let options = ConversationOptions(apiConfiguration: config)
        let conversation = ConversationItem("No descriptor", options: options)
        env.modelContext.insert(config)
        env.modelContext.insert(conversation)

        let context = try ConversationRunContextResolver(
            toolCatalog: StaticLLMToolCatalog([])
        ).resolve(
            conversation: conversation,
            apiConfig: config
        )

        XCTAssertEqual(context.modelDescriptor?.id, "gpt-missing")
        XCTAssertEqual(context.modelDescriptor?.providerID, .openAIPlatform)
        XCTAssertTrue(context.modelDescriptor?.schemaFeatures.contains(.streaming) ?? false)
    }

    func testRequestFactoryProducesStableRequestFromFixedContext() throws {
        let profile = LLMProviderRegistry.shared.profile(for: .openAIPlatform)
        let options = LLMGenerationOptions(
            modelID: "gpt-test",
            endpointFamily: .responses,
            streamMode: .disabled
        )
        let context = ConversationRunContext(
            conversationID: TestEnvironment().createConversation().id,
            providerConfiguration: LLMProviderConfiguration(
                providerID: .openAIPlatform,
                baseURL: "https://unit.test/v1",
                credential: .secret("key"),
                endpointPaths: profile.endpointPaths
            ),
            providerProfile: profile,
            providerID: .openAIPlatform,
            endpointFamily: .responses,
            modelID: "gpt-test",
            modelDescriptor: LLMModelDescriptor(
                id: "gpt-test",
                providerID: .openAIPlatform,
                endpointFamilies: [.responses],
                modalities: [.text],
                parameterMappings: LLMParameterMappingCatalog.defaults(
                    providerID: .openAIPlatform,
                    endpointFamily: .responses,
                    modelID: "gpt-test"
                ),
                schemaFeatures: [.tools, .strictTools, .jsonSchema, .jsonObject, .reasoning, .usage, .streaming]
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
