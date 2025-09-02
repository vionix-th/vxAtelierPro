import Foundation
import os
import Combine
import SwiftUI

/// Structured log entry for message history
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: LoggingService.LogType
    let file: String
    let function: String
    let line: Int
    
    var isError: Bool {
        type == .error || type == .critical || type == .fault
    }
    
    var isWarning: Bool {
        type == .warning
    }
    
    var callSiteInfo: String {
        return "\(file.components(separatedBy: "/").last ?? file):\(line) - \(function)"
    }
}

class LoggingService: ObservableObject {
    static let shared = LoggingService()
    
    @Published var latestMessage: String = "-"
    @Published var lastLogType: LogType = .info
    @Published var messageHistory: [LogEntry] = []
    
    private let logger = Logger(subsystem: "com.cutecube.software.vxAtelierPro", category: "main")
    private let sourcesKey = "LoggingService.sources"
    
    private init() {}
    
    // MARK: - Source Registration & Filtering
    private func registerSource(file: String, function: String) -> LogSource {
        let source = LogSource(file: file.components(separatedBy: "/").last ?? file, function: function)
        var sources = loadSources()
        if sources[source] == nil {
            sources[source] = true // Default: enabled
            saveSources(sources)
        }
        return source
    }
    
    private func isSourceEnabled(_ source: LogSource) -> Bool {
        let sources = loadSources()
        return sources[source] ?? true
    }
    
    // MARK: - Persistence
    private func saveSources(_ sources: [LogSource: Bool]) {
        do {
            let data = try JSONEncoder().encode(sources)
            UserDefaults.standard.set(data, forKey: sourcesKey)
        } catch {
            logger.error("Failed to save log sources: \(error.localizedDescription)")
        }
    }
    
    private func loadSources() -> [LogSource: Bool] {
        guard let data = UserDefaults.standard.data(forKey: sourcesKey) else { return [:] }
        do {
            let decoded = try JSONDecoder().decode([LogSource: Bool].self, from: data)
            return decoded
        } catch {
            logger.error("Failed to load log sources: \(error.localizedDescription)")
            return [:]
        }
    }
    
    // MARK: - Logging
    func log(_ message: String, type: LogType = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = file.components(separatedBy: "/").last ?? file
        let source = registerSource(file: fileName, function: function)
        guard isSourceEnabled(source) else { return }
        let callSite = "\(fileName):\(line) - \(function)"
        
        switch type {
        case .debug:
            logger.debug("[\(callSite)] \(message)")
        case .info:
            logger.info("[\(callSite)] \(message)")
        case .notice:
            logger.notice("[\(callSite)] \(message)")
        case .warning:
            logger.warning("[\(callSite)] \(message)")
        case .error:
            logger.error("[\(callSite)] \(message)")
        case .critical:
            logger.critical("[\(callSite)] \(message)")
        case .fault:
            logger.fault("[\(callSite)] \(message)")
        }
        
        DispatchQueue.main.async {
            self.latestMessage = message
            self.lastLogType = type
            self.messageHistory.append(LogEntry(
                timestamp: Date(),
                message: message,
                type: type,
                file: file,
                function: function,
                line: line
            ))
        }
    }
    
    // Wrapper methods to match Logger API
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .debug, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .info, file: file, function: function, line: line)
    }
    
    func notice(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .notice, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .warning, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .error, file: file, function: function, line: line)
    }
    
    func critical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .critical, file: file, function: function, line: line)
    }
    
    func fault(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .fault, file: file, function: function, line: line)
    }
    
    func clearHistory() {
        messageHistory = []
    }
    
    enum LogType: String {
        case debug, info, notice, warning, error, critical, fault
        
        var systemImage: String {
            switch self {
            case .debug:
                return "ladybug"
            case .info:
                return "info.circle"
            case .notice:
                return "bell"
            case .warning:
                return "exclamationmark.triangle"
            case .error, .critical, .fault:
                return "exclamationmark.circle"
            }
        }
        
        var color: Color {
            switch self {
            case .debug:
                return .gray
            case .info, .notice:
                return .blue
            case .warning:
                return .orange
            case .error, .critical, .fault:
                return .red
            }
        }
    }
}

struct LogEntryView: View {
    let entry: LogEntry
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(entry.message)
                .foregroundColor(entry.type.color)
                .font(.body)
            
            Text(entry.callSiteInfo)
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
}
