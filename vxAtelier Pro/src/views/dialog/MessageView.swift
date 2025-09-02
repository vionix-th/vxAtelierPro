import AVFoundation
import SwiftData
import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#endif

struct MessageView: View {
    @Environment(QueryManager.self) private var queryManager
    
    let messageID: PersistentIdentifier?
    let turnID: PersistentIdentifier
    let conversationID: PersistentIdentifier
    let isSelected: Bool
    let isSelecting: Bool
    let onSelect: () -> Void
    let onTap: () -> Void
    let onAction: (MessageAction) -> Void
    let isBookmarked: Bool
    var streamingContent: String? = nil

    @AppStorage("DisableAvatar") private var disableAvatar: Bool = false
    @AppStorage("DefaultAvatarSize") private var defaultAvatarSize: Double = 40
    @AppStorage("BubbleFontSize") private var bubbleFontSize: Double = AppDefaults.fontSizeMedium
    @AppStorage("ShowToolCallChips") private var showToolCallChips: Bool = true
    @AppStorage("MarkdownStreamFinalizeOnly") private var markdownStreamFinalizeOnly: Bool = false
    @State private var toolsExpanded: Bool = false
    @State private var didAutoExpand: Bool = false
    @State private var expandedResultIds: Set<PersistentIdentifier> = []

    private var avatar: some View {
        let dialog = queryManager.allConversations.first(where: { $0.id == conversationID })
        
        let imageData: Data? = {
            if let data = dialog?.options.avatarImageData {
                return data
            } else if let data = dialog?.project?.defaultOptions.avatarImageData {
                return data
            } else if let data = UserDefaults.standard.data(forKey: "defaultAvatar") {
                return data
            }
            return nil
        }()
        return AvatarView(imageData: imageData, size: defaultAvatarSize, strokeWidth: nil)
            .padding(.top, AppDefaults.paddingMedium)
    }

