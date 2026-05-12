import SwiftUI
import SwiftData
import Foundation

// MARK: - ConversationView
struct ConversationView: View {
    @Environment(QueryManager.self) private var queryManager
    @Environment(TTSQueue.self) private var ttsQueue

    let conversationID: PersistentIdentifier
    let scrollHint: PersistentIdentifier?
    let onRequestOptions: (PersistentIdentifier) -> Void

    @State private var selectedMessages = Set<PersistentIdentifier>()
    @State private var isSelectingMessages: Bool = false
    @State private var draftStore = ConversationDraftStore()
    @State private var errorAlert: ErrorAlert?
    @State private var bookmarkMessage: MessageItem?
    @State private var bookmarkMessageLabel: String = ""

    init(
        conversationID: PersistentIdentifier,
        scrollHint: PersistentIdentifier? = nil,
        onRequestOptions: @escaping (PersistentIdentifier) -> Void = { _ in }
    ) {
        self.conversationID = conversationID
        self.scrollHint = scrollHint
        self.onRequestOptions = onRequestOptions
    }

    private var conversation: ConversationItem? {
        queryManager.conversation(with: conversationID)
    }

    private var sortedTurns: [ConversationTurn] {
        conversation?.turns.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) ?? []
    }

    private var navigationTitle: String {
        guard let conversation else { return "Conversation Not Found" }
        if let project = conversation.project {
            return "\(conversation.title)@\(project.name)"
        }
        return conversation.title
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if let conversation {
                                let turns = sortedTurns
                                ForEach(turns, id: \.id) { turn in
                                    ConversationTurnView(
                                        conversationID: conversation.id,
                                        turn: turn,
                                        isLastTurn: turn.id == turns.last?.id,
                                        draftStore: draftStore,
                                        isSelecting: isSelectingMessages,
                                        isSelected: { selectedMessages.contains($0) },
                                        onSelect: { toggleSelection(for: $0) },
                                        onTap: { message, t in
                                            hideKeyboard()
                                            if isSelectingMessages { toggleSelection(for: message.id) }
                                        },
                                        onAction: { action, message, t in
                                            handleMessageAction(action, message: message, turn: t)
                                        },
                                        isBookmarkedUser: queryManager.isUserBookmarked(turnID: turn.id),
                                        isBookmarkedAssistant: { messageID in
                                            queryManager.isAssistantBookmarked(turnID: turn.id, messageID: messageID)
                                        }
                                    )
                                }
                            }

                            Color.clear
                                .frame(height: 1)
                        }
                        .padding(.vertical, AppDefaults.paddingSmall)
                    }
                }
                .onAppear {
                    if let conversation {
                        vxAtelierPro.log.debug("ConversationView.onAppear: \(conversation.title)")
                    } else {
                        vxAtelierPro.log.debug("ConversationView.onAppear: no conversation available")
                    }
                }

                if !isSelectingMessages, let conversation {
                    Divider()
                    MessageInputView(
                        queryManager: queryManager,
                        draftStore: draftStore,
                        contextConversation: conversation,
                        resolveConversation: {
                            if let resolvedConversation = queryManager.conversation(with: conversationID) {
                                return resolvedConversation
                            }
                            throw AppError.invalidOperation("Conversation not available")
                        }
                    )
                    .padding(AppDefaults.paddingSmall)
                    .disabled(draftStore.isActive)
                }
            }
        }
        .padding(AppDefaults.paddingSmall)
        .navigationTitle(navigationTitle)
        .errorAlert(error: $errorAlert)
        .sheet(isPresented: Binding(get: { bookmarkMessage != nil }, set: { if !$0 { bookmarkMessage = nil } })) {
            if let message = bookmarkMessage {
                if let (turn, event) = turnAndEvent(for: message) {
                    BookmarkSheetView(
                        label: $bookmarkMessageLabel,
                        turn: turn,
                        event: event,
                        onBookmark: { _, _, label in
                            insertBookmark(label: label, message: message)
                            bookmarkMessage = nil
                        },
                        onCancel: {
                            bookmarkMessage = nil
                        }
                    )
                }
            }
        }
        .onTapGesture { hideKeyboard() }
        .onKeyPress(.escape, action: {
            if isSelectingMessages {
                isSelectingMessages = false
                return KeyPress.Result.handled
            }
            return KeyPress.Result.ignored
        })
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if isSelectingMessages {
                        selectionModeMenu
                    } else {
                        normalModeMenu
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
            }
        }
    }

    @ViewBuilder
    private var selectionModeMenu: some View {
        Button {
            exitSelectionMode()
        } label: {
            MenuItemStyle.label("Exit Selection Mode", systemImage: "xmark.circle")
        }
        .help("Exit message selection mode")
        .keyboardShortcut(.escape, modifiers: [])

        Divider()

        Button { selectAllMessages() } label: {
            MenuItemStyle.label("Select All Messages", systemImage: "checkmark.circle.fill")
        }
        .help("Select all messages in this conversation")

        Button { invertSelection() } label: {
            MenuItemStyle.label("Invert Selection", systemImage: "arrow.2.circlepath")
        }
        .help("Invert the current message selection")
        .disabled(selectedMessages.isEmpty)

        Divider()

        Button {
            addSelectedToPlaylist()
        } label: {
            MenuItemStyle.label("Add to Playlist", systemImage: "speaker.wave.2.bubble")
        }
        .help("Add selected messages to the text-to-speech queue")
        .disabled(selectedMessages.isEmpty)

        Divider()

        Button {
            copySelectedAsText()
        } label: {
            MenuItemStyle.label("Copy as Text", systemImage: "doc.on.doc")
        }
        .help("Copy selected messages as plain text")
        .disabled(selectedMessages.isEmpty)

        Button {
            copySelectedAsJSON()
        } label: {
            MenuItemStyle.label("Copy as JSON", systemImage: "doc.on.doc")
        }
        .help("Copy selected messages as JSON")
        .disabled(selectedMessages.isEmpty)

        Button {
            Task {
                await exportSelectedMessages()
            }
        } label: {
            MenuItemStyle.label("Export Selected Messages", systemImage: "arrow.up.doc")
        }
        .help("Export selected messages as Text")
        .disabled(selectedMessages.isEmpty)

        Divider()

        if conversation?.status == .active {
            Button(role: .destructive) {
                deleteTurnsContainingMessages(selectedMessages.map { $0 })
                exitSelectionMode()
            } label: {
                MenuItemStyle.label("Delete Selected", systemImage: "trash")
            }
            .help("Permanently delete selected messages")
            .disabled(selectedMessages.isEmpty)
        }
    }

    @ViewBuilder
    private var normalModeMenu: some View {
        Button { isSelectingMessages = true } label: {
            MenuItemStyle.label("Select Messages", systemImage: "checkmark.circle")
        }
        .help("Enter message selection mode")

        Divider()

        Button {
            addAllToPlaylist()
        } label: {
            MenuItemStyle.label("Add to Playlist", systemImage: "speaker.wave.2.bubble")
        }
        .help("Add all messages to the text-to-speech queue")
        .disabled(conversation?.turns.isEmpty ?? true)

        if conversation?.status == .active {
            Divider()
#if os(macOS)
            if let conversation {
                Toggle(isOn: Binding(get: { conversation.isUtilityConversation }, set: { newValue in
                    do {
                        try queryManager.setUtilityPanelConversation(conversation, isLinked: newValue)
                    } catch {
                        vxAtelierPro.log.error("ConversationView: Failed to update utility panel link: \(error.localizedDescription)")
                    }
                })) {
                    MenuItemStyle.label("Link to Utility Panel", systemImage: "dock.rectangle")
                }
                .help("Link this conversation to the utility panel")
            }
#endif
        }

        Divider()

        if conversation?.status == .active {
            Button {
                onRequestOptions(conversationID)
            } label: {
                MenuItemStyle.label("Conversation Options", systemImage: "slider.horizontal.3")
            }
            .help("Configure conversation settings")
            .keyboardShortcut(",", modifiers: [.command, .option])
        }
    }

    private func toggleSelection(for id: PersistentIdentifier) {
        if selectedMessages.contains(id) {
            selectedMessages.remove(id)
        } else {
            selectedMessages.insert(id)
        }
    }

    private func selectAllMessages() {
        guard let conversation else {
            selectedMessages.removeAll()
            return
        }
        selectedMessages = allMessageIDs(in: conversation)
    }

    private func invertSelection() {
        guard let conversation else { return }
        selectedMessages = allMessageIDs(in: conversation).subtracting(selectedMessages)
    }

    private func handleMessageAction(_ action: MessageAction, message: MessageItem, turn: ConversationTurn) {
        vxAtelierPro.log.info("Handling message action: \(action) for message ID: \(message.id)")
        guard let conversation else {
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

    private func deleteTurnsContainingMessages(_ ids: [PersistentIdentifier]) {
        guard let conversation else {
            vxAtelierPro.log.error("Cannot delete messages: conversation not found")
            errorAlert = ErrorAlert(error: AppError.invalidOperation("Conversation not found"))
            return
        }

        let messagesToRemove = Set(ids)
        do {
            let removedCount = try queryManager.deleteTurns(containing: messagesToRemove, in: conversation)
            if removedCount == 0 {
                vxAtelierPro.log.info("ConversationView: No turns removed during delete action.")
            } else {
                vxAtelierPro.log.notice("ConversationView: Deleted \(removedCount) turn(s) for selected messages.")
            }
        } catch {
            vxAtelierPro.log.error("ConversationView: Failed to delete turns: \(error.localizedDescription)")
            errorAlert = ErrorAlert(error: AppError.dataSaveFailed(error.localizedDescription))
        }
    }

    private func exitSelectionMode() {
        vxAtelierPro.log.debug("Exiting selection mode.")
        isSelectingMessages = false
        selectedMessages.removeAll()
    }

    private func addToPlaylist(_ messageIDs: Set<PersistentIdentifier>) {
        guard !messageIDs.isEmpty else {
            vxAtelierPro.log.debug("No messages selected to add to playlist")
            return
        }
        guard let conversation else {
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

    private func addSelectedToPlaylist() {
        guard !selectedMessages.isEmpty else {
            vxAtelierPro.log.debug("No messages selected to add to playlist")
            return
        }

        addToPlaylist(selectedMessages)
        exitSelectionMode()
    }

    private func addAllToPlaylist() {
        vxAtelierPro.log.info("Adding all messages to playlist.")
        guard let conversation else {
            vxAtelierPro.log.error("Cannot add to playlist: conversation not found")
            errorAlert = ErrorAlert(error: AppError.invalidOperation("Conversation not found"))
            return
        }
        addToPlaylist(allMessageIDs(in: conversation))
    }

    private func copySelectedAsText() {
        guard let conversation else { return }

        let selectedMessagesList = selectedMessagesOrdered(in: conversation, messageIDs: selectedMessages)
        let selectedText = selectedMessagesList.map(\.displayText).joined(separator: "\n\n")
        ExportUtils.copyToClipboard(selectedText)
    }

    private func copySelectedAsJSON() {
        guard let conversation else { return }

        let selectedMessagesList = selectedMessagesOrdered(in: conversation, messageIDs: selectedMessages)
            .map { MessageExportData($0) }
        ExportUtils.copyToClipboard(selectedMessagesList)

        exitSelectionMode()
    }

    private func exportSelectedMessages() async {
        guard let conversation else { return }

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

    private func turnAndEvent(for message: MessageItem) -> (ConversationTurn, TurnEvent?)? {
        guard let conversation else { return nil }

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

    private func removeBookmarkForMessage(_ message: MessageItem) {
        guard let (turn, event) = turnAndEvent(for: message) else { return }

        let bookmark = queryManager.bookmark(for: turn, event: event)

        if let bookmark {
            do {
                try queryManager.delete(bookmark)
            } catch {
                vxAtelierPro.log.error("Failed to delete bookmark: \(error.localizedDescription)")
            }
        }
    }

    private func insertBookmark(label: String, message: MessageItem) {
        guard conversation != nil else { return }
        guard let (turn, event) = turnAndEvent(for: message) else { return }

        if let event {
            let bookmark = BookmarkItem(label, turn: turn, event: event)
            try? queryManager.insert(bookmark)
        } else {
            let bookmark = BookmarkItem(label, turn: turn)
            try? queryManager.insert(bookmark)
        }
    }

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

fileprivate struct ConversationTurnView: View {
    let conversationID: PersistentIdentifier
    let turn: ConversationTurn
    let isLastTurn: Bool
    let draftStore: ConversationDraftStore

    let isSelecting: Bool
    let isSelected: (PersistentIdentifier) -> Bool

    let onSelect: (PersistentIdentifier) -> Void
    let onTap: (MessageItem, ConversationTurn) -> Void
    let onAction: (MessageAction, MessageItem, ConversationTurn) -> Void

    let isBookmarkedUser: Bool
    let isBookmarkedAssistant: (PersistentIdentifier) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // User bubble
            MessageView(
                messageID: turn.userMessage.id,
                turnID: turn.id,
                conversationID: conversationID,
                isSelected: isSelected(turn.userMessage.id),
                isSelecting: isSelecting,
                onSelect: { onSelect(turn.userMessage.id) },
                onTap: { onTap(turn.userMessage, turn) },
                onAction: { action in onAction(action, turn.userMessage, turn) },
                isBookmarked: isBookmarkedUser
            )
            .id(turn.userMessage.id)

            // Assistant bubbles: render all assistant events in chronological order
            let assistantEvents = turn.events
                .filter { $0.type == .assistant }
                .sorted { $0.timestamp < $1.timestamp }
            ForEach(assistantEvents, id: \.id) { assistant in
                MessageView(
                    messageID: assistant.message.id,
                    turnID: turn.id,
                    conversationID: conversationID,
                    isSelected: isSelected(assistant.message.id),
                    isSelecting: isSelecting,
                    onSelect: { onSelect(assistant.message.id) },
                    onTap: { onTap(assistant.message, turn) },
                    onAction: { action in onAction(action, assistant.message, turn) },
                    isBookmarked: isBookmarkedAssistant(assistant.message.id)
                )
                .id(assistant.message.id)
            }

            let draft = draftStore.draft(for: conversationID)
            let latestRun = turn.responseRuns.sorted { $0.startedAt < $1.startedAt }.last
            let latestRunFailed = latestRun?.status == .failed || latestRun?.status == .cancelled
            let draftFailed = draft.runStatus == .failed || draft.runStatus == .cancelled
            let shouldRenderDraft = assistantEvents.isEmpty
                && isLastTurn
                && (draft.isActive || draftFailed || latestRunFailed)

            if shouldRenderDraft {
                MessageView(
                    messageID: nil,
                    turnID: turn.id,
                    conversationID: conversationID,
                    isSelected: false,
                    isSelecting: false,
                    onSelect: {},
                    onTap: {},
                    onAction: { _ in },
                    isBookmarked: false,
                    streamingContent: draft.text,
                    streamingToolCalls: draft.toolCalls,
                    streamingRunStatus: latestRun?.status ?? draft.runStatus,
                    streamingErrorMessage: latestRun?.errorMessage ?? draft.errorMessage
                )
                .id("stream-\(turn.id)")
            }
        }
        .padding(.horizontal, AppDefaults.paddingSmall)
    }
}
