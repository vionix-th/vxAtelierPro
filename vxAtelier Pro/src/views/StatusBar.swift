import SwiftData
import SwiftUI

// MARK: - Status Bar View
struct StatusBar: View {
    // MARK: - Properties
    @ObservedObject private var loggingService = LoggingService.shared
    @State private var isStatusBarFilterPopoverOpen: Bool = false
    @State private var popupLogTypeFilters: Set<LoggingService.LogType> = []
    @State private var statusBarLogTypeFilters: Set<LoggingService.LogType> = []
    @State private var displayedMessage: String = ""
    let onRequestLogHistory: () -> Void
    let onRequestModelSelection: (PersistentIdentifier) -> Void
    private let messageAnimation: Animation = .easeInOut(duration: 0.18)
    
    // Environment access
    @Environment(QueryManager.self) private var queryManager
    @Environment(NavigationRouter.self) private var router
    
    // UserDefaults keys
    private let popupFilterKey = AppSettings.Keys.popupLogTypeFilters
    private let statusBarFilterKey = AppSettings.Keys.statusBarLogTypeFilters

    // Computed property to determine if the view is in compact mode
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    // MARK: - Computed Properties
    // Filtered log messages based on supplied filters
    private func filteredMessages(with filters: Set<LoggingService.LogType>) -> [LogEntry] {
        if filters.isEmpty {
            return loggingService.messageHistory
        }
        return loggingService.messageHistory.filter { filters.contains($0.type) }
    }

    // Latest filtered message for status bar
    private var latestFilteredMessage: String {
        if statusBarLogTypeFilters.isEmpty {
            return loggingService.latestMessage
        }
        return filteredMessages(with: statusBarLogTypeFilters).last?.message ?? ""
    }

    // Latest log type that matches the status bar filters
    private var latestFilteredLogType: LoggingService.LogType {
        if statusBarLogTypeFilters.isEmpty {
            return loggingService.lastLogType
        }
        return filteredMessages(with: statusBarLogTypeFilters).last?.type ?? .info
    }

    private var activeConversation: ConversationItem? {
        guard let id = router.activeConversationID else { return nil }
        return queryManager.conversation(with: id)
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

    // MARK: - Initialization
    init(
        onRequestLogHistory: @escaping () -> Void,
        onRequestModelSelection: @escaping (PersistentIdentifier) -> Void
    ) {
        self.onRequestLogHistory = onRequestLogHistory
        self.onRequestModelSelection = onRequestModelSelection
    }

    // MARK: - Filter Persistence Methods
    
    /// Save the current filter settings to UserDefaults
    private func saveFiltersToUserDefaults() {
        // Convert Set<LoggingService.LogType> to array of strings
        let popupFilterStrings: [String]  = Array(popupLogTypeFilters).map { $0.rawValue }
        let statusBarFilterStrings: [String] = Array(statusBarLogTypeFilters).map { $0.rawValue }
        
        // Log what we're saving
        vxAtelierPro.log.debug("Saving popup filters: \(popupFilterStrings)")
        vxAtelierPro.log.debug("Saving status bar filters: \(statusBarFilterStrings)")
        
        // Simply store the string arrays directly - no JSON conversion needed
        UserDefaults.standard.set(popupFilterStrings, forKey: popupFilterKey)
        UserDefaults.standard.set(statusBarFilterStrings, forKey: statusBarFilterKey)
    }
    
    /// Load filter settings from UserDefaults
    private func loadFiltersFromUserDefaults() {
        // Load string arrays directly
        if let popupFilterStrings = UserDefaults.standard.stringArray(forKey: popupFilterKey) {
            // Convert string array to Set<LoggingService.LogType>            
            popupLogTypeFilters = Set(popupFilterStrings.compactMap { 
                LoggingService.LogType(rawValue: $0)
            })
            vxAtelierPro.log.debug("Loaded popup filters: \(popupFilterStrings), created set: \(popupLogTypeFilters.map { $0.rawValue })")
        }
        
        if let statusBarFilterStrings = UserDefaults.standard.stringArray(forKey: statusBarFilterKey) {
            // Convert string array to Set<LoggingService.LogType>
            statusBarLogTypeFilters = Set(statusBarFilterStrings.compactMap { 
                LoggingService.LogType(rawValue: $0)
            })
            vxAtelierPro.log.debug("Loaded status bar filters: \(statusBarFilterStrings), created set: \(statusBarLogTypeFilters.map { $0.rawValue })")
        }
    }

    // MARK: - View Body
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // Status bar filter button
                Button {
                    isStatusBarFilterPopoverOpen.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(statusBarLogTypeFilters.isEmpty ? .secondary : .blue)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                .help("Filter status bar messages")
                .popover(isPresented: $isStatusBarFilterPopoverOpen) {
                    LogFilterPopover(
                        title: "Status Bar Filters",
                        filters: $statusBarLogTypeFilters,
                        showNote: true,
                        onClear: {                        
                            statusBarLogTypeFilters.removeAll()
                            updateDisplayedMessage()
                            saveFiltersToUserDefaults()
                        }
                    )
                }

                // Log message display with animation
                Text(displayedMessage)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 2)
                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                    .onTapGesture {
                        onRequestLogHistory()
                    }
                
                if let conversation = activeConversation,
                   !isCompact {
                    HStack(spacing: 6) {
                        ConversationInfoHeader(
                            conversation: conversation,
                            isCompact: false,
                            queryManager: queryManager,
                            onRequestModelSelection: onRequestModelSelection
                        )
                            .layoutPriority(1)
                    }
                    .frame(minWidth: 200, idealWidth: 400, maxWidth: 500, alignment: .trailing)
                }
            }
            .frame(height: 32)
            .background(Color.secondary.opacity(0.1))
            
