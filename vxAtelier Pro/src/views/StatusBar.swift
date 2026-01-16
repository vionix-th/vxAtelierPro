import SwiftData
import SwiftUI

// MARK: - Status Bar View
struct StatusBar: View {
    // MARK: - Properties
    @StateObject private var loggingService = LoggingService.shared
    @State private var isStatusBarFilterPopoverOpen: Bool = false
    @State private var popupLogTypeFilters: Set<LoggingService.LogType> = []
    @State private var statusBarLogTypeFilters: Set<LoggingService.LogType> = []
    @Environment(\.showLogHistory) private var showLogHistory
    @State private var displayedMessage: String = ""
    private let messageAnimation: Animation = .easeInOut(duration: 0.18)
    
    // Environment access
    @Environment(QueryManager.self) private var queryManager
    
    // Track the active item from ContentView
    let activeItemId: PersistentIdentifier?
    
    // UserDefaults keys
    private let popupFilterKey = "popupLogTypeFilters"
    private let statusBarFilterKey = "statusBarLogTypeFilters"

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
    init(activeItemId: PersistentIdentifier?) {
        self.activeItemId = activeItemId
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
                        showLogHistory()
                    }
                
                // Only show dialog info inline if we have an active dialog and not compact
                if let activeItemId = activeItemId,
                   let dialog = queryManager.allConversations.first(where: { $0.id == activeItemId }),
                   !isCompact {
                    HStack(spacing: 6) {
                        DialogInfoHeader(dialog: dialog, isCompact: false)
                            .layoutPriority(1)
                    }
                    .frame(minWidth: 200, idealWidth: 400, maxWidth: 500, alignment: .trailing)
                }
            }
            .frame(height: 32)
            .background(Color.secondary.opacity(0.1))
            
            // On compact (iPhone), show DialogInfoHeader below if active
            if let activeItemId = activeItemId,
               let dialog = queryManager.allConversations.first(where: { $0.id == activeItemId }),
               isCompact {
                DialogInfoHeader(dialog: dialog, isCompact: true)
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

// MARK: - Dialog Info Header
struct DialogInfoHeader: View {
    let dialog: ConversationItem
    let isCompact: Bool
    @State private var isModelPickerPresented: Bool = false
    @State private var refreshTrigger = UUID()
    
    private var modelParam: AiRequestArgument? {
        dialog.options.parameters.first(where: { $0.name == "model" })
    }
    
    private var modelName: String {
        modelParam?.stringValue ?? "No model"
    }
    
    private var modelCapabilities: [ModelCapability] {
        ModelProviderUtils.inferCapabilities(from: modelName)
    }
    
    private var isStreamingEnabled: Bool {
        let streamParam = dialog.options.parameters.first(where: { $0.name == "stream" })
        return streamParam?.boolValue ?? false
    }
    
    private var currentProvider: AIServiceProvider {
        if let config = dialog.options.apiConfiguration {
            return AIServiceProvider.detectProvider(from: config)
        }
        return .openAI // Default provider
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Add utility panel link icon if the dialog is linked
            if dialog.isLinkedToUtilityPanel {
                Image(systemName: "menubar.dock.rectangle")
                    .foregroundColor(.green)
                    .font(.caption)
                    .help("Linked to utility panel")
                
                Divider()
                    .frame(height: 14)
            }
            
            Text(dialog.options.apiConfiguration?.name ?? "No API Config")
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
                .id(refreshTrigger) // Force refresh when this ID changes
                .onTapGesture {
                    if dialog.options.apiConfiguration != nil {
                        isModelPickerPresented = true
                        vxAtelierPro.log.debug("Opening model picker from status bar")
                    }
                }
                .sheet(isPresented: $isModelPickerPresented) {
                    if dialog.options.apiConfiguration != nil {
                        ModelSelectionView(
                            selectedModel: modelName,
                            onModelSelected: { newModel in
                                if let param = modelParam {
                                    param.setValue(newModel)
                                    // Force refresh of the view
                                    refreshTrigger = UUID()
                                    vxAtelierPro.log.debug("Changed model to \(newModel) for \(dialog.title)")
                                }
                            },
                            currentProvider: currentProvider
                        )
                    }
                }
            
            Divider()
                .frame(height: 14)

            // Update token count display to use distinct sections for context and total
            HStack(spacing: 6) {
                TokenDisplay(count: dialog.tokenCount, type: .context, compactMode: true)
                TokenDisplay(count: dialog.usedTokenCount, type: .total, compactMode: true)
            }
            .padding(.horizontal, 2)
            .layoutPriority(2) // Increase layout priority for token displays
            
            Divider()
                .frame(height: 14)

            // Only show streaming toggle if model supports it and not compact
            if modelCapabilities.contains(.streaming) && !isCompact {
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
                    // Check if stream parameter exists
                    if let streamParam = dialog.options.parameters.first(where: {
                        $0.name == "stream"
                    }) {
                        // Toggle the value
                        let newStreamValue = !(streamParam.boolValue ?? false)

                        // Update both the value and enabled state
                        streamParam.setValue(newStreamValue)
                        streamParam.isEnabled = newStreamValue

                        vxAtelierPro.log.info(
                            "Toggled streaming to \(newStreamValue ? "enabled" : "disabled") for \(dialog.title)"
                        )
                    } else {
                        vxAtelierPro.log.error(
                            "Stream parameter not found for \(dialog.title)")
                    }
                }
                .layoutPriority(3)
                
                Divider()
                    .frame(height: 14)
            }                
            
            if !modelCapabilities.isEmpty {                                
                // Show model capabilities as icons
                HStack(spacing: 3) {
                    ForEach(modelCapabilities, id: \.self) { capability in
                        Image(systemName: capability.systemName)
                            .foregroundColor(.blue)
                            .font(.caption2)
                            .frame(width: 14, height: 14)
                            .help(capability.rawValue)
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
