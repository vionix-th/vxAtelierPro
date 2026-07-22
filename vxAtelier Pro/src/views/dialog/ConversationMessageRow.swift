import Foundation
import SwiftData
import SwiftUI

struct ConversationMessageRow: View {
    let snapshot: ConversationMessageSnapshot
    let style: ConversationPresentationStyle
    let playlists: [ConversationPlaylistSnapshot]
    let isSelecting: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onTap: () -> Void
    let onAction: (ConversationMessageAction) -> Void
    let onLayoutChange: () -> Void

    @AppStorage(AppSettings.Keys.disableAvatar) private var disableAvatar = false
    @AppStorage(AppSettings.Keys.defaultAvatarSize) private var defaultAvatarSize = 40.0
    @AppStorage(AppSettings.Keys.defaultAvatarData) private var defaultAvatarData: Data?
    @AppStorage(AppSettings.Keys.showToolCallChips) private var showToolCallChips = true

    var body: some View {
        HStack {
            if isSelecting {
                Button(action: onSelect) {
                    Image(systemName: isSelected ? "checkmark.circle" : "circle")
                }
                .buttonStyle(.plain)
            }

            switch snapshot.role {
            case .user:
                Spacer()
                messageContent
            case .assistant:
                if showToolCallChips || !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(alignment: .top) {
                        if !disableAvatar {
                            AvatarView(
                                imageData: resolvedAvatarImageData,
                                size: defaultAvatarSize,
                                strokeWidth: nil
                            )
                            .padding(.top, AppDefaults.paddingMedium)
                        }
                        messageContent
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, AppDefaults.paddingSmall)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .opacity(isSelecting ? (isSelected ? 1 : 0.5) : 1)
        .contextMenu {
            ConversationMessageActionMenu(
                isBookmarked: snapshot.isBookmarked,
                playlists: playlists,
                onAction: onAction
            )
        }
    }

    private var resolvedAvatarImageData: Data? {
        style.avatarImageData ?? defaultAvatarData
    }

    private var messageContent: some View {
        ConversationMessageBubble(
            snapshot: snapshot,
            rendersMarkdown: style.rendersMarkdown,
            showsTools: showToolCallChips,
            onLayoutChange: onLayoutChange,
            onCopyToolResult: { ExportUtils.copyToClipboard($0) }
        )
    }
}

private struct ConversationMessageBubble: View {
    let snapshot: ConversationMessageSnapshot
    let rendersMarkdown: Bool
    let showsTools: Bool
    let onLayoutChange: () -> Void
    let onCopyToolResult: (String) -> Void

    @AppStorage(AppSettings.Keys.bubbleFontSize) private var bubbleFontSize = AppDefaults.fontSizeMedium

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                if showsMainBubble {
                    Group {
                        if rendersMarkdown {
                            MarkdownUIRenderer(markdown: snapshot.text)
                        } else {
                            Text(snapshot.text)
                                .font(.system(size: bubbleFontSize))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(AppDefaults.paddingMedium)
                    .background(bubbleColor)
                    .cornerRadius(AppDefaults.cornerRadiusMedium)
                }

                if snapshot.role == .assistant, showsTools {
                    if !snapshot.toolCalls.isEmpty {
                        ConversationToolCallSummary(calls: snapshot.toolCalls)
                    }
                    ConversationToolResultsSection(
                        results: snapshot.toolResults,
                        pendingCount: snapshot.pendingToolResultCount,
                        showsWaitingIndicator: snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        onLayoutChange: onLayoutChange,
                        onCopyResult: onCopyToolResult
                    )
                }
            }

            if snapshot.isBookmarked {
                Image(systemName: "bookmark")
                    .offset(x: 6, y: 4)
            }
        }
    }

    private var showsMainBubble: Bool {
        snapshot.role != .assistant
            || !snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var bubbleColor: Color {
        snapshot.role == .user
            ? Color.secondary.opacity(0.2)
            : Color.blue.opacity(0.2)
    }
}

private struct ConversationToolCallSummary: View {
    let calls: [ConversationToolCallSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(calls) { call in
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(call.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(call.argumentsJSON)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(call.status)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            }
        }
    }
}

private struct ConversationToolResultsSection: View {
    let results: [ConversationToolResultSnapshot]
    let pendingCount: Int
    let showsWaitingIndicator: Bool
    let onLayoutChange: () -> Void
    let onCopyResult: (String) -> Void

    @State private var isExpanded = false
    @State private var expandedResultIDs = Set<PersistentIdentifier>()

    var body: some View {
        Group {
            if showsWaitingIndicator, pendingCount > 0 {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for tool results…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, AppDefaults.paddingMedium)
            }

            if pendingCount > 0 || !results.isEmpty {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(results) { result in
                            resultView(result)
                        }
                    }
                    .padding(.horizontal, 2)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.stack")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Tool Results (\(results.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if pendingCount > 0 {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, AppDefaults.paddingMedium)
                }
            }
        }
        .onChange(of: isExpanded) { _, _ in onLayoutChange() }
        .onChange(of: expandedResultIDs) { _, _ in onLayoutChange() }
    }

    private func resultView(_ result: ConversationToolResultSnapshot) -> some View {
        let expanded = expandedResultIDs.contains(result.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(result.toolName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if result.isLong {
                    Button {
                        if expanded {
                            expandedResultIDs.remove(result.id)
                        } else {
                            expandedResultIDs.insert(result.id)
                        }
                    } label: {
                        Text(expanded ? "Show Less" : "Show More")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(result.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(expanded ? nil : (result.isLong ? 12 : nil))
                HStack {
                    Spacer()
                    Button {
                        onCopyResult(result.text)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(6)
        }
        .padding(6)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(6)
    }
}

private struct ConversationMessageActionMenu: View {
    let isBookmarked: Bool
    let playlists: [ConversationPlaylistSnapshot]
    let onAction: (ConversationMessageAction) -> Void

    var body: some View {
        Group {
            Button {
                onAction(isBookmarked ? .removeBookmark : .bookmark)
            } label: {
                MenuItemStyle.label(
                    isBookmarked ? "Remove Bookmark" : "Add Bookmark",
                    systemImage: isBookmarked ? "bookmark.slash" : "bookmark"
                )
            }

            Divider()

            Button {
                onAction(.fork)
            } label: {
                MenuItemStyle.label("Fork from Here", systemImage: "arrow.branch")
            }

            Menu {
                Button {
                    onAction(.addToNewPlaylist)
                } label: {
                    MenuItemStyle.label("New Playlist", systemImage: "plus.square.on.square")
                }
                if !playlists.isEmpty {
                    Divider()
                    ForEach(playlists) { playlist in
                        Button {
                            onAction(.addToPlaylist(playlist.id))
                        } label: {
                            MenuItemStyle.label(playlist.name, systemImage: "music.note.list")
                        }
                    }
                }
            } label: {
                MenuItemStyle.label("Add to Playlist", systemImage: "speaker.wave.2.bubble")
            }

            Divider()

            Button {
                onAction(.select)
            } label: {
                MenuItemStyle.label("Select Message", systemImage: "checkmark.circle")
            }

            Divider()

            Button {
                onAction(.copyText)
            } label: {
                MenuItemStyle.label("Copy as Text", systemImage: "doc.on.doc")
            }
            Button {
                onAction(.copyJSON)
            } label: {
                MenuItemStyle.label("Copy as JSON", systemImage: "doc.on.clipboard")
            }

            Divider()

            Button(role: .destructive) {
                onAction(.delete)
            } label: {
                MenuItemStyle.label("Delete Message", systemImage: "trash")
            }
        }
    }
}
