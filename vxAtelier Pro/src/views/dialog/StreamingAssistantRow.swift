import Foundation
import SwiftData
import SwiftUI

struct StreamingAssistantRow: View {
    let conversationID: PersistentIdentifier
    let presentation: ConversationStreamPresentation
    let style: ConversationPresentationStyle
    let draftStore: ConversationDraftStore
    let onContentPublished: () -> Void

    @AppStorage(AppSettings.Keys.disableAvatar) private var disableAvatar = false
    @AppStorage(AppSettings.Keys.defaultAvatarSize) private var defaultAvatarSize = 40.0
    @AppStorage(AppSettings.Keys.defaultAvatarData) private var defaultAvatarData: Data?
    @AppStorage(AppSettings.Keys.bubbleFontSize) private var bubbleFontSize = AppDefaults.fontSizeMedium
    @AppStorage(AppSettings.Keys.showToolCallChips) private var showToolCallChips = true

    var body: some View {
        Group {
            if presentation.turnID != nil, shouldRender {
                HStack(alignment: .top) {
                    if !disableAvatar {
                        AvatarView(
                            imageData: resolvedAvatarImageData,
                            size: defaultAvatarSize,
                            strokeWidth: nil
                        )
                        .padding(.top, AppDefaults.paddingMedium)
                    }
                    streamingContent
                    Spacer()
                }
                .padding(.horizontal, AppDefaults.paddingSmall)
            }
        }
        .onChange(of: draftStore.revision) { _, _ in
            onContentPublished()
        }
    }

    private var draft: ConversationDraft {
        draftStore.draft(for: conversationID)
    }

    private var runStatus: ProviderRunStatus {
        if draft.isActive || draft.errorMessage != nil {
            return draft.runStatus
        }
        return presentation.latestRun?.status ?? draft.runStatus
    }

    private var errorMessage: String? {
        draft.errorMessage ?? presentation.latestRun?.errorMessage
    }

    private var shouldRender: Bool {
        draft.isActive || runStatus == .failed || runStatus == .cancelled
    }

    private var isTerminalError: Bool {
        runStatus == .failed || runStatus == .cancelled
    }

    private var resolvedAvatarImageData: Data? {
        style.avatarImageData ?? defaultAvatarData
    }

    private var streamingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if isTerminalError, let errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                    }
                } else if draft.text.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(draft.text)
                        .font(.system(size: bubbleFontSize))
                        .textSelection(.enabled)
                }
            }
            .padding(AppDefaults.paddingMedium)
            .background(isTerminalError ? Color.red.opacity(0.12) : Color.blue.opacity(0.2))
            .cornerRadius(AppDefaults.cornerRadiusMedium)

            if showToolCallChips, !draft.toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(draft.toolCalls.sorted(by: { $0.index < $1.index })) { call in
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
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
}
