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
    @Published var isPinnedToEnd: Bool = true
    @Published var unreadCount: Int = 0
    @Published var lastVisibleMessageID: PersistentIdentifier? = nil

    let queryManager: QueryManager
    let ttsQueue: TTSQueue

    // Debug flags removed for auto-scroll; keys retained in settings only

    // Resolve the conversation on-demand from the QueryManager
    var conversation: ConversationItem? {
        queryManager.allConversations.first { $0.id == conversationID }
    }
    
    var sortedTurns: [ConversationTurn] {
        guard let conversation = conversation else { return [] }
        return conversation.turns.sorted(by: { $0.sequenceNumber < $1.sequenceNumber })
    }

    var allSelectableMessageIDs: [PersistentIdentifier] {
        guard let conversation = conversation else { return [] }
        return conversation.turns.flatMap { [$0.userMessage.id] + $0.events.map { $0.message.id } }
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
        selectedMessages = Set(allSelectableMessageIDs)
    }

    func invertSelection() {
        let all = Set(allSelectableMessageIDs)
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
            deleteMessages([message.id])
        }
    }

    func deleteMessages(_ ids: [PersistentIdentifier]) {
        guard let conversation = conversation else {
            vxAtelierPro.log.error("Cannot delete messages: conversation not found")
            errorAlert = ErrorAlert(error: AppError.invalidOperation("Conversation not found"))
            return
        }
        
        let messagesToRemove = Set(ids)
        var turnsToRemove = Set<PersistentIdentifier>()
        var removedCount = 0
        
        for turn in conversation.turns {
            if messagesToRemove.contains(turn.userMessage.id) {
                turnsToRemove.insert(turn.id)
            }
        }
        
        let initialCount = conversation.turns.count
        conversation.turns.removeAll { turn in
            turnsToRemove.contains(turn.id)
        }
        removedCount += initialCount - conversation.turns.count
        
        for turn in conversation.turns {
            let initialEventCount = turn.events.count
            turn.events.removeAll { event in
                messagesToRemove.contains(event.message.id)
            }
            removedCount += initialEventCount - turn.events.count
        }
        
        if removedCount > 0 {
            conversation.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: false)
            do {
                try queryManager.saveContext()
                vxAtelierPro.log.notice("DialogViewModel: Deleted \(removedCount) selected messages.")
            } catch {
                vxAtelierPro.log.error("DialogViewModel: Failed to save context after deleting messages: \(error.localizedDescription)")
            }
        } else {
            vxAtelierPro.log.info("DialogViewModel: No messages removed during delete action.")
        }
        
        isSelectingMessages = false
        selectedMessages.removeAll()
    }

    // MARK: - Scroll Logic (removed)

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
        isSelectingMessages = false
        selectedMessages.removeAll()
    }

    func addSelectedToPlaylist() {
        vxAtelierPro.log.info("Adding selected messages to playlist.")
        guard let conversation = conversation else {
            vxAtelierPro.log.error("Cannot add to playlist: conversation not found")
            errorAlert = ErrorAlert(error: AppError.invalidOperation("Conversation not found"))
            return
        }
        
        let messagesToAdd = conversation.turns.flatMap { turn -> [MessageItem] in
            let turnMessages = [turn.userMessage] + turn.events.map { $0.message }
            let isTurnSelected = turnMessages.contains { selectedMessages.contains($0.id) }
            return isTurnSelected ? turnMessages : []
        }

        for (index, message) in messagesToAdd.enumerated() {
            ttsQueue.add(
                message,
                dialogTitle: conversation.title,
                messageIndex: index,
                projectName: conversation.project?.name
            )
        }

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
        
        let messagesToAdd = conversation.turns.flatMap { turn -> [MessageItem] in
            let turnMessages = [turn.userMessage] + turn.events.map { $0.message }
            let isTurnSelected = turnMessages.contains { messageIDs.contains($0.id) }
            return isTurnSelected ? turnMessages : []
        }

        for (index, message) in messagesToAdd.enumerated() {
            ttsQueue.add(
                message,
                dialogTitle: conversation.title,
                messageIndex: index,
                projectName: conversation.project?.name
            )
        }

        isSelectingMessages = false
        selectedMessages.removeAll()
    }

    func addAllToPlaylist() {
        vxAtelierPro.log.info("Adding all messages to playlist.")
        guard let conversation = conversation else {
            vxAtelierPro.log.error("Cannot add to playlist: conversation not found")
            errorAlert = ErrorAlert(error: AppError.invalidOperation("Conversation not found"))
            return
        }
        
        let allMessages = conversation.turns.flatMap { [$0.userMessage] + $0.events.map { $0.message } }
        for (index, message) in allMessages.enumerated() {
            ttsQueue.add(
                message,
                dialogTitle: conversation.title,
                messageIndex: index,
                projectName: conversation.project?.name
            )
        }
    }

    func copySelectedAsText() {
        guard let conversations = conversation else { return }
        
        let selectedText = conversations.turns
            .filter { selectedMessages.contains($0.userMessage.id) }
            .map { $0.userMessage.content.text }
            .joined(separator: "\n\n")
        ExportUtils.copyToClipboard(selectedText)
    }

    func copySelectedAsJSON() {
        guard let conversation = conversation else { return }
        
        let selectedMessagesList = conversation.turns
            .filter { selectedMessages.contains($0.userMessage.id) }
            .map { MessageExportData($0.userMessage) }
        ExportUtils.copyToClipboard(selectedMessagesList)
        isSelectingMessages = false
    }

    func exportSelectedMessages() async {
        guard let conversation = conversation else { return }
        
        let selectedMessageItems: [MessageItem] = conversation.turns.flatMap { turn in
            var items: [MessageItem] = []
            if selectedMessages.contains(turn.userMessage.id) {
                items.append(turn.userMessage)
            }
            for event in turn.events {
                if selectedMessages.contains(event.message.id) {
                    items.append(event.message)
                }
            }
            return items
        }
        do {
            try await DataManager.shared.exportSelectedMessages(
                selectedMessageItems,
                dialogTitle: conversation.title
            )
        } catch {
            vxAtelierPro.log.error("Failed to export messages: \(error.localizedDescription)")
        }
    }

    func deleteSelectedMessages() {
        guard !selectedMessages.isEmpty else { return }
        guard let conversation = conversation else { return }
        
        // Need to find all turns containing these messages
        var turnsToCheck = Set<PersistentIdentifier>()
        
        for turn in conversation.turns {
            if selectedMessages.contains(turn.userMessage.id) {
                turnsToCheck.insert(turn.id)
            } else {
                for event in turn.events where selectedMessages.contains(event.message.id) {
                    turnsToCheck.insert(turn.id)
                    break
                }
            }
        }
        
        var removedCount = 0
        for turn in turnsToCheck {
            if let index = conversation.turns.firstIndex(where: { $0.id == turn }) {
                conversation.turns.remove(at: index)
                removedCount += 1
            }
        }
        
        for turn in conversation.turns {
            turn.events.removeAll { event in
                selectedMessages.contains(event.message.id)
            }
        }
        
        // Update token count and exit selection mode
        conversation.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: false)
        isSelectingMessages = false
        
        // Save context
        try? queryManager.saveContext()
        isSelectingMessages = false
        selectedMessages.removeAll()
    }
    
    // MARK: - Bookmark Management
    
    /// Returns the turn and event for the given message
    func turnAndEvent(for message: MessageItem) -> (ConversationTurn, TurnEvent)? {
        guard let conversation = conversation else { return nil }
        
        for turn in conversation.turns {
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
        
        if let bookmark = queryManager.bookmarks.first(where: { $0.turn == turn && $0.target === event }) {
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
        let bookmark = BookmarkItem(label, turn: turn, event: event)
        try? queryManager.insert(bookmark)
    }

    func markBottomVisibility(_ visible: Bool) {
        isPinnedToEnd = visible
        if visible { unreadCount = 0 }
    }

    func incrementUnreadIfNeeded() {
        guard !isPinnedToEnd else { return }
        unreadCount = min(unreadCount + 1, 99)
    }

    func resetUnread() {
        unreadCount = 0
    }
} 
