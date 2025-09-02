import SwiftUI

// MARK: - Log History Sheet
struct LogHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: Set<LoggingService.LogType>
    @State private var displayedMessages: [LogEntry] = []
    
    // Use @StateObject to track the logging service for live updates
    @StateObject private var loggingService = LoggingService.shared
    
    // Initialize with filters but compute displayed messages internally
    init(filters: Binding<Set<LoggingService.LogType>>) {
        self._filters = filters
    }
    
    // Computed property to apply filters
    private var filteredMessages: [LogEntry] {
        loggingService.messageHistory.filter { 
            filters.isEmpty || filters.contains($0.type)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Log type filter section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Filters:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterButton(for: nil, label: "All")
                            
                            ForEach([
                                LoggingService.LogType.debug, .info, .notice, .warning, .error,
                                .critical, .fault,
                            ], id: \.self) { logType in
                                filterButton(for: logType, label: logType.rawValue.capitalized)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .background(Color.secondary.opacity(0.05))
                }
                .padding(.top, 10)
                .padding(.bottom, 4)
                
                // Log entries list
                List {
                    ForEach(filteredMessages) { entry in
                        LogEntryRow(entry: entry)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    
                    if filteredMessages.isEmpty {
                        Text("No messages with selected filter")
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Log History")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Text("\(filteredMessages.count) entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") {
                        loggingService.clearHistory()
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(idealWidth: 600, idealHeight: 500)
    }
    
    private func filterButton(for logType: LoggingService.LogType?, label: String) -> some View {
        FilterButton(
            logType: logType,
            label: label,
            isSelected: logType == nil ? filters.isEmpty : filters.contains(logType!)
        ) {
            if let type = logType {
                // If a specific type button is clicked
                if filters.contains(type) {
                    // If the selected type is already in filters, remove it
                    filters.remove(type)
                    // If this was the last filter, revert to "All" mode
                    if filters.isEmpty && logType != nil {
                        // We're already in "All" mode by having an empty filter set
                    }
                } else {
                    // Add this type to filters
                    filters.insert(type)
                }
            } else {
                // "All" button was clicked - clear all filters
                filters.removeAll()
            }
        }
    }
}

// MARK: - Log Entry Row
struct LogEntryRow: View {
    let entry: LogEntry
    @State private var isExpanded: Bool = false
    @State private var showCopied: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: entry.type.systemImage)
                    .foregroundColor(entry.type.color)
                    .frame(width: 18)

                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.message)
                        .font(.body)
                        .lineLimit(isExpanded ? nil : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if isExpanded {
                        Text(entry.callSiteInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
                
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                // Copy to clipboard button
                Button {
                    ExportUtils.copyToClipboard(entry.message)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showCopied = false
                    }
                } label: {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.body)
                        .foregroundColor(showCopied ? .green : .secondary)
                        .accessibilityLabel("Copy log entry to clipboard")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            isExpanded.toggle()
        }
    }
} 