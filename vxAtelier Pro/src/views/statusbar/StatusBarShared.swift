import SwiftData
import SwiftUI

struct StatusBarFilterButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundColor(isActive ? .blue : .secondary)
                .padding(AppDefaults.paddingSmall)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Filter status bar messages")
    }
}

struct StatusBarFilterPopover: View {
    let title: String
    @Binding var filters: Set<LoggingService.LogType>
    let showNote: Bool
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
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
                .padding(.vertical, AppDefaults.paddingSmall / 2)
                .padding(.horizontal, AppDefaults.paddingMedium)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(AppDefaults.cornerRadiusSmall)
            }

            Text("Show message types:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach([LoggingService.LogType.debug, .info, .notice, .warning, .error, .critical, .fault], id: \.self) { logType in
                StatusBarFilterRow(
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
                    .padding(.top, AppDefaults.paddingSmall)
            }
        }
        .padding(AppDefaults.paddingMedium)
    }
}

struct StatusBarFilterRow: View {
    let logType: LoggingService.LogType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: AppDefaults.paddingMedium) {
            Image(systemName: logType.systemImage)
                .foregroundColor(logType.color)

            Text(logType.rawValue.capitalized)

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, AppDefaults.paddingSmall)
        .padding(.horizontal, AppDefaults.paddingMedium)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(AppDefaults.cornerRadiusSmall)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct StatusBarTokenDisplay: View {
    enum TokenType {
        case context, total

        var systemImage: String {
            switch self {
            case .context: return "character.textbox"
            case .total: return "sum"
            }
        }

        var backgroundColor: Color {
            Color.secondary.opacity(0.1)
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
        HStack(spacing: AppDefaults.paddingSmall) {
            Image(systemName: type.systemImage)
                .foregroundColor(.secondary)
                .font(.caption)

            Text(formattedCount)
                .font(compactMode ? .caption : .subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, compactMode ? AppDefaults.paddingSmall : AppDefaults.paddingMedium)
        .padding(.vertical, AppDefaults.paddingSmall / 2)
        .background(type.backgroundColor)
        .cornerRadius(AppDefaults.cornerRadiusSmall)
        .help("\(type.helpText): \(count)")
    }
}

struct StatusBarModelPill: View {
    let modelName: String
    let compactMode: Bool
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    pillLabel
                }
                .buttonStyle(.plain)
            } else {
                pillLabel
            }
        }
        .help("Selected model")
    }

    private var pillLabel: some View {
        Text(modelName)
            .font(compactMode ? .caption : .subheadline)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, compactMode ? AppDefaults.paddingSmall : AppDefaults.paddingMedium)
            .padding(.vertical, AppDefaults.paddingSmall / 2)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(AppDefaults.cornerRadiusSmall)
    }
}

struct StatusBarConversationInfoRow: View {
    @Environment(QueryManager.self) private var queryManager

    let conversationID: PersistentIdentifier
    let allowsStreamingToggle: Bool
    let dense: Bool
    let onRequestOptions: () -> Void
    let onRequestModelSelection: (() -> Void)?
    let onToggleStreaming: ((Bool) -> Void)?

    private var conversation: ConversationItem? {
        queryManager.conversation(with: conversationID)
    }

    private var selectedModel: ModelItem? {
        guard let conversation,
              let apiConfiguration = conversation.options.apiConfiguration else {
            return nil
        }

        let modelName = conversation.options.selectedModelID
            ?? apiConfiguration.defaultModelID
            ?? "No model"
        return queryManager.model(with: modelName, for: apiConfiguration)
    }

    private var modelName: String {
        guard let conversation else { return "No model" }
        return conversation.options.selectedModelID
            ?? conversation.options.apiConfiguration?.defaultModelID
            ?? "No model"
    }

    private var apiConfigurationName: String {
        conversation?.options.apiConfiguration?.name ?? "No API Config"
    }

    private var tokenCount: Int {
        conversation?.tokenCount ?? 0
    }

    private var usedTokenCount: Int {
        conversation?.usedTokenCount ?? 0
    }

    private var supportsStreaming: Bool {
        selectedModel?.capabilities.contains(.streaming) == true
    }

    private var isStreamingEnabled: Bool {
        guard let conversation else { return false }
        return conversation.options.streamMode != .disabled
    }

    private var canSelectModel: Bool {
        conversation?.options.apiConfiguration != nil
    }

    private var isUtilityConversation: Bool {
        conversation?.isUtilityConversation == true
    }

    private var capabilities: [LLMModelCapability] {
        selectedModel?.capabilities ?? []
    }

    @ViewBuilder
    var body: some View {
        if conversation != nil {
            HStack(spacing: AppDefaults.paddingSmall) {
                if isUtilityConversation {
                    Image(systemName: "menubar.dock.rectangle")
                        .foregroundColor(.green)
                        .font(.caption)
                        .help("Linked to utility panel")
                }

                Button(action: onRequestOptions) {
                    Text(apiConfigurationName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("Open conversation options")

                StatusBarModelPill(
                    modelName: modelName,
                    compactMode: dense,
                    action: canSelectModel ? onRequestModelSelection : nil
                )

                HStack(spacing: AppDefaults.paddingSmall) {
                    StatusBarTokenDisplay(count: tokenCount, type: .context, compactMode: dense)
                    StatusBarTokenDisplay(count: usedTokenCount, type: .total, compactMode: dense)
                }
                .padding(.horizontal, AppDefaults.paddingSmall)

                if !dense {
                    if allowsStreamingToggle && supportsStreaming, let onToggleStreaming {
                        HStack(spacing: AppDefaults.paddingSmall) {
                            Image(systemName: isStreamingEnabled ? "sparkles" : "text.alignleft")
                                .font(.caption)
                            Text(isStreamingEnabled ? "Stream" : "Block")
                                .font(.caption)
                        }
                        .foregroundColor(isStreamingEnabled ? .blue : .secondary)
                        .padding(.horizontal, AppDefaults.paddingSmall)
                        .onTapGesture {
                            onToggleStreaming(!isStreamingEnabled)
                        }
                    }

                    if !capabilities.isEmpty {
                        HStack(spacing: AppDefaults.paddingSmall) {
                            ForEach(capabilities) { capability in
                                Image(systemName: capability.systemName)
                                    .foregroundColor(.blue)
                                    .font(.caption2)
                                    .help(capability.displayName)
                            }
                        }
                        .padding(.horizontal, AppDefaults.paddingSmall)
                    }
                }
            }
        } else {
            EmptyView()
        }
    }
}
