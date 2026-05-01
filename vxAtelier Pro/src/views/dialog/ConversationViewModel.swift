import Foundation
import SwiftUI
import SwiftData
import Observation

// Stable token for sheet presentation identity
// Removed OptionsSheetToken struct

@MainActor
@Observable
final class ConversationViewModel {
    // Store the conversation ID instead of the direct reference
    private let conversationID: PersistentIdentifier
    var id: PersistentIdentifier { conversationID }
    
    var selectedMessages = Set<PersistentIdentifier>()
    var isSelectingMessages: Bool = false
    var draftStore = ConversationDraftStore()
    var errorAlert: ErrorAlert?
    var bookmarkMessage: MessageItem? = nil
    var bookmarkMessageLabel: String = ""
    @ObservationIgnored let queryManager: QueryManager
    @ObservationIgnored let ttsQueue: TTSQueue

    var conversation: ConversationItem? {
        queryManager.conversation(with: conversationID)
    }
    
    var sortedTurns: [ConversationTurn] {
        guard let conversation = conversation else { return [] }
        return conversation.turns.sorted(by: { $0.sequenceNumber < $1.sequenceNumber })
    }

    var navigationTitle: String {
        guard let conversation = conversation else { return "Conversation Not Found" }
        if let project = conversation.project {
            return "\(conversation.title)@\(project.name)"
        } else {
            return conversation.title
        }
    }

    var contentVersion: Int {
        conversation?.turns.reduce(0) { $0 + 1 + $1.events.count } ?? 0
    }

    // Initialize with conversation ID instead of direct reference
    init(conversationID: PersistentIdentifier, queryManager: QueryManager, ttsQueue: TTSQueue) {
        self.conversationID = conversationID
        self.queryManager = queryManager
        self.ttsQueue = ttsQueue
    }
    
    deinit {
        let id = conversationID
        Task { @MainActor in
            vxAtelierPro.log.debug("ConversationViewModel.deinit for conversationID=\(id)")
        }
    }

    // MARK: - Selection Logic
    func toggleSelection(for id: PersistentIdentifier) {
        if selectedMessages.contains(id) {
            selectedMessages.remove(id)
        } else {
            selectedMessages.insert(id)
        }
    }

    func selectAllMessages() {
        guard let conversation = conversation else {
            selectedMessages.removeAll()
            return
        }
        selectedMessages = allMessageIDs(in: conversation)
    }

    func invertSelection() {
        guard let conversation = conversation else { return }
        let all = allMessageIDs(in: conversation)
        selectedMessages = all.subtracting(selectedMessages)
    }

    // MARK: - Message Actions
    func handleMessageAction(_ action: MessageAction, message: MessageItem, turn: ConversationTurn) {
        vxAtelierPro.log.info("Handling message action: \(action) for message ID: \(message.id)")
        guard let conversation = conversation else { 
            vxAtelierPro.log.error("Cannot handle message action: conversation not found")
            errorAlert = ErrorAlert(error: AppError.invalidOperation("Conversation not found"))
            return
        }
        
        switch action {
        case .bookmark:
            bookmarkMessageLabel = ""
            bookmarkMessage = message
        case .removeBookmark:
            removeBookmarkForMessage(message)
        case .fork:
            let forkedConversation = conversation.fork(upToTurnIndex: turn.sequenceNumber)
            do {
                try queryManager.insert(forkedConversation)
            } catch {
                vxAtelierPro.log.error("Failed to insert forked conversation: \(error.localizedDescription)")
            }
        case .addToPlaylist:
            vxAtelierPro.log.info("Adding single message to playlist. ID: \(message.id)")
            ttsQueue.add(message, conversationTitle: conversation.title, messageIndex: 0, projectName: conversation.project?.name)
        case .select:
            isSelectingMessages = true
            selectedMessages.insert(message.id)
        case .copyText:
            ExportUtils.copyToClipboard(message.displayText)
        case .copyJSON:
            let messageData = MessageExportData(message)
            ExportUtils.copyToClipboard(messageData)
        case .delete:
            deleteTurnsContainingMessages([message.id])
        }
    }

    func deleteTurnsContainingMessages(_ ids: [PersistentIdentifier]) {
        guard let conversation = conversation else {
            vxAtelierPro.log.error("Cannot delete messages: conversation not found")
            errorAlert = ErrorAlert(error: AppError.invalidOperation("Conversation not found"))
            return
        }

        let messagesToRemove = Set(ids)
        do {
            let removedCount = try queryManager.deleteTurns(containing: messagesToRemove, in: conversation)
            if removedCount == 0 {
                vxAtelierPro.log.info("ConversationViewModel: No turns removed during delete action.")
            } else {
                vxAtelierPro.log.notice("ConversationViewModel: Deleted \(removedCount) turn(s) for selected messages.")
            }
        } catch {
            vxAtelierPro.log.error("ConversationViewModel: Failed to delete turns: \(error.localizedDescription)")
            errorAlert = ErrorAlert(error: AppError.dataSaveFailed(error.localizedDescription))
        }
    }

    func deleteSelectedMessages() {
        guard !selectedMessages.isEmpty else { return }
        deleteTurnsContainingMessages(selectedMessages.map { $0 })                
        exitSelectionMode()           
    }
    
    // MARK: - Lifecycle
    @MainActor
    func onAppear() {
        guard let conversation = conversation else {
            vxAtelierPro.log.debug("ConversationViewModel.onAppear: no conversation available")
            return
        }
        vxAtelierPro.log.debug("ConversationViewModel.onAppear: \(conversation.title)")
    }

    @MainActor
    func onDisappear() {
        guard let conversation = conversation else {
            vxAtelierPro.log.debug("ConversationViewModel.onDisappear: no conversation available")
            return
        }
        vxAtelierPro.log.debug("ConversationViewModel.onDisappear: \(conversation.title)")
    }

