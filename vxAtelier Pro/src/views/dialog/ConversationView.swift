import SwiftUI
import SwiftData
import Observation
import Foundation

// MARK: - ConversationView
struct ConversationView: View {
    @Environment(QueryManager.self) private var queryManager
    @Environment(TTSQueue.self) private var ttsQueue
    @StateObject private var viewModel: ConversationViewModel

    // Pinned-to-end state and unread indicators
    @State private var isPinnedToEnd: Bool = true
    @State private var unreadCount: Int = 0
    @State private var sendScrollTick: Int = 0

    private var autoScrollDebugEnabled: Bool { UserDefaults.standard.bool(forKey: "AutoScrollDebugEnabled") }

    private var endAnchorID: String {
        if let dialog = viewModel.conversation { return "END-\(dialog.id)" }
        return "END-none"
    }
    
    let scrollHint: PersistentIdentifier?
    let onRequestOptions: (PersistentIdentifier) -> Void

    init(conversationID: PersistentIdentifier, scrollHint: PersistentIdentifier? = nil, onRequestOptions: @escaping (PersistentIdentifier) -> Void = { _ in }) {
        self.scrollHint = scrollHint
        self.onRequestOptions = onRequestOptions
        _viewModel = StateObject(wrappedValue: ConversationViewModel(conversationID: conversationID, queryManager: nil, ttsQueue: nil))
    }

    // Backward compatibility initializer
    init(conversation: ConversationItem, scrollHint: PersistentIdentifier? = nil, onRequestOptions: @escaping (PersistentIdentifier) -> Void = { _ in }) {
        self.init(conversationID: conversation.id, scrollHint: scrollHint, onRequestOptions: onRequestOptions)
    }

