import Foundation
import SwiftData

/// Resolves persisted conversation and API configuration into provider-neutral run context.
struct ConversationRunContextResolver {
    let registry: LLMProviderRegistry
    let toolCatalog: LLMToolCatalog
    let modelDescriptorResolver: LLMModelDescriptorResolver

    /// Creates a resolver with injectable provider and tool registries.
    init(
        registry: LLMProviderRegistry = .shared,
        toolCatalog: LLMToolCatalog = LLMToolRegistry.shared,
        modelDescriptorResolver: LLMModelDescriptorResolver = LLMModelDescriptorResolver()
    ) {
        self.registry = registry
        self.toolCatalog = toolCatalog
        self.modelDescriptorResolver = modelDescriptorResolver
    }

    /// Resolves model, endpoint, tools, options, and message history for one run.
    @MainActor
    func resolve(
        conversation: ConversationItem,
        apiConfig: APIConfigurationItem
    ) throws -> ConversationRunContext {
        let providerID = apiConfig.providerIDEnum
        let profile = registry.profile(for: providerID)
        let endpoint = conversation.options.endpointOverrideFamily ?? apiConfig.defaultEndpointFamilyEnum
        guard profile.supportedEndpointFamilies.contains(endpoint) else {
            throw LLMProviderError.unsupportedCapability("\(profile.name) does not support \(endpoint.rawValue).")
        }

        let modelID = conversation.options.modelOverride
            ?? modelDescriptorResolver.defaultModelID(for: providerID, apiConfiguration: apiConfig)
        guard let modelID, !modelID.isEmpty else {
            throw LLMProviderError.invalidConfiguration("No model configured for \(profile.name).")
        }

        let descriptor = try modelDescriptorResolver.descriptor(
            for: modelID,
            providerID: providerID,
            apiConfiguration: apiConfig,
            modelContext: conversation.modelContext,
            endpointFamilies: [endpoint]
        )
        let mappings = LLMParameterMappingResolver.resolve(
            providerID: providerID,
            endpointFamily: endpoint,
            modelID: modelID,
            modelDescriptor: descriptor
        )
        let options = conversation.options.generationOptions(
            resolvedModelID: modelID,
            resolvedEndpointFamily: endpoint,
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
            endpointFamily: endpoint,
            modelID: modelID,
            modelDescriptor: descriptor,
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
