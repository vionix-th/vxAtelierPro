import SwiftData
import SwiftUI

struct TTSControlView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TTSQueue.self) private var ttsQueue
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: [
        SortDescriptor(\TTSPlaylist.updatedAt, order: .reverse),
        SortDescriptor(\TTSPlaylist.createdAt, order: .reverse)
    ])
    private var playlists: [TTSPlaylist]

    @AppStorage(AppSettings.Keys.ttsRepeatMode) private var repeatMode: String = AppDefaults.ttsRepeatMode
    @State private var playlistEditor: PlaylistEditor?
    @State private var deletePlaylistID: PersistentIdentifier?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                nowPlayingSection
                
                playerControls
                
                List {
                    Section("Playlists") {
                        if playlists.isEmpty {
                            Text("No playlists yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(playlists) { playlist in
                                playlistRow(for: playlist)
                            }
                        }
                    }

                    Section(currentPlaylistSectionTitle) {
                        if currentEntries.isEmpty {
                            Text("Add messages to build this playlist.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(currentEntries.enumerated()), id: \.element.id) { index, item in
                                playlistEntryRow(index: index, item: item)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Text to Speech")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close Player", systemImage: "xmark.square")
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        playlistEditor = PlaylistEditor(
                            title: "New Playlist",
                            name: suggestedPlaylistName(),
                            playlistID: nil
                        )
                    } label: {
                        Label("New Playlist", systemImage: "plus")
                    }

                    Button {
                        ttsQueue.clear()
                    } label: {
                        Label("Clear Playlist", systemImage: "eraser")
                    }
                    .disabled(ttsQueue.currentPlaylistEntryCount() == 0)
                }
            }
            .sheet(item: $playlistEditor) { editor in
                PlaylistEditorSheet(
                    title: editor.title,
                    name: editor.name,
                    onCancel: {
                        playlistEditor = nil
                    },
                    onSave: { name in
                        if let playlistID = editor.playlistID {
                            ttsQueue.renamePlaylist(id: playlistID, to: name)
                        } else {
                            _ = ttsQueue.createPlaylist(named: name)
                        }
                        playlistEditor = nil
                    }
                )
            }
            .confirmationDialog(
                "Delete Playlist",
                isPresented: Binding(
                    get: { deletePlaylistID != nil },
                    set: { if !$0 { deletePlaylistID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let deletePlaylistID {
                        ttsQueue.deletePlaylist(id: deletePlaylistID)
                    }
                    self.deletePlaylistID = nil
                }
                Button("Cancel", role: .cancel) {
                    deletePlaylistID = nil
                }
            } message: {
                Text("Delete selected playlist and its items.")
            }
        }
        .frame(
            minWidth: 360, idealWidth: 520, maxWidth: .infinity,
            minHeight: 480, idealHeight: 720, maxHeight: .infinity
        )
        .presentationDetents([.medium, .large])
        .onAppear {
            ttsQueue.selectFirstPlaylistIfNeeded()
        }
    }

    private var nowPlayingSection: some View {
        VStack(spacing: 12) {
            if let currentPlaylist = ttsQueue.currentPlaylist {
                VStack(spacing: 12) {
                    Circle()
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
                        )
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "waveform")
                                .font(.title)
                                .foregroundColor(ttsQueue.isPlaying ? .accentColor : .secondary)
                        )
                        .padding(.top)

                    Text(currentPlaylist.name)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let currentItem = ttsQueue.currentItem {
                        ScrollView {
                            Text(currentItem.displayText)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    colorScheme == .dark
                                        ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                        )
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 8) {
                            Text("Playlist is empty")
                                .font(.headline)
                            Text("Add messages to start playback.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    colorScheme == .dark
                                        ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                        )
                        .padding(.horizontal)
                    }
                }
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .background(colorScheme == .dark ? Color.black : Color.white)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No active playlist")
                        .font(.headline)
                    Text("Create or select playlist to start playback.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .background(colorScheme == .dark ? Color.black : Color.white)
            }
        }
    }

    private var currentEntries: [TTSPlaylistEntry] {
        ttsQueue.currentPlaylistOrderedEntries()
    }

    private var currentPlaylistSectionTitle: String {
        ttsQueue.currentPlaylistName().map { "\($0) Items" } ?? "Items"
    }

    private var playerControls: some View {
        VStack(spacing: 16) {
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(
                        width: progressWidth(totalWidth: geometry.size.width)
                    )
                    .frame(height: 2)
            }
            .frame(height: 2)

            HStack {
                Spacer()

                Button {
                    switch repeatMode {
                    case "none": repeatMode = "one"
                    case "one": repeatMode = "all"
                    case "all": repeatMode = "none"
                    default: repeatMode = "none"
                    }
                } label: {
                    Image(systemName: repeatModeIcon)
                        .foregroundColor(repeatMode == "none" ? .secondary : .accentColor)
                }

                Spacer()
            }
            .font(.caption)

            HStack(spacing: 24) {
                Spacer()

                Button(action: { ttsQueue.previous() }) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .foregroundColor(previousButtonColor)
                }
                .disabled(previousButtonDisabled)

                Button(action: {
                    if ttsQueue.isPlaying {
                        ttsQueue.pause()
                    } else {
                        ttsQueue.resume()
                    }
                }) {
                    Image(systemName: ttsQueue.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)
                }
                .disabled(ttsQueue.currentPlaylistEntryCount() == 0)

                Button(action: { ttsQueue.next() }) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundColor(nextButtonColor)
                }
                .disabled(nextButtonDisabled)

                Spacer()
            }
            .padding(.vertical, 8)
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
    }

    private func playlistRow(for playlist: TTSPlaylist) -> some View {
        let isSelected = playlist.id == ttsQueue.currentPlaylistID()
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "play.fill" : "music.note.list")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .foregroundStyle(.primary)
                Text("\(playlist.orderedEntries.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                ttsQueue.playPlaylist(id: playlist.id)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.plain)
            .help("Play playlist")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ttsQueue.selectPlaylist(id: playlist.id)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                playlistEditor = PlaylistEditor(
                    title: "Rename Playlist",
                    name: playlist.name,
                    playlistID: playlist.id
                )
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                deletePlaylistID = playlist.id
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                ttsQueue.playPlaylist(id: playlist.id)
            } label: {
                Label("Play", systemImage: "play.circle")
            }

            Button {
                playlistEditor = PlaylistEditor(
                    title: "Rename Playlist",
                    name: playlist.name,
                    playlistID: playlist.id
                )
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                deletePlaylistID = playlist.id
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func playlistEntryRow(index: Int, item: TTSPlaylistEntry) -> some View {
        HStack(spacing: 12) {
            if index == ttsQueue.currentIndex && item.id == ttsQueue.currentItem?.id {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(.accentColor)
            } else {
                Text("\(index + 1)")
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayText)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                HStack {
                    Text(item.role.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if item.sourceConversationIDString != nil {
                        Text("Source linked")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button(role: .destructive) {
                ttsQueue.remove(at: index)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from playlist")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ttsQueue.jumpTo(index)
        }
    }

    private func progressWidth(totalWidth: CGFloat) -> CGFloat {
        let count = ttsQueue.currentPlaylistEntryCount()
        guard count > 0 else { return 0 }
        let progressIndex = min(ttsQueue.currentIndex + 1, count)
        return totalWidth * (CGFloat(progressIndex) / CGFloat(count))
    }

    private func suggestedPlaylistName() -> String {
        "Playlist \(playlists.count + 1)"
    }

    private var repeatModeIcon: String {
        switch repeatMode {
        case "none": return "repeat"
        case "one": return "repeat.1"
        case "all": return "repeat.circle"
        default: return "repeat"
        }
    }

    private var previousButtonColor: Color {
        guard ttsQueue.currentPlaylistEntryCount() > 0 else { return .secondary }
        return (ttsQueue.currentIndex > 0 || repeatMode == "all") ? .primary : .secondary
    }

    private var previousButtonDisabled: Bool {
        ttsQueue.currentPlaylistEntryCount() == 0 || (ttsQueue.currentIndex == 0 && repeatMode != "all")
    }

    private var nextButtonColor: Color {
        guard ttsQueue.currentPlaylistEntryCount() > 0 else { return .secondary }
        return (ttsQueue.currentIndex < ttsQueue.currentPlaylistEntryCount() - 1 || repeatMode == "all") ? .primary : .secondary
    }

    private var nextButtonDisabled: Bool {
        ttsQueue.currentPlaylistEntryCount() == 0 || (ttsQueue.currentIndex >= ttsQueue.currentPlaylistEntryCount() - 1 && repeatMode != "all")
    }
}

private struct PlaylistEditor: Identifiable {
    let id = UUID()
    let title: String
    let name: String
    let playlistID: PersistentIdentifier?
}

private struct PlaylistEditorSheet: View {
    let title: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String

    init(title: String, name: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.title = title
        self.onCancel = onCancel
        self.onSave = onSave
        _draftName = State(initialValue: name)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $draftName)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draftName)
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 180)
    }
}

//#Preview{
//    TTSControlView()
//        .bootstrapped(with: .preview())
//        
//}
