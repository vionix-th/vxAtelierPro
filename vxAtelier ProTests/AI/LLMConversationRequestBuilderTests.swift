import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMConversationRequestBuilderTests: XCTestCase {
    func testRequestBuilderResolvesModelFromSelectedAPIConfiguration() throws {
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
            supportedParameters: LLMProviderRegistry.shared.profile(for: .openAIPlatform).supportedParameters,
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

        let options = ConversationOptions(apiConfiguration: configB, shouldSetupParameters: false)
        options.modelOverride = "gpt-test"
        let conversation = ConversationItem("Scoped model", options: options)

        env.modelContext.insert(configA)
        env.modelContext.insert(configB)
        env.modelContext.insert(modelA)
        env.modelContext.insert(modelB)
        env.modelContext.insert(conversation)

        let request = try LLMConversationRequestBuilder().makeRequest(
            conversation: conversation,
            apiConfig: configB
        )

        let maxOutputMapping = request.modelDescriptor?.parameterMappings.first {
            $0.endpointFamily == .chatCompletions && $0.semanticParameterID == .maxOutputTokens
        }
        XCTAssertEqual(
            maxOutputMapping?.wireKey,
            "max_tokens_b",
            "Resolved wire key: \(maxOutputMapping?.wireKey ?? "nil"), descriptor config provider: \(request.modelDescriptor?.providerID.rawValue ?? "nil")"
        )
    }
}
