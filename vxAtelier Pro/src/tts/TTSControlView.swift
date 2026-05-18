import SwiftData
import SwiftUI

struct TTSControlView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TTSQueue.self) private var ttsQueue

    @Query(sort: [
        SortDescriptor(\TTSPlaylist.updatedAt, order: .reverse),
        SortDescriptor(\TTSPlaylist.createdAt, order: .reverse)
    ])
    private var playlists: [TTSPlaylist]

    @AppStorage(AppSettings.Keys.ttsRepeatMode) private var repeatMode: String = AppDefaults.ttsRepeatMode
    @State private var presentedPlaylistEditor: PlaylistEditor?
    @State private var presentedCustomEntryEditor: CustomPlaylistEntryEditor?
    @State private var pendingPlaylistDeletionID: PersistentIdentifier?
    @State private var focusedPlaylistID: PersistentIdentifier?
    @State private var selectedPlaylistID: PersistentIdentifier?
    @State private var activeTab: TTSTab = .player

    var body: some View {
        VStack(spacing: AppDefaults.paddingLarge) {
            tabSelector
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
                        _ = ttsQueue.createPlaylist(named: name)
                    }
                    presentedPlaylistEditor = nil
                }
            )
        }
        .sheet(item: $presentedCustomEntryEditor) { editor in
            CustomPlaylistEntryEditorSheet(
                title: editor.title,
                onCancel: {
                    presentedCustomEntryEditor = nil
                },
                onSave: { text, role in
                    if let playlistID = editor.playlistID {
                        ttsQueue.selectPlaylist(id: playlistID)
                    }
                    ttsQueue.addCustomEntry(
                        text: text,
                        role: role.rawValue
                    )
                    presentedCustomEntryEditor = nil
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
    }

    private var tabSelector: some View {
        HStack(spacing: AppDefaults.paddingSmall) {
            tabButton(title: "Player", systemImage: "play.circle", tab: .player)
            tabButton(title: "Playlists", systemImage: "music.note.list", tab: .playlists)
            Spacer(minLength: 0)
        }
    }

    private func tabButton(title: String, systemImage: String, tab: TTSTab) -> some View {
        Button {
            activeTab = tab
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, AppDefaults.paddingMedium)
                .padding(.vertical, AppDefaults.paddingSmall)
                .foregroundStyle(activeTab == tab ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium, style: .continuous)
                        .fill(activeTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
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
                    transportCard
                    entriesCard(for: playlist)
                } else {
                    emptyDetailState
                }
            }
            .padding(AppDefaults.paddingLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(detailBackground)
    }

    private var playlistsTab: some View {
        List(selection: $focusedPlaylistID) {
            Section("Playlists") {
                if playlists.isEmpty {
                    emptySidebarState
                } else {
                    ForEach(playlists) { playlist in
                        playlistRow(for: playlist)
                            .tag(Optional(playlist.persistentModelID))
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var playlistActionsBar: some View {
        VStack(spacing: AppDefaults.paddingSmall) {
            Divider()
            HStack(spacing: AppDefaults.paddingMedium) {
                if playlists.isEmpty {
                    Text("No playlists")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("", selection: playlistSelectionBinding) {
                        ForEach(playlists) { playlist in
                            Text(playlist.name)
                                .tag(Optional(playlist.persistentModelID))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Button {
                    presentedPlaylistEditor = PlaylistEditor(
                        title: "New Playlist",
                        name: suggestedPlaylistName(),
                        playlistID: nil
                    )
                } label: {
                    Label("New Playlist", systemImage: "plus")
                }

                Button {
                    presentCustomEntryEditor(
                        targetPlaylistID: focusedPlaylistID ?? ttsQueue.currentPlaylistID(),
                        playlistName: displayedPlaylist?.name
                    )
                } label: {
                    Label("Add Custom Entry", systemImage: "text.badge.plus")
                }

                Spacer()

                Text("\(playlists.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppDefaults.paddingLarge)
            .padding(.vertical, AppDefaults.paddingSmall)
        }
        .padding(.top, AppDefaults.paddingSmall)
    }

    private var transportCard: some View {
        VStack(spacing: AppDefaults.paddingMedium) {
            HStack {
                Text("Playback")
                    .font(.headline)
                
                Spacer(minLength: 0)
            }
            progressBar

            HStack(spacing: AppDefaults.paddingMedium) {
                Button(action: { ttsQueue.previous() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.secondary)
                .disabled(previousButtonDisabled)

                Button(action: {
                    if ttsQueue.isPlaying {
                        ttsQueue.pause()
                    } else {
                        ttsQueue.resume()
                    }
                }) {
                    Image(systemName: ttsQueue.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(ttsQueue.currentPlaylistEntryCount() == 0)

                Button(action: { ttsQueue.next() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.secondary)
                .disabled(nextButtonDisabled)

                Spacer(minLength: 0)

                Menu {
                    Button("Repeat Off") { repeatMode = "none" }
                    Button("Repeat One") { repeatMode = "one" }
                    Button("Repeat All") { repeatMode = "all" }
                } label: {
                    Image(systemName: repeatModeIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .help(repeatModeTitle)
            }
        }
        .padding(AppDefaults.paddingLarge)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous))
    }

    private func entriesCard(for playlist: TTSPlaylist) -> some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
            HStack {
                Text(playlist.name)
                    .font(.headline)

                Spacer(minLength: 0)
            }

            if playlist.orderedEntries.isEmpty {
                emptyEntriesState
            } else {
                LazyVStack(spacing: AppDefaults.paddingSmall) {
                    ForEach(playlist.orderedEntries) { item in
                        playlistEntryRow(item: item)
                    }
                }
            }
        }
        .padding(AppDefaults.paddingLarge)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous))
    }

    private func playlistRow(for playlist: TTSPlaylist) -> some View {
        let isSelected = playlist.persistentModelID == focusedPlaylistID

        return HStack(spacing: AppDefaults.paddingMedium) {
            ZStack {
                RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    .frame(width: 34, height: 34)

                Image(systemName: isSelected ? "play.fill" : "music.note.list")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                Text(playlist.name)
                    .foregroundStyle(.primary)
                Text("\(playlist.orderedEntries.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                ttsQueue.playPlaylist(id: playlist.persistentModelID)
                focusedPlaylistID = playlist.persistentModelID
            } label: {
                Image(systemName: "play.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .help("Play playlist")
        }
        .padding(.vertical, AppDefaults.paddingSmall)
        .contentShape(Rectangle())
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        .onTapGesture {
            focusedPlaylistID = playlist.persistentModelID
            ttsQueue.selectPlaylist(id: playlist.persistentModelID)
        }
        .contextMenu {
            Button {
                ttsQueue.playPlaylist(id: playlist.persistentModelID)
                focusedPlaylistID = playlist.persistentModelID
            } label: {
                Label("Play", systemImage: "play.circle")
            }

            Button {
                presentedPlaylistEditor = PlaylistEditor(
                    title: "Rename Playlist",
                    name: playlist.name,
                    playlistID: playlist.persistentModelID
                )
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                pendingPlaylistDeletionID = playlist.persistentModelID
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Divider()

            Button {
                presentCustomEntryEditor(
                    targetPlaylistID: playlist.persistentModelID,
                    playlistName: playlist.name
                )
            } label: {
                Label("Add Entry", systemImage: "text.badge.plus")
            }
        }
    }

    private func playlistEntryRow(item: TTSPlaylistEntry) -> some View {
        let isCurrent = item.persistentModelID == ttsQueue.currentItem?.persistentModelID

        return HStack(spacing: AppDefaults.paddingMedium) {
            VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                HStack(spacing: AppDefaults.paddingSmall) {
                    if let index = displayedPlaylistEntryIndex(for: item) {
                        entryIndexBadge(number: index + 1)
                    }

                    if isCurrent {
                        Label("Now playing", systemImage: "speaker.wave.2.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text(item.role.capitalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(item.displayText)
                    .font(.body)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if item.sourceConversationIDString != nil {
                    Text("Source linked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: AppDefaults.paddingMedium)

            HStack(spacing: AppDefaults.paddingSmall) {
                Button {
                    moveEntry(item, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveEntry(item, by: -1))
                .help("Move up")

                Button {
                    moveEntry(item, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveEntry(item, by: 1))
                .help("Move down")

                Button(role: .destructive) {
                    guard let removeIndex = displayedPlaylistEntryIndex(for: item) else { return }
                    ttsQueue.remove(at: removeIndex)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Remove from playlist")
            }
        }
        .padding(AppDefaults.paddingMedium)
        .background(
            RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous)
                .stroke(isCurrent ? Color.accentColor.opacity(0.16) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard let index = displayedPlaylistEntryIndex(for: item) else { return }
            ttsQueue.jumpTo(index)
        }
    }

    private func displayedPlaylistEntryIndex(for item: TTSPlaylistEntry) -> Int? {
        displayedPlaylistEntries.firstIndex(where: { $0.persistentModelID == item.persistentModelID })
    }

    private func entryIndexBadge(number: Int) -> some View {
        Text(String(number))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium, style: .continuous))
    }

    private func moveEntry(_ item: TTSPlaylistEntry, by offset: Int) {
        guard let index = displayedPlaylistEntryIndex(for: item) else { return }
        let destination = index + offset
        guard destination >= 0, destination < displayedPlaylistEntries.count else { return }
        ttsQueue.moveEntries(from: IndexSet(integer: index), to: destination)
    }

    private func canMoveEntry(_ item: TTSPlaylistEntry, by offset: Int) -> Bool {
        guard let index = displayedPlaylistEntryIndex(for: item) else { return false }
        let destination = index + offset
        return destination >= 0 && destination < displayedPlaylistEntries.count
    }

    private func presentCustomEntryEditor(targetPlaylistID: PersistentIdentifier?, playlistName: String?) {
        presentedCustomEntryEditor = CustomPlaylistEntryEditor(
            title: playlistName.map { "Add Entry to \($0)" } ?? "Add Entry",
            playlistID: targetPlaylistID
        )
    }

    private func syncSelection() {
        if let currentID = ttsQueue.currentPlaylistID(),
           playlists.contains(where: { $0.persistentModelID == currentID }) {
            focusedPlaylistID = currentID
            selectedPlaylistID = currentID
        } else {
            let firstPlaylistID = playlists.first?.persistentModelID
            focusedPlaylistID = firstPlaylistID
            selectedPlaylistID = firstPlaylistID
        }
    }

    private var playlistSelectionBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { selectedPlaylistID },
            set: { newValue in
                selectedPlaylistID = newValue
                ttsQueue.selectPlaylist(id: newValue)
            }
        )
    }

    private var displayedPlaylist: TTSPlaylist? {
        if let selectedPlaylistID,
           let playlist = playlists.first(where: { $0.persistentModelID == selectedPlaylistID }) {
            return playlist
        }

        if let focusedPlaylistID,
           let playlist = playlists.first(where: { $0.persistentModelID == focusedPlaylistID }) {
            return playlist
        }
        return ttsQueue.playlist(with: ttsQueue.currentPlaylistID())
    }

    private var displayedPlaylistEntries: [TTSPlaylistEntry] {
        displayedPlaylist?.orderedEntries ?? []
    }

    private var cardBackground: some ShapeStyle {
        .regularMaterial
    }

    private var detailBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .controlBackgroundColor)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            let count = max(1, displayedPlaylistEntries.count)
            let progressIndex = min(ttsQueue.currentIndex + 1, count)

            RoundedRectangle(cornerRadius: 99, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 99, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * (CGFloat(progressIndex) / CGFloat(count)))
                }
        }
        .frame(height: 6)
    }

    private var repeatModeIcon: String {
        switch repeatMode {
        case "none": return "repeat"
        case "one": return "repeat.1"
        case "all": return "repeat.circle"
        default: return "repeat"
        }
    }

    private var repeatModeTitle: String {
        switch repeatMode {
        case "none": return "Repeat Off"
        case "one": return "Repeat One"
        case "all": return "Repeat All"
        default: return "Repeat"
        }
    }

    private var emptySidebarState: some View {
        Text("No playlists yet.")
            .foregroundStyle(.secondary)
            .padding(.vertical, AppDefaults.paddingLarge)
    }

    private var emptyDetailState: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
            Text("No active playlist")
                .font(.title3.weight(.semibold))
            Text("Create a playlist or select one from the Playlists page.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .padding(AppDefaults.paddingLarge)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous))
    }

    private var emptyEntriesState: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
            Text("No entries")
                .font(.headline)
            Text("Add messages from a conversation to populate this playlist.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppDefaults.paddingLarge)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium, style: .continuous))
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
}

private enum TTSTab: Hashable {
    case player
    case playlists
}

private struct PlaylistEditor: Identifiable {
    let id = UUID()
    let title: String
    let name: String
    let playlistID: PersistentIdentifier?
}

private struct CustomPlaylistEntryEditor: Identifiable {
    let id = UUID()
    let title: String
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
        VStack(alignment: .leading, spacing: AppDefaults.paddingLarge) {
            Text(title)
                .font(.title3.weight(.semibold))

            TextField("Playlist name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            HStack(spacing: AppDefaults.paddingSmall) {
                Spacer(minLength: 0)

                Button("Cancel") {
                    onCancel()
                    dismiss()
                }

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(AppDefaults.paddingLarge)
        .frame(minWidth: 360, minHeight: 180)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous))
    }

    private var canSave: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        onSave(draftName)
        dismiss()
    }
}

private struct CustomPlaylistEntryEditorSheet: View {
    let title: String
    let onCancel: () -> Void
    let onSave: (String, TTSPlaylistRole) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftText: String = ""
    @State private var draftRole: TTSPlaylistRole = .user

    var body: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingLarge) {
            Text(title)
                .font(.title3.weight(.semibold))

            TextEditorWithPlaceholder(
                text: $draftText,
                placeholder: "Enter the entry text"
            )
            .frame(minHeight: 180)

            Picker("", selection: $draftRole) {
                ForEach(TTSPlaylistRole.allCases) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: AppDefaults.paddingSmall) {
                Spacer(minLength: 0)

                Button("Cancel") {
                    onCancel()
                    dismiss()
                }

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(AppDefaults.paddingLarge)
        .frame(minWidth: 460, minHeight: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous))
    }

    private var canSave: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        onSave(draftText, draftRole)
        dismiss()
    }
}

private struct TextEditorWithPlaceholder: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(4)

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .allowsHitTesting(false)
            }
        }
    }
}

#Preview{
    TTSControlView()
        .bootstrapped(with: .preview())
}
