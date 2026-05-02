import Foundation
import SwiftData

struct LLMConversationRequestBuilder {
    let registry: LLMProviderRegistry

    init(registry: LLMProviderRegistry = .shared) {
        self.registry = registry
    }

    @MainActor
    func makeRequest(conversation: ConversationItem, apiConfig: APIConfigurationItem) throws -> LLMRequest {
        let providerID = registry.resolveProviderID(for: apiConfig)
        let profile = registry.profile(for: providerID)
        conversation.options.syncTypedFieldsFromParameters()
        let endpoint = resolveEndpointFamily(options: conversation.options, config: apiConfig)
        guard profile.supportedEndpointFamilies.contains(endpoint) else {
            throw LLMProviderError.unsupportedCapability("\(profile.name) does not support \(endpoint.rawValue).")
        }

        let modelID = conversation.options.modelOverride
            ?? apiConfig.defaultModelID
            ?? profile.defaultModelID
        guard let modelID, !modelID.isEmpty else {
            throw LLMProviderError.invalidConfiguration("No model configured for \(profile.name).")
        }

        let generationOptions = conversation.options.generationOptions(
            resolvedModelID: modelID,
            resolvedEndpointFamily: endpoint
        )
        let enabledTools = AIToolRegistry.shared.getTools()
            .filter { conversation.options.isToolEnabled($0.name) }

        var request = LLMRequest(
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
            tools: enabledTools.map { LLMRequestEncoding.toolDefinition(from: $0) },
            options: generationOptions
        )
        let streamEnabled = try LLMCapabilityValidator.resolveStreamEnabled(for: request, profile: profile)
        request.options.streamMode = streamEnabled ? .enabled : .disabled
        try LLMCapabilityValidator.validate(request, profile: profile)
        return request
    }

    private func resolveEndpointFamily(
        options: ConversationOptions,
        config: APIConfigurationItem
    ) -> LLMEndpointFamily {
        options.endpointOverrideFamily ?? config.defaultEndpointFamilyEnum
    }

    private func orderedMessages(in conversation: ConversationItem) -> [MessageItem] {
        conversation.turns
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
            .flatMap { turn in
                [turn.userMessage] + turn.events.sorted { $0.timestamp < $1.timestamp }.map(\.message)
            }
    }

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
        if let model {
            LLMParameterMappingCatalog.materializeDefaults(on: model, preserveCustomized: true)
        }
        return model?.descriptor
    }
}
