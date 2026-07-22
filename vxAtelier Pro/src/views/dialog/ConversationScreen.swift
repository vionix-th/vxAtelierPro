import SwiftData
import SwiftUI

struct ConversationScreen: View {
    @Environment(QueryManager.self) private var queryManager
    @Environment(AppSceneModel.self) private var sceneModel
    @Environment(NavigationRouter.self) private var router
    @Environment(TTSQueue.self) private var ttsQueue

    let conversationID: PersistentIdentifier
    let onRequestOptions: (PersistentIdentifier) -> Void

    @State private var selectedMessageIDs = Set<PersistentIdentifier>()
    @State private var isSelecting = false
    @State private var draftStore = ConversationDraftStore()
    @State private var errorAlert: ErrorAlert?
    @State private var bookmarkContext: ConversationMessageReference?
    @State private var bookmarkLabel = ""

    init(
        conversationID: PersistentIdentifier,
        onRequestOptions: @escaping (PersistentIdentifier) -> Void = { _ in }
    ) {
        self.conversationID = conversationID
        self.onRequestOptions = onRequestOptions
    }

    var body: some View {
        Group {
            if let conversation, let presentation {
                VStack(spacing: 0) {
                    ConversationTimelineView(
                        presentation: presentation,
                        playlists: playlistSnapshots,
                        draftStore: draftStore,
                        scrollRequest: router.conversationScrollRequest,
                        isSelecting: isSelecting,
                        selectedMessageIDs: selectedMessageIDs,
                        onSelect: toggleSelection,
                        onMessageTap: handleMessageTap,
                        onMessageAction: handleMessageAction,
                        onConsumeScrollRequest: router.consumeConversationScrollRequest
                    )

                    if !isSelecting {
                        Divider()
                        ConversationComposerView(
                            queryManager: queryManager,
                            draftStore: draftStore,
                            contextConversationID: conversation.persistentModelID,
                            resolveConversation: {
                                guard let resolved = queryManager.conversation(with: conversationID) else {
                                    throw AppError.invalidOperation("Conversation not available")
                                }
                                return resolved
                            }
                        )
                        .padding(AppDefaults.paddingSmall)
                    }
                }
                .navigationTitle(presentation.title)
                .onChange(of: presentation.messageIDs) { _, messageIDs in
                    selectedMessageIDs.formIntersection(messageIDs)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        toolbarMenu(presentation: presentation)
                    }
                }
            } else {
                Text("Conversation Not Found")
                    .foregroundColor(.secondary)
            }
        }
        .padding(AppDefaults.paddingSmall)
        .errorAlert(error: $errorAlert)
        .sheet(
            isPresented: Binding(
                get: { bookmarkContext != nil },
                set: { if !$0 { bookmarkContext = nil } }
            )
        ) {
            BookmarkSheetView(
                label: $bookmarkLabel,
                onBookmark: confirmBookmark,
                onCancel: { bookmarkContext = nil }
            )
        }
        .onAppear {
            sceneModel.focusConversation(conversationID)
            vxAtelierPro.log.debug("ConversationScreen appeared: \(conversationID)")
        }
        .onDisappear {
            sceneModel.clearConversationFocus(conversationID)
        }
        .onTapGesture {
            hideKeyboard()
        }
        .onKeyPress(.escape) {
            guard isSelecting else { return .ignored }
            exitSelectionMode()
            return .handled
        }
    }

    private var conversation: ConversationItem? {
        queryManager.conversation(with: conversationID)
    }

    private var presentation: ConversationPresentationSnapshot? {
        conversation.map(ConversationPresentationBuilder.build)
    }

    private var commands: ConversationCommands {
        ConversationCommands(
            queryManager: queryManager,
            ttsQueue: ttsQueue,
            conversationID: conversationID
        )
    }

    private var playlistSnapshots: [ConversationPlaylistSnapshot] {
        ttsQueue.playlists().map {
            ConversationPlaylistSnapshot(id: $0.persistentModelID, name: $0.name)
        }
    }

    private func toolbarMenu(
        presentation: ConversationPresentationSnapshot
    ) -> some View {
        ConversationToolbarMenu(
            isSelecting: isSelecting,
            selectedMessageCount: selectedMessageIDs.count,
            hasMessages: !presentation.rows.isEmpty,
            isActive: presentation.isActive,
            isUtilityConversation: presentation.isUtilityConversation,
            playlists: playlistSnapshots,
            onBeginSelection: { isSelecting = true },
            onExitSelection: exitSelectionMode,
            onSelectAll: { selectedMessageIDs = presentation.messageIDs },
            onInvertSelection: {
                selectedMessageIDs = presentation.messageIDs.subtracting(selectedMessageIDs)
            },
            onAddSelectionToNewPlaylist: {
                performSelectionCommand {
                    try commands.addToNewPlaylist(messageIDs: selectedMessageIDs)
                }
            },
            onAddSelectionToPlaylist: { playlistID in
                performSelectionCommand {
                    try commands.addToPlaylist(
                        messageIDs: selectedMessageIDs,
                        playlistID: playlistID
                    )
                }
            },
            onAddAllToNewPlaylist: {
                perform {
                    try commands.addToNewPlaylist(messageIDs: presentation.messageIDs)
                }
            },
            onAddAllToPlaylist: { playlistID in
                perform {
                    try commands.addToPlaylist(
                        messageIDs: presentation.messageIDs,
                        playlistID: playlistID
                    )
                }
            },
            onCopySelectionText: {
                perform { try commands.copyText(messageIDs: selectedMessageIDs) }
            },
            onCopySelectionJSON: {
                perform { try commands.copyJSON(messageIDs: selectedMessageIDs) }
                exitSelectionMode()
            },
            onExportSelection: exportSelection,
            onDeleteSelection: {
                perform { try commands.deleteMessages(selectedMessageIDs) }
                exitSelectionMode()
            },
            onSetUtilityConversation: { isLinked in
                perform { try commands.setUtilityConversation(isLinked) }
            },
            onRequestOptions: { onRequestOptions(conversationID) }
        )
    }

    private func handleMessageTap(_ messageID: PersistentIdentifier) {
        hideKeyboard()
        if isSelecting {
            toggleSelection(messageID)
        }
    }

    private func toggleSelection(_ messageID: PersistentIdentifier) {
        if selectedMessageIDs.contains(messageID) {
            selectedMessageIDs.remove(messageID)
        } else {
            selectedMessageIDs.insert(messageID)
        }
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedMessageIDs.removeAll()
    }

    private func handleMessageAction(
        _ action: ConversationMessageAction,
        reference: ConversationMessageReference
    ) {
        switch action {
        case .bookmark:
            bookmarkLabel = ""
            bookmarkContext = reference
        case .removeBookmark:
            perform { try commands.removeBookmark(reference: reference) }
        case .fork:
            perform { try commands.fork(turnID: reference.turnID) }
        case .addToNewPlaylist:
            perform {
                try commands.addToNewPlaylist(messageIDs: [reference.messageID])
            }
        case .addToPlaylist(let playlistID):
            perform {
                try commands.addToPlaylist(
                    messageIDs: [reference.messageID],
                    playlistID: playlistID
                )
            }
        case .select:
            isSelecting = true
            selectedMessageIDs.insert(reference.messageID)
        case .copyText:
            perform { try commands.copyText(messageID: reference.messageID) }
        case .copyJSON:
            perform { try commands.copyJSON(messageID: reference.messageID) }
        case .delete:
            perform { try commands.deleteMessages([reference.messageID]) }
        }
    }

    private func confirmBookmark() {
        guard let bookmarkContext else { return }
        perform {
            try commands.insertBookmark(label: bookmarkLabel, reference: bookmarkContext)
        }
        self.bookmarkContext = nil
    }

    private func performSelectionCommand(_ action: () throws -> Void) {
        perform(action)
        exitSelectionMode()
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            vxAtelierPro.log.error("Conversation command failed: \(error.localizedDescription)")
            errorAlert = ErrorAlert(error: error)
        }
    }

    private func exportSelection() {
        let messageIDs = selectedMessageIDs
        Task { @MainActor in
            do {
                try await commands.export(messageIDs: messageIDs)
            } catch {
                vxAtelierPro.log.error("Conversation export failed: \(error.localizedDescription)")
                errorAlert = ErrorAlert(error: error)
            }
        }
    }
}
