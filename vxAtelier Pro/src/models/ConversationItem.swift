import Foundation
import SwiftData
import SwiftUI

/// Represents a conversation between a user and an AI assistant.
///
/// This model stores a complete conversation, including:
/// - All messages and their content
/// - Configuration options for the AI service
/// - Status information (active, archived, trashed)
/// - Project organization
/// - Tool call history and capabilities
@Model
final class ConversationItem {
    /// When this conversation was created
    var timestamp: Date

    /// Display name for this conversation
    var title: String

    /// Conversation turns (user message + assistant/tool events)
    @Relationship(deleteRule: .cascade, inverse: \ConversationTurn.conversation) var turns: [ConversationTurn] = []

    /// Configuration options for this conversation
    @Relationship(deleteRule: .cascade) var options: ConversationOptions

    /// Optional project this conversation belongs to
    @Relationship(deleteRule: .nullify) var project: ProjectItem? = nil

    /// Current status of this conversation (active, archived, trashed)
    var status: ItemStatus = ItemStatus.active

    /// Purpose of this conversation (system or user)
    var purpose: ConversationPurpose = ConversationItem.ConversationPurpose.user

    /// Estimated token count for the current context
    var tokenCount: Int = 0

    /// Total tokens used in all requests for this conversation
    var usedTokenCount: Int = 0

    /// Purpose categories for conversations
    enum ConversationPurpose: String, Codable {
        /// System-generated conversation
        case system = "System"

        /// User-created conversation
        case user = "User"
    }

    /// Whether this conversation is currently linked to the utility panel.
    var isUtilityConversation: Bool = false

    /// Creates a new conversation with a title and options.
    ///
    /// - Parameters:
    ///   - title: Display name for this conversation
    ///   - options: Configuration options, defaults to empty options
    convenience init(_ title: String, options: ConversationOptions = ConversationOptions()) {
        self.init(timestamp: Date(), title: title, options: options)
    }

    /// Creates a new conversation with specified properties.
    ///
    /// - Parameters:
    ///   - timestamp: When this conversation was created
    ///   - title: Display name for this conversation
    ///   - options: Configuration options
    init(timestamp: Date, title: String, options: ConversationOptions) {
        self.timestamp = timestamp
        self.title = title
        self.options = options
    }

    /// Creates a fork (copy) of this conversation up to a specific turn index (inclusive).
    ///
    /// - Parameter upToTurnIndex: Optional index of the last turn to include (inclusive). Nil means no turns.
    /// - Returns: A new conversation containing copied turns
    func fork(upToTurnIndex: Int?) -> ConversationItem {
        // Copy options
        let forkedOptions = self.options.copy()
        let forkedConversation = ConversationItem(
            timestamp: Date(),
            title: "\(self.title) (Fork)",
            options: forkedOptions
        )
        let sortedTurns = self.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
        guard let upTo = upToTurnIndex, upTo >= 0, upTo < sortedTurns.count else {
            forkedConversation.project = self.project
            return forkedConversation
        }
        for turn in sortedTurns[0...upTo] {
            // Deep copy userMessage
            let userMsgCopy = MessageItem(
                role: turn.userMessage.role,
                content: ContentItem(turn.userMessage.content.text, type: turn.userMessage.content.type),
                timestamp: turn.userMessage.timestamp,
                toolCallId: turn.userMessage.toolCallId,
                toolCallsData: turn.userMessage.toolCallsData
            )
            let turnCopy = ConversationTurn(
                sequenceNumber: turn.sequenceNumber,
                timestamp: turn.timestamp,
                userMessage: userMsgCopy,
                conversation: forkedConversation
            )
            // Deep copy events
            for event in turn.events {
                let eventMsgCopy = MessageItem(
                    role: event.message.role,
                    content: ContentItem(event.message.content.text, type: event.message.content.type),
                    timestamp: event.message.timestamp,
                    toolCallId: event.message.toolCallId,
                    toolCallsData: event.message.toolCallsData
                )
                let eventCopy = TurnEvent(type: event.type, timestamp: event.timestamp, message: eventMsgCopy, turn: turnCopy)
                turnCopy.events.append(eventCopy)
            }
            forkedConversation.turns.append(turnCopy)
        }
        forkedConversation.project = self.project
        return forkedConversation
    }

