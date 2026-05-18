import SwiftData
import SwiftUI

struct TTSControlTabSelector: View {
    @Binding var activeTab: TTSTab

    var body: some View {
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
}

struct TTSControlPlaylistActionsBar: View {
    let playlists: [TTSPlaylist]
    let selectedPlaylistID: Binding<PersistentIdentifier?>
    let isPlaylistTabActive: Bool
    let isExportingPlaylistAudio: Bool
    let onNewPlaylist: () -> Void
    let onAddEntry: () -> Void
    let onImportPlaylist: () -> Void
    let onExportAudio: () -> Void
    let onExportJSON: () -> Void

    var body: some View {
        VStack(spacing: AppDefaults.paddingSmall) {
            Divider()
            HStack(spacing: AppDefaults.paddingMedium) {
                if playlists.isEmpty {
                    Text("No playlists")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("", selection: selectedPlaylistID) {
                        ForEach(playlists) { playlist in
                            Text(playlist.name)
                                .tag(Optional(playlist.persistentModelID))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Button(action: onNewPlaylist) {
                    Label("New Playlist", systemImage: "plus")
                }

                Button(action: onAddEntry) {
                    Label("Add Entry", systemImage: "text.badge.plus")
                }

                if isPlaylistTabActive {
                    Button(action: onImportPlaylist) {
                        Label("Import Playlist", systemImage: "square.and.arrow.down")
                    }

                    Menu {
                        Button(action: onExportAudio) {
                            Label("Export Audio", systemImage: "waveform")
                        }

                        Button(action: onExportJSON) {
                            Label("Export JSON", systemImage: "doc")
                        }
                    } label: {
                        Label("Export Playlist", systemImage: "square.and.arrow.up")
                    }
                    .disabled(playlists.isEmpty || isExportingPlaylistAudio)
                }

                Spacer(minLength: 0)

                Text("\(playlists.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppDefaults.paddingLarge)
            .padding(.vertical, AppDefaults.paddingSmall)
        }
        .padding(.top, AppDefaults.paddingSmall)
    }
}

struct TTSControlPlayerCard: View {
    @Binding var repeatMode: String

    let progressFraction: Double
    let isPlaying: Bool
    let canPlay: Bool
    let previousDisabled: Bool
    let nextDisabled: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: AppDefaults.paddingMedium) {
            HStack {
                Text("Playback")
                    .font(.headline)

                Spacer(minLength: 0)
            }

            progressBar

            HStack(spacing: AppDefaults.paddingMedium) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.secondary)
                .disabled(previousDisabled)

                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!canPlay)

                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.secondary)
                .disabled(nextDisabled)

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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous))
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 99, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 99, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * progressFraction)
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
}

struct TTSControlPlaylistEntriesCard: View {
    let playlist: TTSPlaylist
    let entries: [TTSPlaylistEntry]
    let currentItemID: PersistentIdentifier?
    let indexForEntry: (TTSPlaylistEntry) -> Int?
    let onSelectEntry: (Int) -> Void
    let onMoveUp: (TTSPlaylistEntry) -> Void
    let onMoveDown: (TTSPlaylistEntry) -> Void
    let onEditEntry: (TTSPlaylistEntry) -> Void
    let onDeleteEntry: (TTSPlaylistEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
            HStack {
                Text(playlist.name)
                    .font(.headline)

                Spacer(minLength: 0)
            }

            if entries.isEmpty {
                TTSControlEmptyEntriesState()
            } else {
                LazyVStack(spacing: AppDefaults.paddingSmall) {
                    ForEach(entries) { item in
                        TTSControlPlaylistEntryRow(
                            item: item,
                            index: indexForEntry(item),
                            isCurrent: item.persistentModelID == currentItemID,
                            canMoveUp: canMove(item, by: -1),
                            canMoveDown: canMove(item, by: 1),
                            onSelect: {
                                if let index = indexForEntry(item) {
                                    onSelectEntry(index)
                                }
                            },
                            onMoveUp: { onMoveUp(item) },
                            onMoveDown: { onMoveDown(item) },
                            onEdit: { onEditEntry(item) },
                            onDelete: { onDeleteEntry(item) }
                        )
                    }
                }
            }
        }
        .padding(AppDefaults.paddingLarge)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous))
    }

    private func canMove(_ item: TTSPlaylistEntry, by offset: Int) -> Bool {
        guard let index = indexForEntry(item) else { return false }
        let destination = index + offset
        return destination >= 0 && destination < entries.count
    }
}

struct TTSControlPlaylistRow: View {
    let playlist: TTSPlaylist
    let isSelected: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onAddEntry: () -> Void

    var body: some View {
        HStack(spacing: AppDefaults.paddingMedium) {
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

            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .help("Play playlist")
        }
        .padding(.vertical, AppDefaults.paddingSmall)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(action: onPlay) {
                Label("Play", systemImage: "play.circle")
            }

            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }

            Divider()

            Button(action: onAddEntry) {
                Label("Add Entry", systemImage: "text.badge.plus")
            }
        }
    }
}

struct TTSControlPlaylistEntryRow: View {
    let item: TTSPlaylistEntry
    let index: Int?
    let isCurrent: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onSelect: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: AppDefaults.paddingMedium) {
            VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                HStack(spacing: AppDefaults.paddingSmall) {
                    if let index {
                        TTSControlEntryIndexBadge(number: index + 1)
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
            }

            Spacer(minLength: AppDefaults.paddingMedium)

            HStack(spacing: AppDefaults.paddingSmall) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                .help("Move up")

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                .help("Move down")
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
        .onTapGesture(perform: onSelect)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.accentColor)

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }

            Button(action: onMoveUp) {
                Label("Move Up", systemImage: "chevron.up")
            }
            .disabled(!canMoveUp)

            Button(action: onMoveDown) {
                Label("Move Down", systemImage: "chevron.down")
            }
            .disabled(!canMoveDown)

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct TTSControlEntryIndexBadge: View {
    let number: Int

    var body: some View {
        Text(String(number))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium, style: .continuous))
    }
}

struct TTSControlEmptySidebarState: View {
    var body: some View {
        Text("No playlists yet.")
            .foregroundStyle(.secondary)
            .padding(.vertical, AppDefaults.paddingLarge)
    }
}

struct TTSControlEmptyDetailState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
            Text("No active playlist")
                .font(.title3.weight(.semibold))
            Text("Create a playlist or select one from the Playlists page.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .padding(AppDefaults.paddingLarge)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous))
    }
}

struct TTSControlEmptyEntriesState: View {
    var body: some View {
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
}

struct TTSControlExportOverlay: View {
    let playlistName: String?
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: AppDefaults.paddingLarge) {
                ProgressView()
                    .controlSize(.large)

                VStack(spacing: AppDefaults.paddingSmall) {
                    Text("Exporting playlist audio")
                        .font(.headline)

                    Text(playlistName.map { "Rendering \($0) to audio." } ?? "Rendering playlist to audio.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Cancel Export", action: onCancel)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: 360)
            .padding(AppDefaults.paddingLarge)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous))
            .shadow(radius: 18)
        }
        .transition(.opacity)
    }
}
