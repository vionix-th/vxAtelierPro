import Foundation
import SwiftData

struct ConversationRunContextResolver {
    let registry: LLMProviderRegistry
    let toolCatalog: LLMToolCatalog

    init(
        registry: LLMProviderRegistry = .shared,
        toolCatalog: LLMToolCatalog = LLMToolRegistry.shared
    ) {
        self.registry = registry
        self.toolCatalog = toolCatalog
    }

    @MainActor
    func resolve(
        conversation: ConversationItem,
        apiConfig: APIConfigurationItem
    ) throws -> ConversationRunContext {
        let providerID = apiConfig.providerIDEnum
        let profile = registry.profile(for: providerID)
        conversation.options.syncTypedFieldsFromParameters()
        let endpoint = conversation.options.endpointOverrideFamily ?? apiConfig.defaultEndpointFamilyEnum
        guard profile.supportedEndpointFamilies.contains(endpoint) else {
            throw LLMProviderError.unsupportedCapability("\(profile.name) does not support \(endpoint.rawValue).")
        }

        let modelID = conversation.options.modelOverride
            ?? apiConfig.defaultModelID
            ?? profile.defaultModelID
        guard let modelID, !modelID.isEmpty else {
            throw LLMProviderError.invalidConfiguration("No model configured for \(profile.name).")
        }

        let options = conversation.options.generationOptions(
            resolvedModelID: modelID,
            resolvedEndpointFamily: endpoint
        )
        let tools = toolCatalog.allTools()
            .filter { conversation.options.isToolEnabled($0.name) }
            .map { LLMRequestEncoding.toolDefinition(from: $0) }

        return ConversationRunContext(
            conversationID: conversation.id,
            providerConfiguration: apiConfig.makeLLMProviderConfiguration(),
            providerProfile: profile,
            providerID: providerID,
            endpointFamily: endpoint,
            modelID: modelID,
            modelDescriptor: modelDescriptor(
                for: modelID,
                apiConfiguration: apiConfig,
                providerID: providerID,
                conversation: conversation
            ),
            messages: orderedMessages(in: conversation).map { $0.asDomainMessage() },
            tools: tools,
            options: options
        )
    }

    @MainActor
    private func orderedMessages(in conversation: ConversationItem) -> [MessageItem] {
        conversation.turns
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
            .flatMap { turn in
                [turn.userMessage] + turn.events.sorted { $0.timestamp < $1.timestamp }.map(\.message)
            }
    }

    @MainActor
    private func modelDescriptor(
        for modelID: String,
        apiConfiguration: APIConfigurationItem,
        providerID: LLMProviderID,
        conversation: ConversationItem
    ) -> LLMModelDescriptor? {
        guard let context = conversation.modelContext,
              let models = try? context.fetch(FetchDescriptor<ModelItem>()) else {
            return nil
        }
        let model = models.first { model in
            (model.modelID == modelID || model.name == modelID)
                && model.apiConfiguration?.id == apiConfiguration.id
                && (LLMProviderID(rawValue: model.providerID) ?? .customOpenAICompatible) == providerID
        }
        return model?.descriptor
    }
}

struct LLMRequestFactory {
    func makeRequest(from context: ConversationRunContext) throws -> LLMRequest {
        var request = LLMRequest(
            providerID: context.providerID,
            endpointFamily: context.endpointFamily,
            modelID: context.modelID,
            modelDescriptor: context.modelDescriptor,
            messages: context.messages,
            tools: context.tools,
            options: context.options
        )
        let streamEnabled = try LLMCapabilityValidator.resolveStreamEnabled(
            for: request,
            profile: context.providerProfile
        )
        request.options.streamMode = streamEnabled ? .enabled : .disabled
        try LLMCapabilityValidator.validate(request, profile: context.providerProfile)
        return request
    }
}
