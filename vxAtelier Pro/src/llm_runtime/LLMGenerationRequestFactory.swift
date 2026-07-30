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
    ) async throws -> ConversationRunContext {
        let providerID = apiConfig.providerIDEnum
        let adapterID = apiConfig.defaultAdapterIDEnum
        try registry.validateRoute(adapterID: adapterID, providerID: providerID)

        let modelID = conversation.options.selectedModelID ?? apiConfig.defaultModelID
        guard let modelID, !modelID.isEmpty else {
            throw LLMProviderError.invalidConfiguration("No model configured for \(apiConfig.name).")
        }
        guard let model = apiConfig.models.first(where: { $0.modelID == modelID }) else {
            throw LLMProviderError.invalidConfiguration("Model \(modelID) is not available for \(apiConfig.name).")
        }

        let rawOptions = conversation.options.generationOptions(resolvedModelID: modelID)
        let resolvedParameters = try LLMGenerationOptionsResolver.resolve(
            options: rawOptions,
            conversationPreferences: conversation.options.parameterInclusionPreferences,
            providedParameterIDs: Set(conversation.options.decodedParameterValues.keys.compactMap(LLMParameterID.init(rawValue:))),
            parameterProfiles: model.modelProfile.parameters
        )
        let tools = toolCatalog.allTools()
            .filter { conversation.options.isToolEnabled($0.name) }
            .map { LLMRequestEncoding.toolDefinition(from: $0) }
        let messages = orderedMessages(in: conversation).map { $0.asDomainMessage() }
        try ConversationHistoryValidator.validate(messages)

        return ConversationRunContext(
            conversationID: conversation.persistentModelID,
            providerConfiguration: try await CodexChatGPTOAuthService.resolvedProviderConfiguration(for: apiConfig),
            providerID: providerID,
            adapterID: adapterID,
            modelID: modelID,
            activeParameters: resolvedParameters.activeParameters,
            messages: messages,
            tools: tools,
            options: resolvedParameters.options
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
}

enum ConversationHistoryValidator {
    static func validate(_ messages: [LLMMessage]) throws {
        var knownToolIDs = Set<String>()
        var answeredToolIDs = Set<String>()
        var pendingToolIDs: [String] = []

        for message in messages {
            if message.role != "tool", !pendingToolIDs.isEmpty {
                throw LLMProviderError.invalidConversationState(
                    "Tool results must immediately follow their assistant tool calls."
                )
            }
            if message.role == "assistant" {
                let ids = message.toolCalls.sorted { $0.index < $1.index }.map { $0.callID ?? $0.id }
                guard Set(ids).count == ids.count, knownToolIDs.isDisjoint(with: ids) else {
                    throw LLMProviderError.invalidConversationState("Assistant tool calls must have unique ids.")
                }
                knownToolIDs.formUnion(ids)
                pendingToolIDs = ids
            } else if message.role == "tool" {
                guard let toolCallID = message.toolCallID, !toolCallID.isEmpty else {
                    throw LLMProviderError.invalidConversationState("Tool result requires a tool-call id.")
                }
                guard knownToolIDs.contains(toolCallID) else {
                    throw LLMProviderError.invalidConversationState(
                        "Tool result \(toolCallID) has no prior assistant tool call."
                    )
                }
                guard !answeredToolIDs.contains(toolCallID),
                      let index = pendingToolIDs.firstIndex(of: toolCallID) else {
                    throw LLMProviderError.invalidConversationState("Tool result \(toolCallID) is duplicated or out of order.")
                }
                pendingToolIDs.remove(at: index)
                answeredToolIDs.insert(toolCallID)
            }
        }
        guard pendingToolIDs.isEmpty else {
            throw LLMProviderError.invalidConversationState("Assistant tool calls must be followed by tool results.")
        }
    }
}

struct LLMGenerationRequestFactory {
    func makeRequest(from context: ConversationRunContext) -> LLMGenerationRequest {
        LLMGenerationRequest(
            providerID: context.providerID,
            adapterID: context.adapterID,
            modelID: context.modelID,
            activeParameters: context.activeParameters,
            messages: context.messages,
            tools: context.tools,
            options: context.options
        )
    }
}
