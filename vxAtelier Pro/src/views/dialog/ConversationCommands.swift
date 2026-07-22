import Foundation
import SwiftData

@MainActor
struct ConversationCommands {
    let queryManager: QueryManager
    let ttsQueue: TTSQueue
    let conversationID: PersistentIdentifier

    func insertBookmark(label: String, reference: ConversationMessageReference) throws {
        try queryManager.insertBookmark(
            label: label,
            conversationID: reference.conversationID,
            turnID: reference.turnID,
            messageID: reference.messageID
        )
    }

    func removeBookmark(reference: ConversationMessageReference) throws {
        let turn = try resolvedTurn(reference.turnID)
        let event: TurnEvent?
        if let eventID = reference.eventID {
            event = turn.events.first { $0.persistentModelID == eventID }
            guard event != nil else {
                throw AppError.invalidOperation("Bookmark event not available")
            }
        } else {
            event = nil
        }

        if let bookmark = queryManager.bookmark(for: turn, event: event) {
            try queryManager.delete(bookmark)
        }
    }

    func fork(turnID: PersistentIdentifier) throws {
        let conversation = try resolvedConversation()
        let turns = conversation.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
        guard let turnIndex = turns.firstIndex(where: { $0.persistentModelID == turnID }) else {
            throw AppError.invalidOperation("Turn not available")
        }
        try queryManager.insert(conversation.fork(upToTurnIndex: turnIndex))
    }

    @discardableResult
    func deleteMessages(_ messageIDs: Set<PersistentIdentifier>) throws -> Int {
        try queryManager.deleteTurns(
            containing: messageIDs,
            in: resolvedConversation()
        )
    }

    func copyText(messageID: PersistentIdentifier) throws {
        ExportUtils.copyToClipboard(try resolvedMessage(messageID).textContent)
    }

    func copyJSON(messageID: PersistentIdentifier) throws {
        ExportUtils.copyToClipboard(MessageExportData(try resolvedMessage(messageID)))
    }

    func copyText(messageIDs: Set<PersistentIdentifier>) throws {
        let text = try orderedMessages(messageIDs: messageIDs)
            .map(\.textContent)
            .joined(separator: "\n\n")
        ExportUtils.copyToClipboard(text)
    }

    func copyJSON(messageIDs: Set<PersistentIdentifier>) throws {
        let messages = try orderedMessages(messageIDs: messageIDs).map(MessageExportData.init)
        ExportUtils.copyToClipboard(messages)
    }

    func export(messageIDs: Set<PersistentIdentifier>) async throws {
        let conversation = try resolvedConversation()
        try await DataManager.shared.exportSelectedMessages(
            orderedMessages(messageIDs: messageIDs, in: conversation),
            conversationTitle: conversation.title
        )
    }

    func addToNewPlaylist(messageIDs: Set<PersistentIdentifier>) throws {
        guard !messageIDs.isEmpty else { return }
        let conversation = try resolvedConversation()
        guard ttsQueue.createPlaylist(named: conversation.title) != nil else {
            throw AppError.invalidOperation("Unable to create playlist")
        }
        ttsQueue.add(
            orderedMessages(messageIDs: messageIDs, in: conversation),
            conversationID: conversationID
        )
    }

    func addToPlaylist(
        messageIDs: Set<PersistentIdentifier>,
        playlistID: PersistentIdentifier
    ) throws {
        guard !messageIDs.isEmpty else { return }
        let conversation = try resolvedConversation()
        guard ttsQueue.playlists().contains(where: { $0.persistentModelID == playlistID }) else {
            throw AppError.invalidOperation("Playlist not available")
        }
        ttsQueue.selectPlaylist(id: playlistID)
        ttsQueue.add(
            orderedMessages(messageIDs: messageIDs, in: conversation),
            conversationID: conversationID
        )
    }

    func setUtilityConversation(_ isLinked: Bool) throws {
        try queryManager.setUtilityPanelConversation(
            resolvedConversation(),
            isLinked: isLinked
        )
    }

    private func resolvedConversation() throws -> ConversationItem {
        guard let conversation = queryManager.conversation(with: conversationID) else {
            throw AppError.invalidOperation("Conversation not available")
        }
        return conversation
    }

    private func resolvedTurn(_ turnID: PersistentIdentifier) throws -> ConversationTurn {
        try resolvedTurn(turnID, in: resolvedConversation())
    }

    private func resolvedTurn(
        _ turnID: PersistentIdentifier,
        in conversation: ConversationItem
    ) throws -> ConversationTurn {
        guard let turn = queryManager.turn(with: turnID, in: conversation) else {
            throw AppError.invalidOperation("Turn not available")
        }
        return turn
    }

    private func resolvedMessage(_ messageID: PersistentIdentifier) throws -> MessageItem {
        let conversation = try resolvedConversation()
        for turn in conversation.turns {
            if let message = queryManager.message(with: messageID, in: turn) {
                return message
            }
        }
        throw AppError.invalidOperation("Message not available")
    }

    private func orderedMessages(
        messageIDs: Set<PersistentIdentifier>
    ) throws -> [MessageItem] {
        try orderedMessages(messageIDs: messageIDs, in: resolvedConversation())
    }

    private func orderedMessages(
        messageIDs: Set<PersistentIdentifier>,
        in conversation: ConversationItem
    ) -> [MessageItem] {
        guard !messageIDs.isEmpty else { return [] }
        var messages: [MessageItem] = []
        for turn in conversation.turns.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
            if messageIDs.contains(turn.userMessage.persistentModelID) {
                messages.append(turn.userMessage)
            }
            let assistantMessages = turn.events.enumerated()
                .filter {
                    $0.element.type == .assistant
                        && messageIDs.contains($0.element.message.persistentModelID)
                }
                .sorted {
                    if $0.element.timestamp != $1.element.timestamp {
                        return $0.element.timestamp < $1.element.timestamp
                    }
                    return $0.offset < $1.offset
                }
                .map { $0.element.message }
            messages.append(contentsOf: assistantMessages)
        }
        return messages
    }
}
