import SwiftData
import SwiftUI

struct StatusBarInline: View {
    let conversationID: PersistentIdentifier?
    let logMessage: String
    let logType: LoggingService.LogType
    @Binding var isStatusBarFilterPopoverOpen: Bool
    @Binding var statusBarLogTypeFilters: Set<LoggingService.LogType>
    let onClearFilters: () -> Void
    let onRequestLogHistory: () -> Void
    let onRequestOptions: (PersistentIdentifier) -> Void
    let onRequestModelSelection: (PersistentIdentifier) -> Void
    let onToggleStreaming: (PersistentIdentifier, Bool) -> Void
    let onRequestTTS: () -> Void

    var body: some View {
        HStack(spacing: AppDefaults.paddingSmall) {
            StatusBarLogStrip(
                message: logMessage,
                logType: logType,
                isStatusBarFilterPopoverOpen: $isStatusBarFilterPopoverOpen,
                statusBarLogTypeFilters: $statusBarLogTypeFilters,
                onClearFilters: onClearFilters,
                onRequestLogHistory: onRequestLogHistory
            )
            .padding(.leading, AppDefaults.paddingSmall)

            Spacer(minLength: 0)

            StatusBarInfoStrip(
                conversationID: conversationID,
                allowsStreamingToggle: true,
                dense: false,
                onRequestOptions: conversationID.map { conversationID in { onRequestOptions(conversationID) } },
                onRequestModelSelection: conversationID.map { conversationID in { onRequestModelSelection(conversationID) } },
                onToggleStreaming: conversationID.map { conversationID in { enabled in onToggleStreaming(conversationID, enabled) } },
                onRequestTTS: onRequestTTS
            )
            .padding(.trailing, AppDefaults.paddingMedium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
    }
}

struct StatusBarStacked: View {
    let conversationID: PersistentIdentifier?
    let logMessage: String
    let logType: LoggingService.LogType
    @Binding var isStatusBarFilterPopoverOpen: Bool
    @Binding var statusBarLogTypeFilters: Set<LoggingService.LogType>
    let onClearFilters: () -> Void
    let onRequestLogHistory: () -> Void
    let onRequestOptions: (PersistentIdentifier) -> Void
    let onRequestModelSelection: (PersistentIdentifier) -> Void
    let onToggleStreaming: (PersistentIdentifier, Bool) -> Void
    let onRequestTTS: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                StatusBarInfoStrip(
                    conversationID: conversationID,
                    allowsStreamingToggle: false,
                    dense: true,
                    onRequestOptions: conversationID.map { conversationID in { onRequestOptions(conversationID) } },
                    onRequestModelSelection: conversationID.map { conversationID in { onRequestModelSelection(conversationID) } },
                    onToggleStreaming: conversationID.map { conversationID in { enabled in onToggleStreaming(conversationID, enabled) } },
                    onRequestTTS: onRequestTTS
                )
            }

            HStack {
                StatusBarLogStrip(
                    message: logMessage,
                    logType: logType,
                    isStatusBarFilterPopoverOpen: $isStatusBarFilterPopoverOpen,
                    statusBarLogTypeFilters: $statusBarLogTypeFilters,
                    onClearFilters: onClearFilters,
                    onRequestLogHistory: onRequestLogHistory
                )
                
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusBarInfoStrip: View {
    @Environment(TTSQueue.self) private var ttsQueue
    @AppStorage(AppSettings.Keys.showStatusBarTTSStrip) private var showStatusBarTTSStrip: Bool = AppDefaults.showStatusBarTTSStrip

    let conversationID: PersistentIdentifier?
    let allowsStreamingToggle: Bool
    let dense: Bool
    let onRequestOptions: (() -> Void)?
    let onRequestModelSelection: (() -> Void)?
    let onToggleStreaming: ((Bool) -> Void)?
    let onRequestTTS: () -> Void

    var body: some View {
        if showStatusBarTTSStrip || conversationID != nil {
        HStack(spacing: AppDefaults.paddingSmall) {
            if showStatusBarTTSStrip {
                StatusBarTTSStrip(
                    isPlaying: ttsQueue.isPlaying,
                    canTogglePlayback: ttsQueue.currentPlaylistHasEntries(),
                    onTogglePlayback: togglePlayback,
                    onRequestTTS: onRequestTTS,
                    dense: dense
                )
            }

            if let conversationID {
                StatusBarConversationInfoRow(
                    conversationID: conversationID,
                    allowsStreamingToggle: allowsStreamingToggle,
                    dense: dense,
                    onRequestOptions: onRequestOptions ?? {},
                    onRequestModelSelection: onRequestModelSelection,
                    onToggleStreaming: onToggleStreaming
                )
            }
        }
        .padding(.horizontal, AppDefaults.paddingMedium)
        .padding(.vertical, AppDefaults.paddingSmall)
        }
    }

    private func togglePlayback() {
        guard ttsQueue.currentPlaylistHasEntries() else { return }
        if ttsQueue.isPlaying {
            ttsQueue.pause()
        } else {
            ttsQueue.resume()
        }
    }
}

private struct StatusBarTTSStrip: View {
    let isPlaying: Bool
    let canTogglePlayback: Bool
    let onTogglePlayback: () -> Void
    let onRequestTTS: () -> Void
    let dense: Bool

    private var statusLabel: String {
        isPlaying ? "TTS Playing" : "TTS Ready"
    }

    var body: some View {
        HStack(spacing: AppDefaults.paddingSmall) {
            Button(action: onTogglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.caption.weight(.semibold))
                    .frame(width: dense ? 20 : 22, height: dense ? 20 : 22)
                    .foregroundStyle(isPlaying ? .green : .primary)
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause TTS playback" : "Resume TTS playback")
            .disabled(!canTogglePlayback)

            Button(action: onRequestTTS) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .frame(width: dense ? 20 : 22, height: dense ? 20 : 22)
            }
            .buttonStyle(.plain)
            .help("Open TTS controls")
        }
        .padding(.horizontal, AppDefaults.paddingSmall)
        .padding(.vertical, AppDefaults.paddingSmall / 2)
    }
}

struct StatusBarLogStrip: View {
    let message: String
    let logType: LoggingService.LogType
    @Binding var isStatusBarFilterPopoverOpen: Bool
    @Binding var statusBarLogTypeFilters: Set<LoggingService.LogType>
    let onClearFilters: () -> Void
    let onRequestLogHistory: () -> Void

    var body: some View {
        HStack(spacing: AppDefaults.paddingSmall) {
            StatusBarFilterButton(isActive: !statusBarLogTypeFilters.isEmpty) {
                isStatusBarFilterPopoverOpen.toggle()
            }
            .popover(isPresented: $isStatusBarFilterPopoverOpen) {
                StatusBarFilterPopover(
                    title: "Status Bar Filters",
                    filters: $statusBarLogTypeFilters,
                    showNote: true,
                    onClear: onClearFilters
                )
            }

            Circle()
                .fill(logType.color)
                .frame(width: 6, height: 6)
                .help(logType.rawValue.capitalized)

            Text(message)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, AppDefaults.paddingSmall)
                .foregroundColor(.primary)
                .contentShape(Rectangle())
                .onTapGesture {
                    onRequestLogHistory()
                }
        }
        .padding(.leading, AppDefaults.paddingMedium)
    }
}

#Preview{
    AppShellView()
        .bootstrapped(with: .preview())
        .frame(width: 800, height:640)
}
