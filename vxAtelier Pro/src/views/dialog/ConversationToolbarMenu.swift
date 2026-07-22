import SwiftData
import SwiftUI

struct ConversationToolbarMenu: View {
    let isSelecting: Bool
    let selectedMessageCount: Int
    let hasMessages: Bool
    let isActive: Bool
    let isUtilityConversation: Bool
    let playlists: [ConversationPlaylistSnapshot]

    let onBeginSelection: () -> Void
    let onExitSelection: () -> Void
    let onSelectAll: () -> Void
    let onInvertSelection: () -> Void
    let onAddSelectionToNewPlaylist: () -> Void
    let onAddSelectionToPlaylist: (PersistentIdentifier) -> Void
    let onAddAllToNewPlaylist: () -> Void
    let onAddAllToPlaylist: (PersistentIdentifier) -> Void
    let onCopySelectionText: () -> Void
    let onCopySelectionJSON: () -> Void
    let onExportSelection: () -> Void
    let onDeleteSelection: () -> Void
    let onSetUtilityConversation: (Bool) -> Void
    let onRequestOptions: () -> Void

    var body: some View {
        Menu {
            if isSelecting {
                selectionMenu
            } else {
                normalMenu
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundColor(.gray)
                .font(.title2)
        }
    }

    @ViewBuilder
    private var selectionMenu: some View {
        Button(action: onExitSelection) {
            MenuItemStyle.label("Exit Selection Mode", systemImage: "xmark.circle")
        }
        .keyboardShortcut(.escape, modifiers: [])

        Divider()

        Button(action: onSelectAll) {
            MenuItemStyle.label("Select All Messages", systemImage: "checkmark.circle.fill")
        }
        Button(action: onInvertSelection) {
            MenuItemStyle.label("Invert Selection", systemImage: "arrow.2.circlepath")
        }
        .disabled(selectedMessageCount == 0)

        Divider()

        playlistMenu(
            isDisabled: selectedMessageCount == 0,
            onNewPlaylist: onAddSelectionToNewPlaylist,
            onPlaylist: onAddSelectionToPlaylist
        )

        Divider()

        Button(action: onCopySelectionText) {
            MenuItemStyle.label("Copy as Text", systemImage: "doc.on.doc")
        }
        .disabled(selectedMessageCount == 0)
        Button(action: onCopySelectionJSON) {
            MenuItemStyle.label("Copy as JSON", systemImage: "doc.on.clipboard")
        }
        .disabled(selectedMessageCount == 0)
        Button(action: onExportSelection) {
            MenuItemStyle.label("Export Selected Messages", systemImage: "arrow.up.doc")
        }
        .disabled(selectedMessageCount == 0)

        if isActive {
            Divider()
            Button(role: .destructive, action: onDeleteSelection) {
                MenuItemStyle.label("Delete Selected", systemImage: "trash")
            }
            .disabled(selectedMessageCount == 0)
        }
    }

    @ViewBuilder
    private var normalMenu: some View {
        Button(action: onBeginSelection) {
            MenuItemStyle.label("Select Messages", systemImage: "checkmark.circle")
        }

        Divider()

        playlistMenu(
            isDisabled: !hasMessages,
            onNewPlaylist: onAddAllToNewPlaylist,
            onPlaylist: onAddAllToPlaylist
        )

        if isActive {
            Divider()
            #if os(macOS)
            Toggle(
                isOn: Binding(
                    get: { isUtilityConversation },
                    set: onSetUtilityConversation
                )
            ) {
                MenuItemStyle.label("Link to Utility Panel", systemImage: "dock.rectangle")
            }
            #endif

            Divider()

            Button(action: onRequestOptions) {
                MenuItemStyle.label("Conversation Options", systemImage: "slider.horizontal.3")
            }
            .keyboardShortcut(",", modifiers: [.command, .option])
        }
    }

    private func playlistMenu(
        isDisabled: Bool,
        onNewPlaylist: @escaping () -> Void,
        onPlaylist: @escaping (PersistentIdentifier) -> Void
    ) -> some View {
        Menu {
            Button(action: onNewPlaylist) {
                MenuItemStyle.label("New Playlist", systemImage: "plus.square.on.square")
            }
            if !playlists.isEmpty {
                Divider()
                ForEach(playlists) { playlist in
                    Button {
                        onPlaylist(playlist.id)
                    } label: {
                        MenuItemStyle.label(playlist.name, systemImage: "music.note.list")
                    }
                }
            }
        } label: {
            MenuItemStyle.label("Add to Playlist", systemImage: "speaker.wave.2.bubble")
        }
        .disabled(isDisabled)
    }
}