    /// Creates chat messages from the conversation's turn history.
    ///
    /// - Parameter service: The AI service to use
    /// - Returns: Array of chat messages formatted for the service
    private func createChatMessages(service: AIService) -> [AIChatMessage] {
        let allMessages: [MessageItem] = self.turns.flatMap { turn in
            [turn.userMessage] + turn.events.map { $0.message }
        }.sorted(by: { $0.timestamp < $1.timestamp })
        return allMessages.map { msg in
            return service.chat.createMessage(
                role: msg.role,
                content: msg.content.text,
                toolCalls: msg.getToolCalls(),
                toolCallId: msg.toolCallId
            )
        }
    }

    /// Creates a configured request with appropriate parameters.
    ///
    /// - Parameters:
    ///   - service: The AI service to use
    ///   - messages: Messages to include in the request
    ///   - enabledTools: Tools that are available for function calling
    /// - Returns: A configured request ready to send
    private func createConfiguredRequest(
        service: AIService,
        messages: [AIChatMessage],
        enabledTools: [AITool]
    ) -> AIChatCompletionRequest {
        // Create request using the service's chat
        var request = service.chat.createRequest(messages: messages)

        // Apply tools if enabled
        if !enabledTools.isEmpty {
            request.tools = enabledTools
            request.toolChoice = "auto"
        }

        // Apply parameters
        if let modifiedRequest = service.applyParameters(to: request, from: options.parameters)
            as? AIChatCompletionRequest
        {
            request = modifiedRequest
        }

        return request
    }

    public func forceUpdateTokenCount(updateContextCount: Bool, updateTotalCount: Bool) {
        updateTokenCount(updateContextCount: updateContextCount, updateTotalCount: updateTotalCount)
        vxAtelierPro.log.debug("Force Updated token count for conversation '\(title)': \(tokenCount)")
    }

    /// Updates the token count for the current context
    private func updateTokenCount(updateContextCount: Bool, updateTotalCount: Bool) {
        var newTokenCount = 0

        if updateContextCount {
            let allMessages: [MessageItem] = self.turns.flatMap { turn in
                [turn.userMessage] + turn.events.map { $0.message }
            }
            newTokenCount = allMessages.reduce(0) { sum, message in
                // Create a dummy AIChatMessage to use the extension method
                let chatMessage = DummyChatMessage(
                    role: message.role,
                    content: message.content.text,
                    toolCalls: message.getToolCalls(),
                    toolCallId: message.toolCallId
                )
                return sum + chatMessage.estimatedTokenCount()
            }
            tokenCount = newTokenCount
            vxAtelierPro.log.debug("Updated context token count for conversation '\(title)': \(newTokenCount)")
        }

        if updateTotalCount {
            usedTokenCount += newTokenCount
            vxAtelierPro.log.debug("Updated total token count for conversation '\(title)': \(usedTokenCount)")
        }
    }

    /// Helper class to utilize the AIChatMessage extension
    private struct DummyChatMessage: AIChatMessage {
        var role: String
        var content: String
        var toolCalls: [AIToolCall]?
        var toolCallId: String?
    }

    /// Adds a user message to the conversation.
    ///
    /// - Parameters:
    ///   - message: The message text
    @MainActor
    private func addUserMessage(_ message: String) {
        let userMsg = MessageItem(
            role: "user",
            content: ContentItem(message),
            timestamp: Date(),
            toolCallId: nil,
            toolCallsData: nil
        )
        // SwiftData relationship arrays are not ordered; compute next sequence from max
        let nextSequence = (self.turns.map { $0.sequenceNumber }.max() ?? -1) + 1
        let turn = ConversationTurn(sequenceNumber: nextSequence, timestamp: userMsg.timestamp, userMessage: userMsg, conversation: self)
        self.turns.append(turn)
        updateTokenCount(updateContextCount: true, updateTotalCount: false)
    }

