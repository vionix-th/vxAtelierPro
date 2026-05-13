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
                contentParts: turn.userMessage.orderedContentParts.map {
                    MessageContentPartItem(
                        index: $0.index,
                        kind: $0.kind,
                        text: $0.text,
                        mimeType: $0.mimeType,
                        dataBase64: $0.dataBase64,
                        sourceURL: $0.sourceURL
                    )
                },
                timestamp: turn.userMessage.timestamp,
                toolCallId: turn.userMessage.toolCallId,
                toolCalls: turn.userMessage.toolCallItems.map {
                    ToolCallItem(
                        callID: $0.callID,
                        providerCallID: $0.providerCallID,
                        index: $0.index,
                        name: $0.name,
                        argumentsJSON: $0.argumentsJSON,
                        status: $0.status
                    )
                }
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
                    contentParts: event.message.orderedContentParts.map {
                        MessageContentPartItem(
                            index: $0.index,
                            kind: $0.kind,
                            text: $0.text,
                            mimeType: $0.mimeType,
                            dataBase64: $0.dataBase64,
                            sourceURL: $0.sourceURL
                        )
                    },
                    timestamp: event.message.timestamp,
                    toolCallId: event.message.toolCallId,
                    toolCalls: event.message.toolCallItems.map {
                        ToolCallItem(
                            callID: $0.callID,
                            providerCallID: $0.providerCallID,
                            index: $0.index,
                            name: $0.name,
                            argumentsJSON: $0.argumentsJSON,
                            status: $0.status
                        )
                    }
                )
                let eventCopy = TurnEvent(type: event.type, timestamp: event.timestamp, message: eventMsgCopy, turn: turnCopy)
                turnCopy.events.append(eventCopy)
            }
            forkedConversation.turns.append(turnCopy)
        }
        forkedConversation.project = self.project
        return forkedConversation
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
                sum + Self.estimatedTokenCount(for: message)
            }
            tokenCount = newTokenCount
            vxAtelierPro.log.debug("Updated context token count for conversation '\(title)': \(newTokenCount)")
        }

        if updateTotalCount {
            usedTokenCount += newTokenCount
            vxAtelierPro.log.debug("Updated total token count for conversation '\(title)': \(usedTokenCount)")
        }
    }

    private static func estimatedTokenCount(for message: MessageItem) -> Int {
        var count = 4
        count += message.role.split(separator: " ").count
        count += max(1, message.displayText.count / 4)
        count += message.orderedToolCallItems.reduce(0) { partial, call in
            partial + max(1, call.name.count / 4) + max(1, call.argumentsJSON.count / 4)
        }
        if let toolCallId = message.toolCallId {
            count += max(1, toolCallId.count / 4)
        }
        return count
    }

}
