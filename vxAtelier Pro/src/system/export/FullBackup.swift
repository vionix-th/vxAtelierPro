import Foundation
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

// MARK: - Backup Data Structures

// Add version constant at the top level
private enum BackupVersion {
    static let current = 2
}

struct FullBackup: Codable {
    let version: Int        // Add version field
    let timestamp: Date
    let projects: [ProjectExportData]
    let conversations: [ConversationExportData]
    let bookmarks: [BookmarkExportData]    
    let promptTemplates: [PromptTemplateExportData]
    let voiceConfigurations: [VoiceConfigurationExportData]
    let ttsPlaylists: [TTSPlaylistExportData]
    let apiConfigurations: [APIConfigurationExportData]
    let models: [ModelExportData]
    let webSearchConfigurations: [WebSearchConfigurationExportData]
    
    // Add initializer to ensure version is set
    init(
        projects: [ProjectExportData],
        conversations: [ConversationExportData],
        bookmarks: [BookmarkExportData],
        promptTemplates: [PromptTemplateExportData],
        voiceConfigurations: [VoiceConfigurationExportData],
        ttsPlaylists: [TTSPlaylistExportData],
        apiConfigurations: [APIConfigurationExportData],
        models: [ModelExportData],
        webSearchConfigurations: [WebSearchConfigurationExportData]
    ) {
        self.version = BackupVersion.current
        self.timestamp = Date()
        self.projects = projects
        self.conversations = conversations
        self.bookmarks = bookmarks
        self.promptTemplates = promptTemplates
        self.voiceConfigurations = voiceConfigurations
        self.ttsPlaylists = ttsPlaylists
        self.apiConfigurations = apiConfigurations
        self.models = models
        self.webSearchConfigurations = webSearchConfigurations
    }
    
    // Add decoder init to handle version differences
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode version, defaulting to 1 for older backups
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        
        // Ensure version is supported
        guard version <= BackupVersion.current else {
            throw BackupError.unsupportedVersion(version)
        }
        
        // Decode remaining fields
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        projects = try container.decode([ProjectExportData].self, forKey: .projects)
        conversations = try container.decode([ConversationExportData].self, forKey: .conversations)
        bookmarks = try container.decode([BookmarkExportData].self, forKey: .bookmarks)
        promptTemplates = try container.decode([PromptTemplateExportData].self, forKey: .promptTemplates)
        voiceConfigurations = try container.decode([VoiceConfigurationExportData].self, forKey: .voiceConfigurations)
        ttsPlaylists = try container.decode([TTSPlaylistExportData].self, forKey: .ttsPlaylists)
        apiConfigurations = try container.decode([APIConfigurationExportData].self, forKey: .apiConfigurations)
        models = try container.decode([ModelExportData].self, forKey: .models)
        webSearchConfigurations = try container.decodeIfPresent([WebSearchConfigurationExportData].self, forKey: .webSearchConfigurations) ?? []
    }
    
    // Explicit encoder implementation
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(projects, forKey: .projects)
        try container.encode(conversations, forKey: .conversations)
        try container.encode(bookmarks, forKey: .bookmarks)
        try container.encode(promptTemplates, forKey: .promptTemplates)
        try container.encode(voiceConfigurations, forKey: .voiceConfigurations)
        try container.encode(ttsPlaylists, forKey: .ttsPlaylists)
        try container.encode(apiConfigurations, forKey: .apiConfigurations)
        try container.encode(models, forKey: .models)
        try container.encode(webSearchConfigurations, forKey: .webSearchConfigurations)
    }
    
    // Updated CodingKeys
    private enum CodingKeys: String, CodingKey {
        case version, timestamp, projects, conversations, bookmarks, promptTemplates, voiceConfigurations, ttsPlaylists, apiConfigurations, models, webSearchConfigurations
    }
}

// Add error type for backup operations
enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This backup was created with a newer version (\(version)) and cannot be restored with the current version (\(BackupVersion.current))"
        }
    }
}

// MARK: - FileDocument wrapper for FullBackup
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var backupData: Data

    // Used for .fileExporter/.fileImporter
    init(backupData: Data) {
        self.backupData = backupData
    }

    // FileDocument conformance
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.backupData = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: backupData)
    }
} 
