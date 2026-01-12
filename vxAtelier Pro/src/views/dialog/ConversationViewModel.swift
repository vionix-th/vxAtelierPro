import Foundation
import SwiftUI
import SwiftData

// Stable token for sheet presentation identity
// Removed OptionsSheetToken struct

@MainActor
final class ConversationViewModel: ObservableObject {
    // Store the conversation ID instead of the direct reference
    private let conversationID: PersistentIdentifier
    var id: PersistentIdentifier { conversationID }
    
    @Published var selectedMessages = Set<PersistentIdentifier>()
    @Published var isSelectingMessages: Bool = false
    @Published var streamingState = StreamingState()
    @Published var errorAlert: ErrorAlert?
    @Published var bookmarkMessage: MessageItem? = nil
    @Published var bookmarkMessageLabel: String = ""
    let queryManager: QueryManager
    let ttsQueue: TTSQueue

    var conversation: ConversationItem? {
        queryManager.allConversations.first { $0.id == conversationID }
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
    
    // Backward compatibility initializer
    convenience init(conversation: ConversationItem, queryManager: QueryManager, ttsQueue: TTSQueue) {
        self.init(conversationID: conversation.id, queryManager: queryManager, ttsQueue: ttsQueue)
    }

    deinit {
        let id = conversationID
        Task { @MainActor in
            vxAtelierPro.log.debug("DialogViewModel.deinit for conversationID=\(id)")
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
            ttsQueue.add(message, dialogTitle: conversation.title, messageIndex: 0, projectName: conversation.project?.name)
        case .select:
            isSelectingMessages = true
            selectedMessages.insert(message.id)
        case .copyText:
            ExportUtils.copyToClipboard(message.content.text)
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
        let turnsToRemove = turnIDsContainingMessages(in: conversation, messageIDs: messagesToRemove)
        if turnsToRemove.isEmpty {
            vxAtelierPro.log.info("DialogViewModel: No turns removed during delete action.")
            exitSelectionMode()
            return
        }

        let initialCount = conversation.turns.count
        conversation.turns.removeAll { turn in
            turnsToRemove.contains(turn.id)
        }
        let removedCount = initialCount - conversation.turns.count

        if removedCount > 0 {
            conversation.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: false)
            do {
                try queryManager.saveContext()
                vxAtelierPro.log.notice("DialogViewModel: Deleted \(removedCount) turn(s) for selected messages.")
            } catch {
                vxAtelierPro.log.error("DialogViewModel: Failed to save context after deleting messages: \(error.localizedDescription)")
            }
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
            vxAtelierPro.log.debug("DialogViewModel.onAppear: no dialog available")
            return
        }
        vxAtelierPro.log.debug("DialogViewModel.onAppear: \(conversation.title)")
    }

    @MainActor
    func onDisappear() {
        guard let conversation = conversation else {
            vxAtelierPro.log.debug("DialogViewModel.onDisappear: no conversation available")
            return
        }
        vxAtelierPro.log.debug("DialogViewModel.onDisappear: \(conversation.title)")
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
                dialogTitle: conversation.title,
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
        let selectedText = selectedMessagesList.map { $0.content.text }.joined(separator: "\n\n")
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
                dialogTitle: conversation.title
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

        let bookmark = queryManager.bookmarks.first { bookmark in
            if bookmark.turn != turn { return false }
            if let event = event {
                return bookmark.target === event
            }
            return bookmark.target == nil
        }

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

    private func turnIDsContainingMessages(
        in conversation: ConversationItem,
        messageIDs: Set<PersistentIdentifier>
    ) -> Set<PersistentIdentifier> {
        guard !messageIDs.isEmpty else { return [] }
        var turnIDs = Set<PersistentIdentifier>()
        for turn in conversation.turns {
            if messageIDs.contains(turn.userMessage.id) {
                turnIDs.insert(turn.id)
                continue
            }
            if turn.events.contains(where: { messageIDs.contains($0.message.id) }) {
                turnIDs.insert(turn.id)
            }
        }
        return turnIDs
    }
}