            if let conversation = activeConversation,
               isCompact {
                ConversationInfoHeader(
                    conversation: conversation,
                    isCompact: true,
                    queryManager: queryManager,
                    onRequestModelSelection: onRequestModelSelection
                )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.05))
            }
        }
        .onChange(of: loggingService.latestMessage) { _, _ in
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

// MARK: - Reusable Filter Button
struct FilterButton: View {
    let logType: LoggingService.LogType?
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let type = logType {
                    Image(systemName: type.systemImage)
                        .foregroundColor(type.color)
                        .font(.caption2)
                        .frame(width: 14, height: 14)
                }
                
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            .foregroundColor(isSelected ? .primary : .secondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Log Filter Popover
struct LogFilterPopover: View {
    let title: String
    @Binding var filters: Set<LoggingService.LogType>
    let showNote: Bool
    let onClear: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                Button {
                    onClear()
                } label: {
                    Text("Clear All")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
            }

            Text("Show message types:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(
                [
                    LoggingService.LogType.debug, .info, .notice, .warning, .error, .critical,
                    .fault,
                ], id: \.self
            ) { logType in
                LogTypeFilterRow(
                    logType: logType, 
                    isSelected: filters.contains(logType)
                ) {
                    if filters.contains(logType) {
                        filters.remove(logType)
                    } else {
                        filters.insert(logType)
                    }
                }
            }

            if showNote {
                Spacer()
                
                Text("Note: Empty selection shows all message types")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.top, 4)
            }
        }
        .padding(10)
        .frame(width: 280)
    }
}

// MARK: - Log Type Filter Row
struct LogTypeFilterRow: View {
    let logType: LoggingService.LogType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: logType.systemImage)
                .foregroundColor(logType.color)
                .frame(width: 16)

            Text(logType.rawValue.capitalized)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
                    .frame(width: 16)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Token Display Component
struct TokenDisplay: View {
    enum TokenType {
        case context, total
        
        var systemImage: String {
            switch self {
            case .context: return "character.textbox"
            case .total: return "sum"
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .context: return Color.secondary.opacity(0.1)
            case .total: return Color.secondary.opacity(0.1)
            }
        }
        
        var helpText: String {
            switch self {
            case .context: return "Current context tokens"
            case .total: return "Total tokens used"
            }
        }
    }
    
    let count: Int
    let type: TokenType
    let compactMode: Bool
    
    init(count: Int, type: TokenType, compactMode: Bool = false) {
        self.count = count
        self.type = type
        self.compactMode = compactMode
    }
    
