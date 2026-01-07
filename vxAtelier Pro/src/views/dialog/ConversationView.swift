import SwiftUI
import SwiftData
import Foundation

// MARK: - ConversationView
struct ConversationView: View {
    @ObservedObject var viewModel: ConversationViewModel
    private var autoScrollDebugEnabled: Bool { UserDefaults.standard.bool(forKey: "AutoScrollDebugEnabled") }
    private var bottomAnchorID: String { "BOTTOM-\(viewModel.id)" }
    
    let scrollHint: PersistentIdentifier?
    let onRequestOptions: (PersistentIdentifier) -> Void

    init(
        viewModel: ConversationViewModel,
        scrollHint: PersistentIdentifier? = nil,
        onRequestOptions: @escaping (PersistentIdentifier) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.scrollHint = scrollHint
        self.onRequestOptions = onRequestOptions
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if let dialog = viewModel.conversation {
                                let turns = viewModel.sortedTurns
                                ForEach(turns, id: \.id) { turn in
                                    TurnRowV2(
                                        conversationID: dialog.id,
                                        turn: turn,
                                        isLastTurn: turn.id == turns.last?.id,
                                        streamingState: viewModel.streamingState,
                                        isSelecting: viewModel.isSelectingMessages,
                                        isSelectedUser: viewModel.selectedMessages.contains(turn.userMessage.id),
                                        isSelectedAssistant: latestAssistantMessageID(for: turn).map { viewModel.selectedMessages.contains($0) } ?? false,
                                        onSelectUser: { viewModel.toggleSelection(for: turn.userMessage.id) },
                                        onSelectAssistant: {
                                            if let mid = latestAssistantMessageID(for: turn) {
                                                viewModel.toggleSelection(for: mid)
                                            }
                                        },
                                        onTap: { message, t in
                                            hideKeyboard()
                                            if viewModel.isSelectingMessages { viewModel.toggleSelection(for: message.id) }
                                        },
                                        onAction: { action, message, t in
                                            viewModel.handleMessageAction(action, message: message, turn: t)
                                        },
                                        isBookmarkedUser: viewModel.queryManager.isUserBookmarked(turnID: turn.id),
                                        isBookmarkedAssistant: {
                                            if let mid = latestAssistantMessageID(for: turn) {
                                                return viewModel.queryManager.isAssistantBookmarked(turnID: turn.id, messageID: mid)
                                            }
                                            return false
                                        }()
                                    )
                                    .onAppear {
                                        if !viewModel.isPinnedToEnd {
                                            viewModel.lastVisibleMessageID = turn.userMessage.id
                                        }
                                    }
                                }
                            }

                            if viewModel.streamingState.isActive,
                               !viewModel.streamingState.text.isEmpty,
                               let dialog = viewModel.conversation,
                               let lastTurn = viewModel.sortedTurns.last {
                                MessageView(
                                    messageID: nil,
                                    turnID: lastTurn.id,
                                    conversationID: dialog.id,
                                    isSelected: false,
                                    isSelecting: false,
                                    onSelect: {},
                                    onTap: {},
                                    onAction: { _ in },
                                    isBookmarked: false,
                                    streamingContent: viewModel.streamingState.text
                                )
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(bottomAnchorID)
                                .onAppear { viewModel.markBottomVisibility(true) }
                                .onDisappear { viewModel.markBottomVisibility(false) }
                        }
                        .padding(.vertical, AppDefaults.paddingSmall)
                    }

