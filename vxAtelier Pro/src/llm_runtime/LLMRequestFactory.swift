import Foundation
import SwiftData

/// Resolves persisted conversation and API configuration into provider-neutral run context.
struct ConversationRunContextResolver {
    let registry: LLMProviderRegistry
    let toolCatalog: LLMToolCatalog

    /// Creates a resolver with injectable provider and tool registries.
    init(
        registry: LLMProviderRegistry = .shared,
        toolCatalog: LLMToolCatalog = LLMToolRegistry.shared
    ) {
        self.registry = registry
        self.toolCatalog = toolCatalog
    }

    /// Resolves model, adapter, tools, options, and message history for one run.
    @MainActor
    func resolve(
        conversation: ConversationItem,
        apiConfig: APIConfigurationItem
    ) throws -> ConversationRunContext {
        let providerID = apiConfig.providerIDEnum
        let profile = registry.profile(for: providerID)
        let adapterID = apiConfig.defaultAdapterIDEnum
        guard profile.supportedAdapterIDs.contains(adapterID) else {
            throw LLMProviderError.unsupportedCapability("\(profile.name) does not support \(adapterID.rawValue).")
        }

        let modelID = conversation.options.selectedModelID ?? apiConfig.defaultModelID
        guard let modelID, !modelID.isEmpty else {
            throw LLMProviderError.invalidConfiguration("No model configured for \(profile.name).")
        }

        guard let model = apiConfig.models.first(where: { $0.modelID == modelID }) else {
            throw LLMProviderError.invalidConfiguration("Model \(modelID) is not available for \(apiConfig.name).")
        }
        let mappings = LLMParameterMappingResolver.resolve(
            adapterID: adapterID,
            mappings: model.parameterMappings.map(\.descriptor)
        )
        let options = conversation.options.generationOptions(
            resolvedModelID: modelID,
            resolvedAdapterID: adapterID,
            mappings: mappings
        )
        let tools = toolCatalog.allTools()
            .filter { conversation.options.isToolEnabled($0.name) }
            .map { LLMRequestEncoding.toolDefinition(from: $0) }

        return ConversationRunContext(
            conversationID: conversation.id,
            providerConfiguration: apiConfig.makeLLMProviderConfiguration(),
            providerProfile: profile,
            providerID: providerID,
            adapterID: adapterID,
            modelID: modelID,
            modelCapabilities: model.capabilities,
            parameterMappings: Array(mappings.values),
            messages: orderedMessages(in: conversation).map { $0.asDomainMessage() },
            tools: tools,
            options: options
        )
    }

    /// Returns conversation messages in provider replay order.
    @MainActor
    private func orderedMessages(in conversation: ConversationItem) -> [MessageItem] {
        conversation.turns
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
            .flatMap { turn in
                [turn.userMessage] + turn.events.sorted { $0.timestamp < $1.timestamp }.map(\.message)
            }
    }

}

/// Builds and validates provider-neutral `LLMRequest` values from resolved run context.
struct LLMRequestFactory {
    /// Creates a request with concrete streaming mode resolved before final validation.
    func makeRequest(from context: ConversationRunContext) throws -> LLMRequest {
        var request = LLMRequest(
            providerID: context.providerID,
            adapterID: context.adapterID,
            modelID: context.modelID,
            modelCapabilities: context.modelCapabilities,
            parameterMappings: context.parameterMappings,
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