    // Format large numbers in a compact way
    private var formattedCount: String {
        switch count {
        case 0..<1000:
            return "\(count)"
        case 1000..<1_000_000:
            let thousands = Double(count) / 1000.0
            return String(format: "%.1fk", thousands).replacingOccurrences(of: ".0", with: "")
        default:
            let millions = Double(count) / 1_000_000.0
            return String(format: "%.1fM", millions).replacingOccurrences(of: ".0", with: "")
        }
    }
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: type.systemImage)
                .foregroundColor(.secondary)
                .font(compactMode ? .caption : .caption)
                .frame(width: compactMode ? 14 : nil, height: compactMode ? 14 : nil)
            
            Text(formattedCount)
                .font(compactMode ? .caption : .subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false) // Prevent text truncation
        }
        .padding(.horizontal, compactMode ? 4 : 6)
        .padding(.vertical, compactMode ? 2 : 2)
        .background(type.backgroundColor)
        .cornerRadius(4)
        .help("\(type.helpText): \(count)")
        .frame(minWidth: compactMode ? 35 : 45) // Ensure minimum width to accommodate larger numbers
    }
}

// MARK: - Conversation Info Header
struct ConversationInfoHeader: View {
    let conversation: ConversationItem
    let isCompact: Bool
    let queryManager: QueryManager
    let onRequestModelSelection: (PersistentIdentifier) -> Void

    private var modelName: String {
        conversation.options.selectedModelID
            ?? conversation.options.apiConfiguration?.defaultModelID
            ?? "No model"
    }

    private var selectedModel: ModelItem? {
        guard let apiConfiguration = conversation.options.apiConfiguration else { return nil }
        return queryManager.model(with: modelName, for: apiConfiguration)
    }
    
    private var isStreamingEnabled: Bool {
        conversation.options.streamMode != .disabled
    }
    
    var body: some View {
        HStack(spacing: 6) {
            if conversation.isUtilityConversation {
                Image(systemName: "menubar.dock.rectangle")
                    .foregroundColor(.green)
                    .font(.caption)
                    .help("Linked to utility panel")
                
                Divider()
                    .frame(height: 14)
            }
            
            Text(conversation.options.apiConfiguration?.name ?? "No API Config")
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
                
            Divider()
                .frame(height: 14)

            // Model name with limited width and clickable for model selection
            Text(modelName)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.secondary)                
                .padding(.horizontal, 2)
                .onTapGesture {
                    if conversation.options.apiConfiguration != nil {
                        onRequestModelSelection(conversation.id)
                    }
                }
            
            Divider()
                .frame(height: 14)

            // Update token count display to use distinct sections for context and total
            HStack(spacing: 6) {
                TokenDisplay(count: conversation.tokenCount, type: .context, compactMode: true)
                TokenDisplay(count: conversation.usedTokenCount, type: .total, compactMode: true)
            }
            .padding(.horizontal, 2)
            .layoutPriority(2) // Increase layout priority for token displays
            
            Divider()
                .frame(height: 14)

            // Only show streaming toggle if model supports it and not compact
            if selectedModel?.capabilities.contains(.streaming) == true && !isCompact {
                HStack(spacing: 4) {
                    Image(systemName: isStreamingEnabled ? "sparkles" : "text.alignleft")
                        .font(.caption)
                    Text(isStreamingEnabled ? "Stream" : "Block")
                        .font(.caption)
                }
                .foregroundColor(isStreamingEnabled ? .blue : .secondary)
                .frame(width: 55, alignment: .leading)
                .padding(.horizontal, 2)
                .onTapGesture {
                    let newStreamValue = !isStreamingEnabled
                    do {
                        try queryManager.setStreamingEnabled(newStreamValue, for: conversation)
                    } catch {
                        vxAtelierPro.log.error(
                            "Stream parameter not found for \(conversation.title)")
                    }
                }
                .layoutPriority(3)
                
                Divider()
                    .frame(height: 14)
            }                
            
            if let selectedModel,
               !selectedModel.capabilities.isEmpty {
                // Show model metadata as icons
                HStack(spacing: 3) {
                    ForEach(selectedModel.capabilities) { capability in
                        Image(systemName: capability.systemName)
                            .foregroundColor(.blue)
                            .font(.caption2)
                            .frame(width: 14, height: 14)
                            .help(capability.displayName)
                    }
                }
                .layoutPriority(2)
                .padding(.horizontal, 2)

                Divider()
                    .frame(height: 14)
            }            
        }
    }
}
