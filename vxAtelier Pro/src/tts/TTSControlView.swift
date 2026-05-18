import SwiftData
import SwiftUI

struct TTSControlView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TTSQueue.self) private var ttsQueue

    @Query(sort: [
        SortDescriptor(\TTSPlaylist.updatedAt, order: .reverse),
        SortDescriptor(\TTSPlaylist.createdAt, order: .reverse)
    ])
    private var playlists: [TTSPlaylist]

    @AppStorage(AppSettings.Keys.ttsRepeatMode) private var repeatMode: String = AppDefaults.ttsRepeatMode
    @State private var presentedPlaylistEditor: PlaylistEditor?
    @State private var presentedPlaylistEntryEditor: PlaylistEntryEditor?
    @State private var pendingPlaylistDeletionID: PersistentIdentifier?
    @State private var selectedPlaylistID: PersistentIdentifier?
    @State private var activeTab: TTSTab = .player
    @State private var isImportingPlaylist = false
    @State private var isExportingPlaylistAudio = false
    @State private var exportingPlaylistAudioName: String?
    @State private var playlistAudioExportTask: Task<Void, Never>?
    @State private var showPlaylistImportError = false
    @State private var playlistImportErrorMessage = ""
    @State private var showPlaylistExportError = false
    @State private var playlistExportErrorMessage = ""

    var body: some View {
        ZStack {
            VStack(spacing: AppDefaults.paddingLarge) {
                TTSControlTabSelector(activeTab: $activeTab)
                activeTabContent

                playlistActionsBar
            }
            .navigationTitle("Text to Speech")
            .sheet(item: $presentedPlaylistEditor) { editor in
                PlaylistEditorSheet(
                    title: editor.title,
                    name: editor.name,
                    onCancel: {
                        presentedPlaylistEditor = nil
                    },
                    onSave: { name in
                        if let playlistID = editor.playlistID {
                            ttsQueue.renamePlaylist(id: playlistID, to: name)
                        } else {
                            if let playlist = ttsQueue.createPlaylist(named: name) {
                                selectedPlaylistID = playlist.persistentModelID
                            }
                        }
                        presentedPlaylistEditor = nil
                    }
                )
            }
            .sheet(item: $presentedPlaylistEntryEditor) { editor in
                PlaylistEntryEditorSheet(
                    title: editor.title,
                    text: editor.text,
                    role: editor.role,
                    onCancel: {
                        presentedPlaylistEntryEditor = nil
                    },
                    onSave: { text, role in
                        if let entryID = editor.entryID {
                            ttsQueue.updateEntry(
                                id: entryID,
                                in: editor.playlistID,
                                text: text,
                                role: role.rawValue
                            )
                        } else if let playlistID = editor.playlistID {
                            ttsQueue.selectPlaylist(id: playlistID)
                            ttsQueue.addCustomEntry(
                                text: text,
                                role: role.rawValue
                            )
                        } else {
                            ttsQueue.addCustomEntry(
                                text: text,
                                role: role.rawValue
                            )
                        }
                        presentedPlaylistEntryEditor = nil
                    }
                )
            }
            .confirmationDialog(
                "Delete Playlist",
                isPresented: Binding(
                    get: { pendingPlaylistDeletionID != nil },
                    set: { if !$0 { pendingPlaylistDeletionID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let pendingPlaylistDeletionID {
                        ttsQueue.deletePlaylist(id: pendingPlaylistDeletionID)
                    }
                    self.pendingPlaylistDeletionID = nil
                    syncSelection()
                }
                Button("Cancel", role: .cancel) {
                    pendingPlaylistDeletionID = nil
                }
            } message: {
                Text("Delete selected playlist and its items.")
            }
            .frame(
                minWidth: 760, idealWidth: 1000, maxWidth: .infinity,
                minHeight: 560, idealHeight: 760, maxHeight: .infinity
            )
            .presentationDetents([.large])
            .fileImporter(
                isPresented: $isImportingPlaylist,
                allowedContentTypes: [.json]
            ) { result in
                switch result {
                case .success(let url):
                    Task { await importPlaylist(from: url) }
                case .failure(let error):
                    playlistImportErrorMessage = error.localizedDescription
                    showPlaylistImportError = true
                }
            }
            .alert("Playlist Import", isPresented: $showPlaylistImportError, presenting: playlistImportErrorMessage) { _ in
                Button("OK") { }
            } message: { message in
                Text(message)
            }
            .alert("Playlist Export", isPresented: $showPlaylistExportError, presenting: playlistExportErrorMessage) { _ in
                Button("OK") { }
            } message: { message in
                Text(message)
            }
            .onAppear {
                syncSelection()
            }
            .onChange(of: ttsQueue.currentPlaylistID()) { _, _ in
                syncSelection()
            }
            .onChange(of: playlists.map(\.persistentModelID)) { _, _ in
                syncSelection()
            }
            .padding(AppDefaults.paddingLarge)
            .background(Color(nsColor: .windowBackgroundColor))
            .disabled(isExportingPlaylistAudio)

            if isExportingPlaylistAudio {
                TTSControlExportOverlay(
                    playlistName: exportingPlaylistAudioName,
                    onCancel: {
                        playlistAudioExportTask?.cancel()
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch activeTab {
        case .player:
            playerTab
        case .playlists:
            playlistsTab
        }
    }

    private var playerTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppDefaults.paddingLarge) {
                if let playlist = displayedPlaylist {
                    TTSControlPlayerCard(
                        repeatMode: $repeatMode,
                        progressFraction: progressFraction,
                        isPlaying: ttsQueue.isPlaying,
                        canPlay: ttsQueue.currentPlaylistEntryCount() > 0,
                        previousDisabled: previousButtonDisabled,
                        nextDisabled: nextButtonDisabled,
                        onPrevious: { ttsQueue.previous() },
                        onPlayPause: {
                            if ttsQueue.isPlaying {
                                ttsQueue.pause()
                            } else {
                                ttsQueue.resume()
                            }
                        },
                        onNext: { ttsQueue.next() }
                    )

                    TTSControlPlaylistEntriesCard(
                        playlist: playlist,
                        entries: displayedPlaylistEntries,
                        currentItemID: ttsQueue.currentItem?.persistentModelID,
                        indexForEntry: { displayedPlaylistEntryIndex(for: $0) },
                        onSelectEntry: { ttsQueue.jumpTo($0) },
                        onMoveUp: { moveEntry($0, by: -1) },
                        onMoveDown: { moveEntry($0, by: 1) },
                        onEditEntry: { presentEntryEditor(item: $0) },
                        onDeleteEntry: {
                            guard let removeIndex = displayedPlaylistEntryIndex(for: $0) else { return }
                            ttsQueue.remove(at: removeIndex)
                        }
                    )
                } else {
                    TTSControlEmptyDetailState()
                }
            }
            .padding(AppDefaults.paddingLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var playlistsTab: some View {
        List(selection: playlistSelectionBinding) {
            Section("Playlists") {
                if playlists.isEmpty {
                    TTSControlEmptySidebarState()
                } else {
                    ForEach(playlists) { playlist in
                        TTSControlPlaylistRow(
                            playlist: playlist,
                            isSelected: playlist.persistentModelID == selectedPlaylistID,
                            onSelect: { selectPlaylist(playlist.persistentModelID) },
                            onPlay: { playPlaylist(playlist.persistentModelID) },
                            onRename: {
                                presentedPlaylistEditor = PlaylistEditor(
                                    title: "Rename Playlist",
                                    name: playlist.name,
                                    playlistID: playlist.persistentModelID
                                )
                            },
                            onDelete: {
                                pendingPlaylistDeletionID = playlist.persistentModelID
                            },
                            onAddEntry: {
                                presentPlaylistEntryEditor(
                                    targetPlaylistID: playlist.persistentModelID,
                                    playlistName: playlist.name
                                )
                            }
                        )
                            .tag(Optional(playlist.persistentModelID))
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var playlistActionsBar: some View {
        TTSControlPlaylistActionsBar(
            playlists: playlists,
            selectedPlaylistID: playlistSelectionBinding,
            isPlaylistTabActive: activeTab == .playlists,
            isExportingPlaylistAudio: isExportingPlaylistAudio,
            onNewPlaylist: {
                presentedPlaylistEditor = PlaylistEditor(
                    title: "New Playlist",
                    name: suggestedPlaylistName(),
                    playlistID: nil
                )
            },
            onAddEntry: {
                presentPlaylistEntryEditor(
                    targetPlaylistID: selectedPlaylistID,
                    playlistName: displayedPlaylist?.name
                )
            },
            onImportPlaylist: {
                isImportingPlaylist = true
            },
            onExportAudio: {
                startPlaylistAudioExport()
            },
            onExportJSON: {
                Task { await exportSelectedPlaylistJSON() }
            }
        )
    }

    private var progressFraction: Double {
        let count = max(1, displayedPlaylistEntries.count)
        let progressIndex = min(ttsQueue.currentIndex + 1, count)
        return Double(progressIndex) / Double(count)
    }

    private func displayedPlaylistEntryIndex(for item: TTSPlaylistEntry) -> Int? {
        displayedPlaylistEntries.firstIndex(where: { $0.persistentModelID == item.persistentModelID })
    }

    private func moveEntry(_ item: TTSPlaylistEntry, by offset: Int) {
        guard let index = displayedPlaylistEntryIndex(for: item) else { return }
        let destination = index + offset
        guard destination >= 0, destination < displayedPlaylistEntries.count else { return }
        ttsQueue.moveEntries(from: IndexSet(integer: index), to: destination)
    }

    private func presentPlaylistEntryEditor(targetPlaylistID: PersistentIdentifier?, playlistName: String?) {
        presentedPlaylistEntryEditor = PlaylistEntryEditor(
            title: playlistName.map { "Add Entry to \($0)" } ?? "Add Entry",
            text: "",
            role: .user,
            playlistID: targetPlaylistID,
            entryID: nil
        )
    }

    private func presentEntryEditor(item: TTSPlaylistEntry) {
        presentedPlaylistEntryEditor = PlaylistEntryEditor(
            title: "Edit Entry",
            text: item.displayText,
            role: TTSPlaylistRole(rawValue: item.role) ?? .user,
            playlistID: displayedPlaylist?.persistentModelID ?? selectedPlaylistID,
            entryID: item.persistentModelID
        )
    }

    private func syncSelection() {
        if let currentID = ttsQueue.currentPlaylistID(),
           playlists.contains(where: { $0.persistentModelID == currentID }) {
            selectedPlaylistID = currentID
        } else {
            selectedPlaylistID = nil
        }
    }

    private var playlistSelectionBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { selectedPlaylistID },
            set: { newValue in
                selectPlaylist(newValue)
            }
        )
    }

    private var displayedPlaylist: TTSPlaylist? {
        if let selectedPlaylistID,
           let playlist = playlists.first(where: { $0.persistentModelID == selectedPlaylistID }) {
            return playlist
        }
        return nil
    }

    private var displayedPlaylistEntries: [TTSPlaylistEntry] {
        displayedPlaylist?.orderedEntries ?? []
    }

    private var previousButtonDisabled: Bool {
        ttsQueue.currentPlaylistEntryCount() == 0 || (ttsQueue.currentIndex == 0 && repeatMode != "all")
    }

    private var nextButtonDisabled: Bool {
        ttsQueue.currentPlaylistEntryCount() == 0 || (ttsQueue.currentIndex >= ttsQueue.currentPlaylistEntryCount() - 1 && repeatMode != "all")
    }

    private func suggestedPlaylistName() -> String {
        "Playlist \(playlists.count + 1)"
    }

    private func playPlaylist(_ playlistID: PersistentIdentifier) {
        selectedPlaylistID = playlistID
        ttsQueue.playPlaylist(id: playlistID)
    }

    private func exportSelectedPlaylistJSON() async {
        guard let playlist = displayedPlaylist else { return }
        do {
            try await DataManager.shared.exportPlaylist(playlist)
            vxAtelierPro.log.info("Exported playlist '\(playlist.name)'.")
        } catch is FileHelper.FileError {
            vxAtelierPro.log.debug("Playlist JSON export cancelled for '\(playlist.name)'.")
        } catch {
            playlistExportErrorMessage = "Failed to export playlist JSON: \(error.localizedDescription)"
            showPlaylistExportError = true
            vxAtelierPro.log.error("Failed to export playlist '\(playlist.name)': \(error.localizedDescription)")
        }
    }

    private func exportSelectedPlaylistAudio() async {
        guard let playlist = displayedPlaylist else { return }
        do {
            #if os(macOS)
            let destinationURL = try await FileHelper.shared.selectSaveURL(
                filename: playlist.name,
                allowedContentTypes: [.mpeg4Audio]
            )

            isExportingPlaylistAudio = true
            exportingPlaylistAudioName = playlist.name

            defer {
                isExportingPlaylistAudio = false
                playlistAudioExportTask = nil
                exportingPlaylistAudioName = nil
            }

            try await DataManager.shared.exportPlaylistAudio(playlist, into: modelContext, to: destinationURL)
            #else
            isExportingPlaylistAudio = true
            exportingPlaylistAudioName = playlist.name

            defer {
                isExportingPlaylistAudio = false
                playlistAudioExportTask = nil
                exportingPlaylistAudioName = nil
            }

            try await FileHelper.shared.save(
                filename: playlist.name,
                allowedContentTypes: [.mpeg4Audio]
            ) { destinationURL in
                try await DataManager.shared.exportPlaylistAudio(playlist, into: modelContext, to: destinationURL)
            }
            #endif

            vxAtelierPro.log.info("Exported playlist audio for '\(playlist.name)'.")
        } catch is CancellationError {
            vxAtelierPro.log.debug("Playlist audio export cancelled for '\(playlist.name)'.")
        } catch is FileHelper.FileError {
            vxAtelierPro.log.debug("Playlist audio export cancelled for '\(playlist.name)'.")
        } catch {
            playlistExportErrorMessage = "Failed to export playlist audio: \(error.localizedDescription)"
            showPlaylistExportError = true
            vxAtelierPro.log.error("Failed to export playlist audio for '\(playlist.name)': \(error.localizedDescription)")
        }
    }

    private func startPlaylistAudioExport() {
        guard !isExportingPlaylistAudio else { return }
        playlistAudioExportTask = Task { await exportSelectedPlaylistAudio() }
    }

    private func importPlaylist(from url: URL) async {
        do {
            let playlist = try await DataManager.shared.importPlaylist(from: url, into: modelContext)
            selectedPlaylistID = playlist.persistentModelID
            ttsQueue.selectPlaylist(id: playlist.persistentModelID)
            vxAtelierPro.log.info("Imported playlist '\(playlist.name)'.")
        } catch {
            playlistImportErrorMessage = error.localizedDescription
            showPlaylistImportError = true
            vxAtelierPro.log.error("Failed to import playlist: \(error.localizedDescription)")
        }
    }

    private func selectPlaylist(_ playlistID: PersistentIdentifier?) {
        selectedPlaylistID = playlistID
        ttsQueue.selectPlaylist(id: playlistID)
    }
}
