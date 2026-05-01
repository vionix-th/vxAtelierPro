import SwiftUI
import SwiftData
import Foundation

// MARK: - ConversationView
struct ConversationView: View {
    @Bindable var viewModel: ConversationViewModel
    
    let scrollHint: PersistentIdentifier?
    let onRequestOptions: (PersistentIdentifier) -> Void

    init(
        viewModel: ConversationViewModel,
        scrollHint: PersistentIdentifier? = nil,
        onRequestOptions: @escaping (PersistentIdentifier) -> Void = { _ in }
    ) {
        self._viewModel = Bindable(wrappedValue: viewModel)
        self.scrollHint = scrollHint
        self.onRequestOptions = onRequestOptions
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if let conversation = viewModel.conversation {
                                let turns = viewModel.sortedTurns
                                ForEach(turns, id: \.id) { turn in
                                    ConversationTurnView(
                                        conversationID: conversation.id,
                                        turn: turn,
                                        isLastTurn: turn.id == turns.last?.id,
                                        draftStore: viewModel.draftStore,
                                        isSelecting: viewModel.isSelectingMessages,
                                        isSelected: { viewModel.selectedMessages.contains($0) },
                                        onSelect: { viewModel.toggleSelection(for: $0) },
                                        onTap: { message, t in
                                            hideKeyboard()
                                            if viewModel.isSelectingMessages { viewModel.toggleSelection(for: message.id) }
                                        },
                                        onAction: { action, message, t in
                                            viewModel.handleMessageAction(action, message: message, turn: t)
                                        },
                                        isBookmarkedUser: viewModel.queryManager.isUserBookmarked(turnID: turn.id),
                                        isBookmarkedAssistant: { messageID in
                                            viewModel.queryManager.isAssistantBookmarked(turnID: turn.id, messageID: messageID)
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
                    viewModel.onAppear()
                }

                if !viewModel.isSelectingMessages, let conversation = viewModel.conversation {
                    Divider()
                    MessageInputView(
                        queryManager: viewModel.queryManager,
                        draftStore: viewModel.draftStore,
                        contextConversation: conversation,
                        resolveConversation: {
                            if let conversation = viewModel.conversation {
                                return conversation
                            }
                            throw AppError.invalidOperation("Conversation not available")
                        }
                    )
                    .padding(AppDefaults.paddingSmall)
                    .disabled(viewModel.draftStore.isActive)
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
                        onBookmark: { _, _, label in
                            viewModel.insertBookmark(label: label, message: message)
                            viewModel.bookmarkMessage = nil
                        },
                        onCancel: {
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

struct SelectionModeMenu: View {
    @Bindable var viewModel: ConversationViewModel
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
        .help("Select all messages in this conversation")

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
                viewModel.deleteTurnsContainingMessages(viewModel.selectedMessages.map { $0 })                
                viewModel.exitSelectionMode()                
            } label: {
                MenuItemStyle.label("Delete Selected", systemImage: "trash")
            }
            .help("Permanently delete selected messages")
            .disabled(viewModel.selectedMessages.isEmpty)
        }
    }
}

struct NormalModeMenu: View {
    @Bindable var viewModel: ConversationViewModel
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
            if let conversation = viewModel.conversation {
                Toggle(isOn: Binding(get: { conversation.isUtilityConversation }, set: { newValue in
                    do {
                        try viewModel.queryManager.setUtilityPanelConversation(conversation, isLinked: newValue)
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

        if viewModel.conversation?.status == .active {
            Button {
                if let id = viewModel.conversation?.id { onRequestOptions(id) }
            } label: {
                MenuItemStyle.label("Conversation Options", systemImage: "slider.horizontal.3")
            }
            .help("Configure conversation settings")
            .keyboardShortcut(",", modifiers: [.command, .option])
        }
    }
}
