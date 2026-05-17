import SwiftData
import SwiftUI

struct StatusBar: View {
    @ObservedObject private var loggingService = LoggingService.shared
    @Environment(AppSceneModel.self) private var sceneModel
    @Environment(QueryManager.self) private var queryManager
    @Environment(NavigationRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppSettings.Keys.statusBarLayoutStyle) private var statusBarLayoutStyleRaw: String = AppDefaults.statusBarLayoutStyle
    @State private var isStatusBarFilterPopoverOpen: Bool = false
    @State private var popupLogTypeFilters: Set<LoggingService.LogType> = []
    @State private var statusBarLogTypeFilters: Set<LoggingService.LogType> = []
    @State private var displayedMessage: String = ""
    private let messageAnimation: Animation = .easeInOut(duration: 0.18)

    private let popupFilterKey = AppSettings.Keys.popupLogTypeFilters
    private let statusBarFilterKey = AppSettings.Keys.statusBarLogTypeFilters

    private var resolvedLayoutStyle: StatusBarLayoutStyle {
        StatusBarLayoutStyle(rawValue: statusBarLayoutStyleRaw) ?? .automatic
    }

    private var isStackedLayout: Bool {
        switch resolvedLayoutStyle {
        case .automatic:
            return horizontalSizeClass == .compact
        case .singleRow:
            return false
        case .twoRows:
            return true
        }
    }

    private var currentConversationID: PersistentIdentifier? {
        sceneModel.focusedConversationID ?? router.activeConversationID
    }

    private func filteredMessages(with filters: Set<LoggingService.LogType>) -> [LogEntry] {
        if filters.isEmpty {
            return loggingService.messageHistory
        }
        return loggingService.messageHistory.filter { filters.contains($0.type) }
    }

    private var latestFilteredMessage: String {
        if statusBarLogTypeFilters.isEmpty {
            return loggingService.latestMessage
        }
        return filteredMessages(with: statusBarLogTypeFilters).last?.message ?? ""
    }

    private var latestFilteredLogType: LoggingService.LogType {
        if statusBarLogTypeFilters.isEmpty {
            return loggingService.lastLogType
        }
        return filteredMessages(with: statusBarLogTypeFilters).last?.type ?? .info
    }

    private func updateDisplayedMessage(animated: Bool = true) {
        let next = latestFilteredMessage
        guard next != displayedMessage else { return }
        if animated {
            withAnimation(messageAnimation) {
                displayedMessage = next
            }
        } else {
            displayedMessage = next
        }
    }

    private func saveFiltersToUserDefaults() {
        let popupFilterStrings: [String] = Array(popupLogTypeFilters).map { $0.rawValue }
        let statusBarFilterStrings: [String] = Array(statusBarLogTypeFilters).map { $0.rawValue }

        vxAtelierPro.log.debug("Saving popup filters: \(popupFilterStrings)")
        vxAtelierPro.log.debug("Saving status bar filters: \(statusBarFilterStrings)")

        UserDefaults.standard.set(popupFilterStrings, forKey: popupFilterKey)
        UserDefaults.standard.set(statusBarFilterStrings, forKey: statusBarFilterKey)
    }

    private func loadFiltersFromUserDefaults() {
        if let popupFilterStrings = UserDefaults.standard.stringArray(forKey: popupFilterKey) {
            popupLogTypeFilters = Set(popupFilterStrings.compactMap {
                LoggingService.LogType(rawValue: $0)
            })
            vxAtelierPro.log.debug("Loaded popup filters: \(popupFilterStrings), created set: \(popupLogTypeFilters.map { $0.rawValue })")
        }

        if let statusBarFilterStrings = UserDefaults.standard.stringArray(forKey: statusBarFilterKey) {
            statusBarLogTypeFilters = Set(statusBarFilterStrings.compactMap {
                LoggingService.LogType(rawValue: $0)
            })
            vxAtelierPro.log.debug("Loaded status bar filters: \(statusBarFilterStrings), created set: \(statusBarLogTypeFilters.map { $0.rawValue })")
        }
    }

    private func clearStatusBarFilters() {
        statusBarLogTypeFilters.removeAll()
        updateDisplayedMessage()
        saveFiltersToUserDefaults()
    }

    private func requestLogHistory() {
        sceneModel.requestLogHistory()
    }

    private func requestOptions(for conversationID: PersistentIdentifier) {
        sceneModel.requestOptions(for: conversationID)
    }

    private func requestModelSelection(for conversationID: PersistentIdentifier) {
        sceneModel.requestModelSelection(for: conversationID)
    }

    private func toggleStreaming(for conversationID: PersistentIdentifier, enabled: Bool) {
        guard let conversation = queryManager.conversation(with: conversationID) else { return }
        do {
            try queryManager.setStreamingEnabled(enabled, for: conversation)
        } catch {
            vxAtelierPro.log.error(
                "StatusBar: Failed to update streaming for conversation '\(conversation.title)': \(error.localizedDescription)"
            )
        }
    }

    var body: some View {
        Group {
            if isStackedLayout {
                StatusBarStacked(
                    conversationID: currentConversationID,
                    logMessage: displayedMessage,
                    logType: latestFilteredLogType,
                    isStatusBarFilterPopoverOpen: $isStatusBarFilterPopoverOpen,
                    statusBarLogTypeFilters: $statusBarLogTypeFilters,
                    onClearFilters: clearStatusBarFilters,
                    onRequestLogHistory: requestLogHistory,
                    onRequestOptions: requestOptions(for:),
                    onRequestModelSelection: requestModelSelection(for:),
                    onToggleStreaming: toggleStreaming(for:enabled:)
                )
            } else {
                StatusBarInline(
                    conversationID: currentConversationID,
                    logMessage: displayedMessage,
                    logType: latestFilteredLogType,
                    isStatusBarFilterPopoverOpen: $isStatusBarFilterPopoverOpen,
                    statusBarLogTypeFilters: $statusBarLogTypeFilters,
                    onClearFilters: clearStatusBarFilters,
                    onRequestLogHistory: requestLogHistory,
                    onRequestOptions: requestOptions(for:),
                    onRequestModelSelection: requestModelSelection(for:),
                    onToggleStreaming: toggleStreaming(for:enabled:)
                )
            }
        }
        .onChange(of: loggingService.messageHistory.count) { _, _ in
            updateDisplayedMessage()
        }
        .onChange(of: statusBarLogTypeFilters) { _, _ in
            saveFiltersToUserDefaults()
            updateDisplayedMessage()
        }
        .onChange(of: popupLogTypeFilters) { _, _ in
            saveFiltersToUserDefaults()
        }
        .onAppear {
            loadFiltersFromUserDefaults()
            updateDisplayedMessage(animated: false)
        }
    }
}
