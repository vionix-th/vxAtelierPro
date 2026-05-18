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

            if let conversationID {
                Spacer(minLength: 0)

                StatusBarInfoStrip(
                    conversationID: conversationID,
                    allowsStreamingToggle: true,
                    dense: false,
                    onRequestOptions: { onRequestOptions(conversationID) },
                    onRequestModelSelection: { onRequestModelSelection(conversationID) },
                    onToggleStreaming: { onToggleStreaming(conversationID, $0) }
                )
            }
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

    var body: some View {
        VStack(spacing: 0) {
            if let conversationID {
                HStack {
                    Spacer()
                    
                    StatusBarInfoStrip(
                        conversationID: conversationID,
                        allowsStreamingToggle: false,
                        dense: true,
                        onRequestOptions: { onRequestOptions(conversationID) },
                        onRequestModelSelection: { onRequestModelSelection(conversationID) },
                        onToggleStreaming: { onToggleStreaming(conversationID, $0) }
                    )
                }
            }

            HStack{
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
    let conversationID: PersistentIdentifier
    let allowsStreamingToggle: Bool
    let dense: Bool
    let onRequestOptions: () -> Void
    let onRequestModelSelection: (() -> Void)?
    let onToggleStreaming: ((Bool) -> Void)?

    var body: some View {
        StatusBarConversationInfoRow(
            conversationID: conversationID,
            allowsStreamingToggle: allowsStreamingToggle,
            dense: dense,
            onRequestOptions: onRequestOptions,
            onRequestModelSelection: onRequestModelSelection,
            onToggleStreaming: onToggleStreaming
        )
        .padding(.horizontal, AppDefaults.paddingMedium)
        .padding(.vertical, AppDefaults.paddingSmall)
        .background(Color.secondary.opacity(AppDefaults.sectionBackgroundOpacity / 2))
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