    func saveContext() throws {
        try queryManager.saveContext()
    }

    // MARK: - Menu Actions
    func exitSelectionMode() {
        vxAtelierPro.log.debug("Exiting selection mode.")
        isSelectingMessages = false
        selectedMessages.removeAll()
    }

    func addToPlaylist(_ messageIDs: Set<PersistentIdentifier>) {
        guard !messageIDs.isEmpty else {
            vxAtelierPro.log.debug("No messages selected to add to playlist")
            return
        }
        guard let conversation = conversation else {
            vxAtelierPro.log.error("Cannot add to playlist: conversation not found")
            errorAlert = ErrorAlert(error: AppError.invalidOperation("Conversation not found"))
            return
        }

        let messagesToAdd = selectedMessagesOrdered(in: conversation, messageIDs: messageIDs)

        for (index, message) in messagesToAdd.enumerated() {
            ttsQueue.add(
                message,
                conversationTitle: conversation.title,
                messageIndex: index,
                projectName: conversation.project?.name
            )
        }
    }

    func addSelectedToPlaylist() {
        guard !selectedMessages.isEmpty else {
            vxAtelierPro.log.debug("No messages selected to add to playlist")
            return
        }

        addToPlaylist(selectedMessages)
        exitSelectionMode()
    }

    func addAllToPlaylist() {
        vxAtelierPro.log.info("Adding all messages to playlist.")
        guard let conversation = conversation else {
            vxAtelierPro.log.error("Cannot add to playlist: conversation not found")
            errorAlert = ErrorAlert(error: AppError.invalidOperation("Conversation not found"))
            return
        }
        addToPlaylist(allMessageIDs(in: conversation))
    }

    func copySelectedAsText() {
        guard let conversation = conversation else { return }

        let selectedMessagesList = selectedMessagesOrdered(in: conversation, messageIDs: selectedMessages)
        let selectedText = selectedMessagesList.map(\.displayText).joined(separator: "\n\n")
        ExportUtils.copyToClipboard(selectedText)
    }

    func copySelectedAsJSON() {
        guard let conversation = conversation else { return }

        let selectedMessagesList = selectedMessagesOrdered(in: conversation, messageIDs: selectedMessages)
            .map { MessageExportData($0) }
        ExportUtils.copyToClipboard(selectedMessagesList)
        
        exitSelectionMode()
    }

    func exportSelectedMessages() async {
        guard let conversation = conversation else { return }

        let selectedMessageItems = selectedMessagesOrdered(in: conversation, messageIDs: selectedMessages)
        do {
            try await DataManager.shared.exportSelectedMessages(
                selectedMessageItems,
                conversationTitle: conversation.title
            )
        } catch {
            vxAtelierPro.log.error("Failed to export messages: \(error.localizedDescription)")
        }
    }

    // MARK: - Bookmark Management
    
    /// Returns the turn and event for the given message
    func turnAndEvent(for message: MessageItem) -> (ConversationTurn, TurnEvent?)? {
        guard let conversation = conversation else { return nil }
        
        for turn in conversation.turns {
            if turn.userMessage.id == message.id {
                return (turn, nil)
            }
            for event in turn.events {
                if event.message.id == message.id {
                    return (turn, event)
                }
            }
        }
        
        return nil
    }
    
    /// Remove a bookmark for the given message
    func removeBookmarkForMessage(_ message: MessageItem) {
        guard let (turn, event) = turnAndEvent(for: message) else { return }

        let bookmark = queryManager.bookmark(for: turn, event: event)

        if let bookmark = bookmark {
            do {
                try queryManager.delete(bookmark)
            } catch {
                vxAtelierPro.log.error("Failed to delete bookmark: \(error.localizedDescription)")
            }
        }
    }
    
    func insertBookmark(label: String, message: MessageItem) {
        // We need to check if the conversation exists, but we don't need the actual value
        guard conversation != nil else { return }
        guard let (turn, event) = turnAndEvent(for: message) else { return }
        
        // Create and insert bookmark through QueryManager
        if let event = event {
            let bookmark = BookmarkItem(label, turn: turn, event: event)
            try? queryManager.insert(bookmark)
        } else {
            let bookmark = BookmarkItem(label, turn: turn)
            try? queryManager.insert(bookmark)
        }
    }

    /// Orders selected messages by turn.sequenceNumber, then event.timestamp (stable by event array order).
    /// User messages come before events within the same turn.
    private func selectedMessagesOrdered(
        in conversation: ConversationItem,
        messageIDs: Set<PersistentIdentifier>
    ) -> [MessageItem] {
        guard !messageIDs.isEmpty else { return [] }

        let turns = conversation.turns.sorted(by: { $0.sequenceNumber < $1.sequenceNumber })
        var messages: [MessageItem] = []
        for turn in turns {
            if messageIDs.contains(turn.userMessage.id) {
                messages.append(turn.userMessage)
            }
            let indexedEvents = Array(turn.events.enumerated())
            let selectedEvents = indexedEvents
                .filter { messageIDs.contains($0.element.message.id) }
                .sorted {
                    if $0.element.timestamp != $1.element.timestamp {
                        return $0.element.timestamp < $1.element.timestamp
                    }
                    return $0.offset < $1.offset
                }
            messages.append(contentsOf: selectedEvents.map { $0.element.message })
        }
        return messages
    }

    private func allMessageIDs(in conversation: ConversationItem) -> Set<PersistentIdentifier> {
        var ids = Set<PersistentIdentifier>()
        for turn in conversation.turns {
            ids.insert(turn.userMessage.id)
            for event in turn.events {
                ids.insert(event.message.id)
            }
        }
        return ids
    }

}