                    if !viewModel.isPinnedToEnd {
                        Button {
                            withAnimation { scrollToBottom(proxy: proxy, animated: true) }
                            viewModel.resetUnread()
                            viewModel.isPinnedToEnd = true
                            if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: FAB tapped -> scroll to end") }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.accentColor)
                                if viewModel.unreadCount > 0 {
                                    Text("\(viewModel.unreadCount)")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(4)
                                        .background(Circle().fill(Color.red))
                                        .offset(x: 10, y: -10)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Scroll to bottom")
                        .padding(.trailing, AppDefaults.paddingMedium)
                        .padding(.bottom, AppDefaults.paddingMedium)
                    }
                }
                .onAppear {
                    performInitialScroll(proxy: proxy)
                    viewModel.onAppear()
                }
                .onChange(of: viewModel.contentVersion) { _, _ in
                    if viewModel.isPinnedToEnd {
                        scrollToBottom(proxy: proxy, animated: false)
                        if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: contentVersion -> pinned, scrolled to end") }
                    } else {
                        viewModel.incrementUnreadIfNeeded()
                        if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: contentVersion -> not pinned, unread=\(viewModel.unreadCount)") }
                    }
                }
                .onChange(of: viewModel.streamingState.text) { _, _ in
                    if viewModel.isPinnedToEnd && viewModel.streamingState.isActive {
                        scrollToBottom(proxy: proxy, animated: false)
                        if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: stream flush -> pinned, scrolled to end") }
                    }
                }

                if !viewModel.isSelectingMessages, let conversation = viewModel.conversation {
                    Divider()
                    MessageInputView(
                        dialog: conversation,
                        streamingState: viewModel.streamingState,
                        didSend: { _ in
                            viewModel.resetUnread()
                            viewModel.isPinnedToEnd = true
                            scrollToBottom(proxy: proxy, animated: true)
                            if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: didSend -> reset unread and scrolled") }
                        }
                    )
                    .padding(AppDefaults.paddingSmall)
                    .disabled(viewModel.streamingState.isActive)
                }
            }
        }
        .padding(AppDefaults.paddingSmall)
        .navigationTitle(viewModel.navigationTitle)
        .errorAlert(error: $viewModel.errorAlert)
        .sheet(isPresented: Binding(get: { viewModel.bookmarkMessage != nil }, set: { if !$0 { viewModel.bookmarkMessage = nil } })) {
            if let message = viewModel.bookmarkMessage {
                if let (turn, event) = viewModel.turnAndEvent(for: message) {
                    BookmarkSheetView(
                        label: $viewModel.bookmarkMessageLabel,
                        turn: turn,
                        event: event,
                        onBookmark: {
                            viewModel.insertBookmark(label: viewModel.bookmarkMessageLabel, message: message)
                            viewModel.bookmarkMessage = nil
                        }
                    )
                }
            }
        }
        .onTapGesture { hideKeyboard() }
        .onKeyPress(.escape, action: {
            if viewModel.isSelectingMessages {
                viewModel.isSelectingMessages = false
                return KeyPress.Result.handled
            }
            return KeyPress.Result.ignored
        })
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if viewModel.isSelectingMessages {
                        SelectionModeMenu(viewModel: viewModel)
                    } else {
                        NormalModeMenu(viewModel: viewModel, onRequestOptions: onRequestOptions)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
            }
        }
    }

    private func performInitialScroll(proxy: ScrollViewProxy) {
        var tx = Transaction(); tx.disablesAnimations = true
        if let hint = scrollHint {
            withTransaction(tx) { proxy.scrollTo(hint, anchor: .center) }
            viewModel.isPinnedToEnd = false
            if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: initial -> scrolled to hint \(hint)") }
        } else if viewModel.isPinnedToEnd {
            withTransaction(tx) { scrollToBottom(proxy: proxy, animated: false) }
            if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: initial -> scrolled to bottom") }
        } else if let anchor = viewModel.lastVisibleMessageID {
            withTransaction(tx) { proxy.scrollTo(anchor, anchor: .top) }
            if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: initial -> restored anchor \(anchor)") }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation { proxy.scrollTo(bottomAnchorID, anchor: .bottom) }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    private func latestAssistantMessageID(for turn: ConversationTurn) -> PersistentIdentifier? {
        let assistantEvents = turn.events.filter { $0.type == .assistant }
        return assistantEvents.sorted { $0.timestamp < $1.timestamp }.last?.message.id
    }
}

fileprivate struct TurnRowV2: View {
    let conversationID: PersistentIdentifier
    let turn: ConversationTurn
    let isLastTurn: Bool
    let streamingState: StreamingState

    let isSelecting: Bool
    let isSelectedUser: Bool
    let isSelectedAssistant: Bool

    let onSelectUser: () -> Void
    let onSelectAssistant: () -> Void
    let onTap: (MessageItem, ConversationTurn) -> Void
    let onAction: (MessageAction, MessageItem, ConversationTurn) -> Void

    let isBookmarkedUser: Bool
    let isBookmarkedAssistant: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // User bubble
            MessageView(
                messageID: turn.userMessage.id,
                turnID: turn.id,
                conversationID: conversationID,
                isSelected: isSelectedUser,
                isSelecting: isSelecting,
                onSelect: onSelectUser,
                onTap: { onTap(turn.userMessage, turn) },
                onAction: { action in onAction(action, turn.userMessage, turn) },
                isBookmarked: isBookmarkedUser
            )
            .id(turn.userMessage.id)

            // Assistant bubble: prefer finalized assistant; otherwise streaming placeholder for last turn
            if let assistant = latestAssistantEvent(in: turn) {
                MessageView(
                    messageID: assistant.message.id,
                    turnID: turn.id,
                    conversationID: conversationID,
                    isSelected: isSelectedAssistant,
                    isSelecting: isSelecting,
                    onSelect: onSelectAssistant,
                    onTap: { onTap(assistant.message, turn) },
                    onAction: { action in onAction(action, assistant.message, turn) },
                    isBookmarked: isBookmarkedAssistant
                )
                .id(assistant.message.id)
            } else if streamingState.isActive && isLastTurn {
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
                    streamingContent: streamingState.text
                )
                .id("stream-\(turn.id)")
            }
        }
        .padding(.horizontal, AppDefaults.paddingSmall)
    }

    private func latestAssistantEvent(in turn: ConversationTurn) -> TurnEvent? {
        let assistantEvents = turn.events.filter { $0.type == .assistant }
        return assistantEvents.sorted { $0.timestamp < $1.timestamp }.last
    }
}

