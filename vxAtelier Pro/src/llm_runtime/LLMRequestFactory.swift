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

    /// Resolves model, endpoint, tools, options, and message history for one run.
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
            ?? LLMDefaultsCatalog.bundled.defaultModelID(for: providerID)
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
            modelDescriptor: try modelDescriptor(
                for: modelID,
                apiConfiguration: apiConfig,
                providerID: providerID,
                endpointFamily: endpoint,
                conversation: conversation
            ),
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

    /// Fetches stored model metadata for the selected API configuration when available.
    @MainActor
    private func modelDescriptor(
        for modelID: String,
        apiConfiguration: APIConfigurationItem,
        providerID: LLMProviderID,
        endpointFamily: LLMEndpointFamily,
        conversation: ConversationItem
    ) throws -> LLMModelDescriptor? {
        guard let context = conversation.modelContext else {
            throw LLMProviderError.invalidConfiguration("Conversation has no model context while resolving descriptor for \(modelID).")
        }
        let requestedModelID = modelID
        let requestedProviderID = providerID.rawValue
        let descriptor = FetchDescriptor<ModelItem>(
            predicate: #Predicate<ModelItem> { model in
                (model.modelID == requestedModelID || model.name == requestedModelID)
                    && model.providerID == requestedProviderID
            }
        )
        let models: [ModelItem]
        do {
            models = try context.fetch(descriptor)
        } catch {
            throw LLMProviderError.invalidConfiguration("Failed to fetch model descriptor for \(modelID) in API configuration \(apiConfiguration.name): \(error.localizedDescription)")
        }
        let model = models.first { model in
            model.apiConfiguration?.id == apiConfiguration.id
        }
        if let model {
            return model.descriptor
        }
        var defaultDescriptor = LLMDefaultsCatalog.bundled.modelDescriptor(
            providerID: providerID,
            modelID: modelID,
            endpointFamilies: nil
        )
        if defaultDescriptor?.endpointFamilies.isEmpty == true {
            defaultDescriptor?.endpointFamilies = [endpointFamily]
        }
        return defaultDescriptor
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