    /// Adds an AI response to the conversation.
    ///
    /// - Parameters:
    ///   - response: The AI response
    ///   - timestamp: When this response was received, defaults to current time
    @MainActor
    private func addResponseToConversation(
        response: AIChatCompletionResponse,
        timestamp: Date = Date()
    ) {
        if let content = response.content {
            let assistantMsg = MessageItem(
                role: "assistant",
                content: ContentItem(content),
                timestamp: timestamp,
                toolCallId: nil,
                toolCallsData: nil
            )
            if let lastTurn = self.turns.max(by: { $0.sequenceNumber < $1.sequenceNumber }) {
                let event = TurnEvent(type: .assistant, timestamp: assistantMsg.timestamp, message: assistantMsg, turn: lastTurn)
                lastTurn.events.append(event)
            }
            updateTokenCount(updateContextCount: true, updateTotalCount: true)
        }
    }

    /// Sends a message to the AI assistant and handles the response (streaming or not).
    /// This method:
    /// 1. Adds the user message to the conversation
    /// 2. Sends the request to the AI service using the unified streaming API
    /// 3. Processes the response and any tool calls as they arrive
    /// 4. Updates the conversation and streaming state with all results
    ///
    /// - Parameters:
    ///   - message: The user message text
    ///   - streamingState: Observable state object for real-time UI updates
    @MainActor
    func complete(_ message: String, streamingState: StreamingState) async throws {
        guard let apiConfig = self.options.apiConfiguration else {
            vxAtelierPro.log.error("ConversationItem.complete: No API configuration available")
            throw AIServiceError.noConfiguration
        }

        vxAtelierPro.log.info("ConversationItem.complete: Starting completion for conversation '\(self.title)'")

        let service = AIServiceManager.shared.getService(with: apiConfig)
        let allTools = AIToolRegistry.shared.getTools()
        let enabledTools = allTools.filter { self.options.isToolEnabled($0.name) }

        addUserMessage(message)
        
        let existingMessages = createChatMessages(service: service)
        let request = createConfiguredRequest(
            service: service,
            messages: existingMessages,
            enabledTools: enabledTools
        )

        do {
            try await runCompletion(
                service: service,
                request: request,
                enabledTools: enabledTools,
                streamingState: streamingState
            )
        } catch {
            // Remove the recently added user message since completion failed.
            // Do not rely on .last; pick the turn with the highest sequenceNumber.
            if let maxIdx = self.turns.indices.max(by: { self.turns[$0].sequenceNumber < self.turns[$1].sequenceNumber }) {
                let lastTurn = self.turns[maxIdx]
                if lastTurn.userMessage.content.text == message {
                    self.turns.remove(at: maxIdx)
                    updateTokenCount(updateContextCount: true, updateTotalCount: false)
                }
            }
            throw error
        }
    }