struct SelectionModeMenu: View {
    @ObservedObject var viewModel: ConversationViewModel
    @Environment(TTSQueue.self) private var ttsQueue

    var body: some View {
        Button {
            viewModel.exitSelectionMode()
        } label: {
            MenuItemStyle.label("Exit Selection Mode", systemImage: "xmark.circle")
        }
        .help("Exit message selection mode")
        .keyboardShortcut(.escape, modifiers: [])

        Divider()

        Button { viewModel.selectAllMessages() } label: {
            MenuItemStyle.label("Select All Messages", systemImage: "checkmark.circle.fill")
        }
        .help("Select all messages in this dialog")

        Button { viewModel.invertSelection() } label: {
            MenuItemStyle.label("Invert Selection", systemImage: "arrow.2.circlepath")
        }
        .help("Invert the current message selection")
        .disabled(viewModel.selectedMessages.isEmpty)

        Divider()

        Button {
            viewModel.addSelectedToPlaylist()
        } label: {
            MenuItemStyle.label("Add to Playlist", systemImage: "speaker.wave.2.bubble")
        }
        .help("Add selected messages to the text-to-speech queue")
        .disabled(viewModel.selectedMessages.isEmpty)

        Divider()

        Button {
            viewModel.copySelectedAsText()
        } label: {
            MenuItemStyle.label("Copy as Text", systemImage: "doc.on.doc")
        }
        .help("Copy selected messages as plain text")
        .disabled(viewModel.selectedMessages.isEmpty)

        Button {
            viewModel.copySelectedAsJSON()
        } label: {
            MenuItemStyle.label("Copy as JSON", systemImage: "doc.on.doc")
        }
        .help("Copy selected messages as JSON")
        .disabled(viewModel.selectedMessages.isEmpty)

        Button {
            Task {
                await viewModel.exportSelectedMessages()
            }
        } label: {
            MenuItemStyle.label("Export Selected Messages", systemImage: "arrow.up.doc")
        }
        .help("Export selected messages as Text")
        .disabled(viewModel.selectedMessages.isEmpty)

        Divider()

        if viewModel.conversation?.status == .active {
            Button(role: .destructive) {
                viewModel.deleteSelectedMessages()
            } label: {
                MenuItemStyle.label("Delete Selected", systemImage: "trash")
            }
            .help("Permanently delete selected messages")
            .disabled(viewModel.selectedMessages.isEmpty)
        }
    }
}

struct NormalModeMenu: View {
    @ObservedObject var viewModel: ConversationViewModel
    @Environment(TTSQueue.self) private var ttsQueue
    let onRequestOptions: (PersistentIdentifier) -> Void

    var body: some View {
        Button { viewModel.isSelectingMessages = true } label: {
            MenuItemStyle.label("Select Messages", systemImage: "checkmark.circle")
        }
        .help("Enter message selection mode")

        Divider()

        Button {
            viewModel.addAllToPlaylist()
        } label: {
            MenuItemStyle.label("Add to Playlist", systemImage: "speaker.wave.2.bubble")
        }
        .help("Add all messages to the text-to-speech queue")
        .disabled(viewModel.conversation?.turns.isEmpty ?? true)

        if viewModel.conversation?.status == .active {
            Divider()
#if os(macOS)
            if let dialog = viewModel.conversation {
                Toggle(isOn: Binding(get: { dialog.isLinkedToUtilityPanel }, set: { dialog.isLinkedToUtilityPanel = $0 })) {
                    MenuItemStyle.label("Link to Utility Panel", systemImage: "dock.rectangle")
                }
                .help("Link this dialog to the utility panel")
                .onChange(of: dialog.isLinkedToUtilityPanel) { oldValue, newValue in
                    do {
                        try viewModel.saveContext()
                        vxAtelierPro.log.debug("DialogView: Saved utility panel link status change ('\(newValue)') for dialog '\(dialog.title)'.")
                    } catch {
                        vxAtelierPro.log.error("DialogView: Failed to save context after utility panel link change: \(error.localizedDescription)")
                    }
                }
            }
#endif
        }

        Divider()

        if viewModel.conversation?.status == .active {
            Button {
                if let id = viewModel.conversation?.id { onRequestOptions(id) }
            } label: {
                MenuItemStyle.label("Dialog Options", systemImage: "slider.horizontal.3")
            }
            .help("Configure dialog settings")
            .keyboardShortcut(",", modifiers: [.command, .option])
        }
    }
}
