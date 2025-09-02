import SwiftUI
import Foundation

private let logSourcesKey = "LoggingService.sources"

private extension LogSourcesSettingsView {
    var searchBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor).opacity(0.7)
        #else
        return Color(UIColor.systemBackground).opacity(0.7)
        #endif
    }
    var toolbarBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(UIColor.secondarySystemBackground)
        #endif
    }
    var separatorColor: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color(UIColor.separator)
        #endif
    }
}


struct LogSourcesSettingsView: View {
    @State private var sources: [LogSource: Bool] = [:]
    @State private var isLoading = true
    @State private var searchText = ""
    
    var filteredSources: [LogSource] {
        if sources.isEmpty { return [] }
        
        return sources.keys.filter { source in
            searchText.isEmpty || 
            source.file.localizedCaseInsensitiveContains(searchText) ||
            source.function.localizedCaseInsensitiveContains(searchText)
        }.sorted(by: logSourceSort)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with search and toggle buttons
            HStack {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter log sources...", text: $searchText)
#if os(macOS)
                        .textFieldStyle(PlainTextFieldStyle())
#else
                        .textFieldStyle(.plain)
#endif
                        .padding(8)
                        .background(searchBackgroundColor)
                        .cornerRadius(6)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
#if os(macOS)
                        .buttonStyle(PlainButtonStyle())
#else
                        .buttonStyle(.plain)
#endif
                        .padding(.trailing, 4)
                    }
                }
                
                Spacer()
                
                // Toggle buttons
                if !filteredSources.isEmpty {
                    HStack(spacing: 8) {
                        Button(action: toggleAllFilteredOn) {
                            Text("Enable All")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
#if os(macOS)
                        .buttonStyle(PlainButtonStyle())
#else
                        .buttonStyle(.plain)
#endif
                        
                        Button(action: toggleAllFilteredOff) {
                            Text("Disable All")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
#if os(macOS)
                        .buttonStyle(PlainButtonStyle())
#else
                        .buttonStyle(.plain)
#endif
                    }
                    .padding(.trailing, 4)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(toolbarBackgroundColor)
            .overlay(Rectangle()
                .frame(height: 0.5)
                .foregroundColor(separatorColor),
                alignment: .bottom)
            
            // List of log sources
            if sources.isEmpty {
                Text("No log sources registered yet.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSources.isEmpty {
                Text("No log sources match '\(searchText)'")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredSources, id: \.self) { source in
                    Toggle(isOn: Binding(
                        get: { sources[source, default: true] },
                        set: { newValue in
                            sources[source] = newValue
                            saveSources()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.file)
                                .font(.headline)
                            Text(source.function)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Log Sources")
        .onAppear(perform: loadSources)
    }
    
    private func loadSources() {
        guard let data = UserDefaults.standard.data(forKey: logSourcesKey) else {
            sources = [:]
            return
        }
        do {
            let decoded = try JSONDecoder().decode([LogSource: Bool].self, from: data)
            sources = decoded
        } catch {
            sources = [:]
        }
    }
    
    private func saveSources() {
        do {
            let data = try JSONEncoder().encode(sources)
            UserDefaults.standard.set(data, forKey: logSourcesKey)
        } catch {
            // Ignore errors for now
        }
    }
    
    private func toggleAllFilteredOn() {
        for source in filteredSources {
            sources[source] = true
        }
        saveSources()
    }
    
    private func toggleAllFilteredOff() {
        for source in filteredSources {
            sources[source] = false
        }
        saveSources()
    }
    
    private func logSourceSort(lhs: LogSource, rhs: LogSource) -> Bool {
        if lhs.file == rhs.file {
            return lhs.function < rhs.function
        }
        return lhs.file < rhs.file
    }
}