    var body: some View {
        let message: MessageItem?
        let turn: ConversationTurn?
        let dialog = queryManager.allConversations.first(where: { $0.id == conversationID })
        let isStreamingPlaceholder: Bool
        
        // Resolve models from IDs
        if let messageID = messageID {
            // Normal message with ID
            // Find the turn in the dialog's turns collection
            turn = dialog?.turns.first(where: { $0.id == turnID })
            message = turn?.userMessage.id == messageID ? turn?.userMessage : 
                     turn?.events.first(where: { $0.message.id == messageID })?.message
            isStreamingPlaceholder = false
        } else if let streamText = streamingContent {
            // Streaming content - create temp message
            turn = dialog?.turns.first(where: { $0.id == turnID })
            message = MessageItem(
                role: "assistant",
                content: ContentItem(streamText),
                timestamp: Date(),
                toolCallId: nil,
                toolCallsData: nil
            )
            isStreamingPlaceholder = true
        } else {
            // No message available
            turn = nil
            message = nil
            isStreamingPlaceholder = false
        }
        
        return HStack {
            if message == nil || dialog == nil {
                // Error state - message or conversation not found
                Text("Message not available")
                    .foregroundColor(.secondary)
                    .italic()
            } else if let message = message, let dialog = dialog {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle" : "circle")
                        .onTapGesture { onSelect() }
                }
                
                if message.role == "user" {
                    Spacer()
                    bubbleContent(message: message, dialog: dialog, isStreaming: isStreamingPlaceholder)
                } else if message.role == "assistant" {
                    // If tool chips are disabled and the assistant text is empty (non-streaming), omit the bubble entirely
                    let assistantTextIsEmpty = message.content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if showToolCallChips || isStreamingPlaceholder || !assistantTextIsEmpty {
                        HStack {
                            if !disableAvatar {
                                VStack {
                                    avatar
                                    Spacer()
                                }
                            }
                            bubbleContent(message: message, dialog: dialog, isStreaming: isStreamingPlaceholder)
                        }
                        Spacer()
                    }
                } else if message.role == "system" || message.role == "developer" {
                    Text(message.content.text)
                        .font(.footnote)
                        .italic()
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .opacity(isSelecting ? (isSelected ? 1.0 : 0.5) : 1.0)
        .contextMenu { 
            if messageID != nil { // Only show context menu for real messages, not streaming content
                bubbleAction(labelVisible: true) 
            }
        }
    }

    func bubbleContent(message: MessageItem, dialog: ConversationItem, isStreaming: Bool = false) -> some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                // Main content bubble
                let assistantTextIsEmpty = message.role == "assistant" && message.content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let showMainBubble = !(message.role == "assistant" && !isStreaming && assistantTextIsEmpty)
                if showMainBubble {
                    Group {
                        // Show a spinner for blank streaming placeholders
                        if isStreaming && message.content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if dialog.options.isMarkdownEnabled && !(isStreaming && markdownStreamFinalizeOnly) {
                            MarkdownUIRenderer(markdown: message.content.text)
                        } else {
                            Text(message.content.text)
                                .font(.system(size: bubbleFontSize))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(AppDefaults.paddingMedium)
                    .background(
                        message.role == "user"
                            ? Color.secondary.opacity(0.2) : Color.blue.opacity(0.2)
                    )
                    .cornerRadius(AppDefaults.cornerRadiusMedium)
                }

                // Tool call chips under assistant message
                if message.role == "assistant",
                   let toolCalls = message.getToolCalls(),
                   !toolCalls.isEmpty,
                   showToolCallChips {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(toolCalls, id: \.id) { toolCall in
                            HStack(spacing: 6) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(toolCall.name)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(toolCall.arguments)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(6)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }
                }

                // Tool results section (gated by ShowToolCallChips)
                if message.role == "assistant" && showToolCallChips {
                    let turn = dialog.turns.first(where: { $0.id == turnID })
                    let toolResults = turn?.events.filter { $0.type == .toolResult && $0.message.toolCallId != nil } ?? []
                    let calls = message.getToolCalls() ?? []
                    let callById: [String: AIToolCall] = {
                        var dict: [String: AIToolCall] = [:]
                        for c in calls {
                            dict[c.id] = c
                        }
                        return dict
                    }()
                    let resultEvents = toolResults.filter { ev in
                        if let cid = ev.message.toolCallId { return callById[cid] != nil } else { return false }
                    }.sorted { $0.timestamp < $1.timestamp }
                    let resultsCountById: [String: Int] = {
                        Dictionary(grouping: resultEvents, by: { $0.message.toolCallId! }).mapValues { $0.count }
                    }()
                    let totalResults = resultEvents.count
                    let pendingCount = calls.reduce(0) { partial, call in
                        let id = call.id
                        return partial + ((resultsCountById[id] ?? 0) == 0 ? 1 : 0)
                    }

                    // Spinner if assistant text is blank and there are pending tool call results
                    if assistantTextIsEmpty && pendingCount > 0 {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for tool results…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, AppDefaults.paddingMedium)
                    }

                    if !calls.isEmpty || pendingCount > 0 || totalResults > 0 {
                        DisclosureGroup(isExpanded: $toolsExpanded) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(resultEvents, id: \.id) { ev in
                                    let rid = ev.id
                                    let cid = ev.message.toolCallId ?? ""
                                    let toolName = (callById[cid]?.name) ?? "Tool"
                                    let isLong = ev.message.content.text.count > 600 || ev.message.content.text.components(separatedBy: "\n").count > 12
                                    let expanded = expandedResultIds.contains(rid)
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "wrench.and.screwdriver")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(toolName)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            if isLong {
                                                Button {
                                                    if expanded { expandedResultIds.remove(rid) } else { expandedResultIds.insert(rid) }
                                                } label: {
                                                    Text(expanded ? "Show Less" : "Show More")
                                                        .font(.caption2)
                                                }
                                                .buttonStyle(.borderless)
                                            }
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(ev.message.content.text)
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .textSelection(.enabled)
                                                .lineLimit(expanded ? nil : (isLong ? 12 : nil))
                                            HStack(spacing: 8) {
                                                Spacer()
                                                Button {
                                                    copyToClipboard(ev.message.content.text)
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
                            .padding(.horizontal, 2)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "rectangle.stack")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Tool Results (\(totalResults))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if pendingCount > 0 {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                            }
                            .padding(.horizontal, AppDefaults.paddingMedium)
                        }
                        .onChange(of: totalResults) { _, newValue in
                            if newValue > 0 && !didAutoExpand {
                                // Auto-expand once when first results arrive
                                didAutoExpand = true
                                toolsExpanded = true
                            }
                        }
                    }
                }
            }
            if isBookmarked {
                Image(systemName: "bookmark")
                    .offset(x: 6, y: 4)
            }
        }
    }

    // Clipboard helper
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    private func bubbleAction(labelVisible: Bool) -> some View {
        Group {
            if isBookmarked {
                Button {
                    onAction(.removeBookmark)
                } label: {
                    MenuItemStyle.label("Remove Bookmark", systemImage: "bookmark.slash")
                }
                .help("Remove the bookmark for this message")
            } else {
                Button {
                    onAction(.bookmark)
                } label: {
                    MenuItemStyle.label("Add Bookmark", systemImage: "bookmark")
                }
                .help("Create a bookmark for this message")
            }
            Divider()
            Button {
                onAction(.fork)
            } label: {
                MenuItemStyle.label("Fork from Here", systemImage: "arrow.branch")
            }
            .help("Create a new dialog forked from all turns preceding the turn containing this message")
            Button {
                onAction(.addToPlaylist)
            } label: {
                MenuItemStyle.label("Add to Playlist", systemImage: "speaker.wave.2.bubble")
            }
            .help("Add this message to the text-to-speech queue")
            Divider()
            Button {
                onAction(.select)
            } label: {
                MenuItemStyle.label("Select Message", systemImage: "checkmark.circle")
            }
            .help("Enter selection mode and select this message")
            Divider()
            Button {
                onAction(.copyText)
            } label: {
                MenuItemStyle.label("Copy as Text", systemImage: "doc.on.doc")
            }
            .help("Copy message content as plain text")
            Button {
                onAction(.copyJSON)
            } label: {
                MenuItemStyle.label("Copy as JSON", systemImage: "doc.on.clipboard")
            }
            .help("Copy message content as JSON")
            Divider()
            Button(role: .destructive) {
                onAction(.delete)
            } label: {
                MenuItemStyle.label("Delete Message", systemImage: "trash")
            }
            .help("Delete this message")
        }
    }
}