    var body: some View {
        // Stable content version for change detection
        let contentVersion: Int = viewModel.conversation?.turns.reduce(0) { $0 + 1 + $1.events.count } ?? 0

        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    // Reversed scroll technique keeps the visual end anchored without bottom sentinel jitter
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            // Visual bottom anchor (placed on top due to rotation)
                            Color.clear
                                .frame(height: 1)
                                .id(endAnchorID)
                                .onAppear { endVisibilityChanged(true) }
                                .onDisappear { endVisibilityChanged(false) }

                            if let dialog = viewModel.conversation {
                                let turns = viewModel.sortedTurns
                                ForEach(turns.reversed(), id: \.id) { turn in
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
                                        isBookmarkedUser: queryManager.isUserBookmarked(turnID: turn.id),
                                        isBookmarkedAssistant: {
                                            if let mid = latestAssistantMessageID(for: turn) {
                                                return queryManager.isAssistantBookmarked(turnID: turn.id, messageID: mid)
                                            }
                                            return false
                                        }()
                                    )
                                    .rotationEffect(.degrees(180)) // invert back per-row
                                }
                            }
                        }
                    }
                    .rotationEffect(.degrees(180)) // reverse the scroll direction for bottom anchoring
                    .onAppear {
                        var tx = Transaction(); tx.disablesAnimations = true
                        if let hint = scrollHint {
                            withTransaction(tx) { proxy.scrollTo(hint, anchor: .center) }
                            isPinnedToEnd = false
                            if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: initial onAppear -> scrolled to hint \(hint)") }
                        } else {
                            // Land at visual bottom (top in reversed space)
                            withTransaction(tx) { proxy.scrollTo(endAnchorID, anchor: .top) }
                            if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: initial onAppear -> scrolled to end") }
                        }
                    }

                    // Floating scroll-to-end button with unread badge
                    if !isPinnedToEnd {
                        Button {
                            withAnimation { proxy.scrollTo(endAnchorID, anchor: .top) }
                            unreadCount = 0
                            isPinnedToEnd = true
                            if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: FAB tapped -> scroll to end") }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.accentColor)
                                if unreadCount > 0 {
                                    Text("\(unreadCount)")
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
                // Scroll triggers
                .onChange(of: contentVersion) {
                    if isPinnedToEnd {
                        var tx = Transaction(); tx.disablesAnimations = true
                        withTransaction(tx) { proxy.scrollTo(endAnchorID, anchor: .top) }
                        if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: contentVersion -> pinned, scrolled to end") }
                    } else {
                        unreadCount = min(unreadCount + 1, 99)
                        if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: contentVersion -> not pinned, unread=\(unreadCount)") }
                    }
                }
                .onChange(of: viewModel.streamingState.text) {
                    if isPinnedToEnd && viewModel.streamingState.isActive {
                        var tx = Transaction(); tx.disablesAnimations = true
                        withTransaction(tx) { proxy.scrollTo(endAnchorID, anchor: .top) }
                        if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: stream flush -> pinned, scrolled to end") }
                    } else if !isPinnedToEnd && viewModel.streamingState.isActive {
                        if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: stream flush -> not pinned") }
                    }
                }
                .onChange(of: sendScrollTick) {
                    withAnimation { proxy.scrollTo(endAnchorID, anchor: .top) }
                    isPinnedToEnd = true
                    unreadCount = 0
                    if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: sendScrollTick -> force scroll to end") }
                }
            }

            if !viewModel.isSelectingMessages, let conversation = viewModel.conversation {
                Divider()
                MessageInputView(
                    dialog: conversation,
                    streamingState: viewModel.streamingState,
                    didSend: { _ in
                        sendScrollTick &+= 1
                        unreadCount = 0
                        if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: didSend -> reset unread and scrolled") }
                    }
                )
                .padding(AppDefaults.paddingSmall)
                .disabled(viewModel.streamingState.isActive)
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
        .onAppear {
            if viewModel.queryManager == nil { viewModel.queryManager = queryManager }
            if viewModel.ttsQueue == nil { viewModel.ttsQueue = ttsQueue }
            viewModel.onAppear()
        }
        .onTapGesture { hideKeyboard() }
        .onChange(of: viewModel.conversation?.id) { oldValue, newValue in
            vxAtelierPro.log.debug("ConversationView: conversation id changed old=\(String(describing: oldValue)) new=\(String(describing: newValue))")
        }
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

    private func endVisibilityChanged(_ visible: Bool) {
        isPinnedToEnd = visible
        if visible { unreadCount = 0 }
        if autoScrollDebugEnabled { vxAtelierPro.log.debug("ConversationView: end visible=\(visible)") }
    }

    private func latestAssistantMessageID(for turn: ConversationTurn) -> PersistentIdentifier? {
        let assistantEvents = turn.events.filter { $0.type == .assistant }
        return assistantEvents.sorted { $0.timestamp < $1.timestamp }.last?.message.id
    }
}

// Preference keys for auto-scroll stickiness removed

struct ConversationMessagesList: View {
    @Environment(QueryManager.self) private var queryManager
    let sortedTurnIDs: [PersistentIdentifier]
    let contentVersion: Int
    let conversationID: PersistentIdentifier
    let selectedMessages: Set<PersistentIdentifier>
    let isSelectingMessages: Bool
    let streamingState: StreamingState
    let onSelect: (PersistentIdentifier) -> Void
    let onTap: (MessageItem, ConversationTurn) -> Void
    let onAction: (MessageAction, MessageItem, ConversationTurn) -> Void
    let onBottomVisibilityChange: (Bool) -> Void
    private var streamingDebugEnabled: Bool { UserDefaults.standard.bool(forKey: "StreamingDebugEnabled") }

    private func logRenderSequence() {
        guard streamingDebugEnabled else { return }
        guard let dialog = queryManager.allConversations.first(where: { $0.id == conversationID }) else { return }
        var parts: [String] = []
        for turnID in sortedTurnIDs {
            guard let turn = dialog.turns.first(where: { $0.id == turnID }) else { continue }
            parts.append("user(\(turn.userMessage.id))@\(turn.userMessage.timestamp.ISO8601Format())")
            for ev in turn.events.sorted(by: compareEvents) {
                parts.append("\(String(describing: ev.type))(\(ev.message.id))@\(ev.timestamp.ISO8601Format())")
            }
        }
        if streamingState.isActive && !streamingState.text.isEmpty,
           let lastTurnID = sortedTurnIDs.last,
           let lastTurn = dialog.turns.first(where: { $0.id == lastTurnID }) {
            parts.append("stream(\(lastTurn.id))@now len=\(streamingState.text.count)")
        }
        vxAtelierPro.log.debug("ConversationMessagesList.render v=\(contentVersion) items=\(parts.count) seq=[\(parts.joined(separator: ", "))]")
    }

    private func eventRank(_ type: TurnEvent.EventType) -> Int {
        switch type {
        case .assistant: return 0
        case .toolCall: return 1
        case .toolResult: return 2
        }
    }

    private func compareEvents(_ a: TurnEvent, _ b: TurnEvent) -> Bool {
        // Primary: event timestamp
        if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
        // Secondary: type rank (assistant < toolCall < toolResult)
        let ra = eventRank(a.type)
        let rb = eventRank(b.type)
        if ra != rb { return ra < rb }
        // Tertiary: message timestamp
        if a.message.timestamp != b.message.timestamp { return a.message.timestamp < b.message.timestamp }
        // Quaternary: toolCallId (if present)
        let aid = a.message.toolCallId ?? ""
        let bid = b.message.toolCallId ?? ""
        if aid != bid { return aid < bid }
        // Final: stable fallback on object identity hash
        return ObjectIdentifier(a.message).hashValue < ObjectIdentifier(b.message).hashValue
    }

    // Compute tool-result message IDs that are collapsed into assistant messages for a turn
    private func hiddenToolResultIds(for turn: ConversationTurn) -> Set<PersistentIdentifier> {
        let assistantEvents = turn.events.filter { $0.type == .assistant }
        let toolResultsById = Dictionary(grouping: turn.events.filter { $0.type == .toolResult && $0.message.toolCallId != nil }, by: { $0.message.toolCallId! })
        var hidden = Set<PersistentIdentifier>()
        for ae in assistantEvents {
            if let calls = ae.message.getToolCalls() {
                for c in calls {
                    let id = c.id
                    if let results = toolResultsById[id] {
                        for r in results { hidden.insert(r.message.id) }
                    }
                }
            }
        }
        return hidden
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(sortedTurnIDs, id: \.self) { turnID in
                if let dialog = queryManager.allConversations.first(where: { $0.id == conversationID }),
                   let turn = dialog.turns.first(where: { $0.id == turnID }) {
                     MessageView(
                         messageID: turn.userMessage.id,
                         turnID: turn.id,
                         conversationID: dialog.id,
                         isSelected: selectedMessages.contains(turn.userMessage.id),
                         isSelecting: isSelectingMessages,
                         onSelect: { onSelect(turn.userMessage.id) },
                         onTap: { 
                             onTap(turn.userMessage, turn) 
                         },
                         onAction: { action in 
                             onAction(action, turn.userMessage, turn) 
                         },
                         isBookmarked: queryManager.isUserBookmarked(turnID: turnID)
                     )
                     .id(turn.userMessage.id)
                     
                     // Build hidden set for tool results that will be shown inside the assistant bubble
                     let hiddenIds = hiddenToolResultIds(for: turn)
                     ForEach(turn.events.sorted(by: compareEvents).filter { $0.type != .toolResult || !hiddenIds.contains($0.message.id) }) { event in
                         MessageView(
                             messageID: event.message.id,
                             turnID: turnID,
                             conversationID: dialog.id,
                             isSelected: selectedMessages.contains(event.message.id),
                             isSelecting: isSelectingMessages,
                             onSelect: { onSelect(event.message.id) },
                             onTap: { 
                                 onTap(event.message, turn) 
                             },
                             onAction: { action in 
                                 onAction(action, event.message, turn) 
                             },
                             isBookmarked: queryManager.isAssistantBookmarked(turnID: turnID, messageID: event.message.id)
                         )
                         .id(event.message.id)
                     }
                 }
             }
            
            if streamingState.isActive,
               !streamingState.text.isEmpty,
               let dialog = queryManager.allConversations.first(where: { $0.id == conversationID }),
               let lastTurnID = sortedTurnIDs.last,
               let lastTurn = dialog.turns.first(where: { $0.id == lastTurnID }) {
                
                MessageView(
                    messageID: nil, // Streaming content doesn't have a persistent ID
                    turnID: lastTurn.id,
                    conversationID: dialog.id,
                    isSelected: false,
                    isSelecting: false,
                    onSelect: {},
                    onTap: {},
                    onAction: { _ in },
                    isBookmarked: false,
                    streamingContent: streamingState.text
                )
                .id("streaming-content")
            }

            // Bottom visibility sentinel inside the lazy stack for reliable viewport tracking
            Color.clear
                .frame(height: 1)
                .id("BOTTOM-\(conversationID)")
                .onAppear { onBottomVisibilityChange(true) }
                .onDisappear { onBottomVisibilityChange(false) }
        }
        .id(contentVersion)
        .onAppear {
            logRenderSequence()
        }
        .onChange(of: contentVersion) {
            logRenderSequence()
        }
        .onChange(of: streamingState.text) {
            if streamingDebugEnabled && streamingState.isActive {
                vxAtelierPro.log.debug("ConversationMessagesList.stream len=\(streamingState.text.count)")
            }
        }
        .onChange(of: streamingState.isActive) {
            if streamingDebugEnabled {
                vxAtelierPro.log.debug("ConversationMessagesList.streamActive=\(streamingState.isActive)")
            }
        }
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