    @MainActor
    private func runCompletion(
        service: AIService,
        request: AIChatCompletionRequest,
        enabledTools: [AITool],
        streamingState: StreamingState
    ) async throws {
        streamingState.isActive = true
        streamingState.text = ""
        do {
            let response = try await CompletionStreamProcessor.processStream(
                service: service,
                request: request,
                updateHandler: { updatedContent in
                    streamingState.text = updatedContent
                }
            )
            streamingState.isActive = false
            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                // Append assistant message with toolCalls once inside the recursive handler
                try await handleToolCallsRecursively(service: service, response: response, enabledTools: enabledTools)
            } else if !(response.content ?? "").isEmpty {
                // No tool calls: append plain assistant message
                appendAssistantMessage(response.content ?? "")
            }
        } catch {
            streamingState.isActive = false
            vxAtelierPro.log.error("ConversationItem.complete: Streaming error: \(error.localizedDescription)")
            throw error
        }
    }

    @MainActor
    private func appendAssistantMessage(_ content: String) {
        let assistantMsg = MessageItem(
            role: "assistant",
            content: ContentItem(content),
            timestamp: Date(),
            toolCallId: nil,
            toolCallsData: nil
        )
        if let lastTurn = self.turns.max(by: { $0.sequenceNumber < $1.sequenceNumber }) {
            let event = TurnEvent(type: .assistant, timestamp: assistantMsg.timestamp, message: assistantMsg, turn: lastTurn)
            lastTurn.events.append(event)
        }
        updateTokenCount(updateContextCount: true, updateTotalCount: true)
    }

    @MainActor
    private func handleToolCallsRecursively(
        service: AIService,
        response: AIChatCompletionResponse,
        enabledTools: [AITool],
        maxRecursionDepth: Int = 10
    ) async throws {
        guard maxRecursionDepth > 0 else {
            throw AIServiceError.unsupportedOperation("Max tool call recursion depth exceeded")
        }
        guard let toolCalls = response.toolCalls else { return }
        appendAssistantMessageWithToolCalls(response.content ?? "", toolCalls: toolCalls)
        let configuredToolCalls = try configureToolCalls(toolCalls)
        let toolResults = try await DefaultToolHandler().handleToolCalls(configuredToolCalls)
        appendToolResults(toolResults)
        if let followUpResponse = try await getFollowUpResponseIfNeeded(
            service: service,
            enabledTools: enabledTools
        ) {
            try await handleToolCallsRecursively(
                service: service,
                response: followUpResponse,
                enabledTools: enabledTools,
                maxRecursionDepth: maxRecursionDepth - 1
            )
        }
    }

    @MainActor
    private func appendAssistantMessageWithToolCalls(_ content: String, toolCalls: [AIToolCall]) {
        let assistantMsg = MessageItem(
            role: "assistant",
            content: ContentItem(content),
            timestamp: Date(),
            toolCallId: nil,
            toolCallsData: nil
        )
        assistantMsg.setToolCalls(toolCalls)
        if let lastTurn = self.turns.max(by: { $0.sequenceNumber < $1.sequenceNumber }) {
            let event = TurnEvent(type: .assistant, timestamp: assistantMsg.timestamp, message: assistantMsg, turn: lastTurn)
            lastTurn.events.append(event)
        }
    }

    @MainActor
    private func configureToolCalls(_ toolCalls: [AIToolCall]) throws -> [AIToolCall] {
        return try toolCalls.map { toolCall in
            let toolName = toolCall.name
            let toolConfig = self.options.getToolConfiguration(toolName)
            guard self.options.isToolEnabled(toolName) else {
                throw AIServiceError.unsupportedOperation(
                    "Tool '\(toolName)' is not enabled for this conversation")
            }
            return GenericToolCall(
                id: toolCall.id,
                name: toolCall.name,
                arguments: toolCall.arguments,
                configuration: toolConfig,
                context: self
            )
        }
    }

    @MainActor
    private func appendToolResults(_ toolResults: [AIToolCallResult]) {
        if let lastTurn = self.turns.max(by: { $0.sequenceNumber < $1.sequenceNumber }) {
            // Anchor tool results to the most recent assistant event timestamp for deterministic ordering
            let baseTimestamp = lastTurn.events.last(where: { $0.type == .assistant })?.timestamp ?? Date()
            for (idx, result) in toolResults.enumerated() {
                let ts = baseTimestamp.addingTimeInterval(0.001 * Double(idx + 1))
                let toolMsg = MessageItem(
                    role: "tool",
                    content: ContentItem(result.output),
                    timestamp: ts,
                    toolCallId: result.toolCallId,
                    toolCallsData: nil
                )
                let event = TurnEvent(type: .toolResult, timestamp: toolMsg.timestamp, message: toolMsg, turn: lastTurn)
                lastTurn.events.append(event)
            }
        }
    }

    @MainActor
    private func getFollowUpResponseIfNeeded(
        service: AIService,
        enabledTools: [AITool]
    ) async throws -> GenericChatCompletionResponse? {
        let messages = createChatMessages(service: service)
        let request = createConfiguredRequest(
            service: service,
            messages: messages,
            enabledTools: enabledTools
        )
        do {
            let response = try await CompletionStreamProcessor.processStream(service: service, request: request)
            if !(response.content ?? "").isEmpty {
                appendAssistantMessage(response.content ?? "")
            }
            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                return response
            }
        } catch {
            vxAtelierPro.log.error("ConversationItem.handleToolCallsRecursively: Streaming error: \(error.localizedDescription)")
            throw error
        }
        return nil
    }
} 
