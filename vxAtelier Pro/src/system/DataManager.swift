import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Manages data operations for the application including backup, restore, import, and export functionality.
class DataManager {
    static let shared = DataManager()
    
    private init() {}
    
    // MARK: - Backup Creation
    
    @MainActor
    func createBackup(
        projects: [ProjectItem],
        conversations: [ConversationItem],
        bookmarks: [BookmarkItem],
        promptTemplates: [PromptTemplate],
        voiceConfigurations: [VoiceConfigurationItem],
        apiConfigurations: [APIConfigurationItem],
        models: [ModelItem],
        webSearchConfigurations: [WebSearchConfigurationItem]
    ) async throws -> Data {
        let projectExports = projects.map { ProjectExportData($0) }
        let conversationExports = conversations.map { ConversationExportData($0) }
        let bookmarkExports = bookmarks.map { BookmarkExportData($0) }
        let templateExports = promptTemplates.map { PromptTemplateExportData($0) }
        let voiceConfigExports = voiceConfigurations.map { VoiceConfigurationExportData($0) }
        let apiConfigExports = apiConfigurations.map { APIConfigurationExportData($0) }
        let modelExports = models.map { ModelExportData($0) }
        let webSearchConfigExports = webSearchConfigurations.map { WebSearchConfigurationExportData($0) }
        
        let backup = FullBackup(
            projects: projectExports,
            conversations: conversationExports,
            bookmarks: bookmarkExports,
            promptTemplates: templateExports,
            voiceConfigurations: voiceConfigExports,
            apiConfigurations: apiConfigExports,
            models: modelExports,
            webSearchConfigurations: webSearchConfigExports
        )
        
        // Use ExportUtils for encoding
        return try ExportUtils.encodeToData(backup)
    }
    
    @MainActor
    func saveBackup(
        projects: [ProjectItem],
        conversations: [ConversationItem],
        bookmarks: [BookmarkItem],
        promptTemplates: [PromptTemplate],
        voiceConfigurations: [VoiceConfigurationItem],
        apiConfigurations: [APIConfigurationItem],
        models: [ModelItem],
        webSearchConfigurations: [WebSearchConfigurationItem]
    ) async throws {
        let data = try await createBackup(
            projects: projects,
            conversations: conversations,
            bookmarks: bookmarks,
            promptTemplates: promptTemplates,
            voiceConfigurations: voiceConfigurations,
            apiConfigurations: apiConfigurations,
            models: models,
            webSearchConfigurations: webSearchConfigurations
        )
        try await FileHelper.shared.save(data: data, filename: "backup_\(Date().ISO8601Format()).json")
    }
    
    // MARK: - Backup Restore
    
    /// Restores application data from a backup file.
    /// - Parameters:
    ///   - data: The backup data to restore from
    ///   - context: The ModelContext to restore into
    @MainActor
    func restoreBackup(from data: Data, into context: ModelContext) async throws {
        // Validate backup format first, before any destructive operations
        // Use ExportUtils for decoding
        let backup: FullBackup
        do {
            backup = try ExportUtils.decodeFromData(FullBackup.self, from: data)
        } catch let decodingError as DecodingError {
            // Provide specific information about what's wrong with the backup format
            switch decodingError {
            case .keyNotFound(let key, _):
                throw DataManagerError.invalidFileFormat(
                    description: "Required field missing: \(key.stringValue)"
                )
            case .typeMismatch(let type, let context):
                throw DataManagerError.invalidFileFormat(
                    description: "Incorrect data type for \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): expected \(type)"
                )
            case .dataCorrupted(let context):
                throw DataManagerError.invalidFileFormat(
                    description: "Data corrupted: \(context.debugDescription)"
                )
            default:
                throw DataManagerError.invalidFileFormat(
                    description: "Invalid backup format: \(decodingError.localizedDescription)"
                )
            }
        } catch {
            throw DataManagerError.restoreFailed(
                reason: "Could not parse backup data",
                error: error
            )
        }
        
        // Backup format is valid, proceed with restore
        do {
            // Delete existing data
            try context.delete(model: ProjectItem.self)
            try context.delete(model: ConversationItem.self)
            try context.delete(model: BookmarkItem.self)
            try context.delete(model: PromptTemplate.self)
            try context.delete(model: VoiceConfigurationItem.self)
            try context.delete(model: APIConfigurationItem.self)
            try context.delete(model: ModelItem.self)
            try context.delete(model: WebSearchConfigurationItem.self)
            
            // Insert API configurations first as they're referenced by other items
            for configData in backup.apiConfigurations {
                let config = configData.toDataItem()
                context.insert(config)
            }
            
            // Insert Web Search configurations
            for searchConfigData in backup.webSearchConfigurations {
                let searchConfig = searchConfigData.toDataItem()
                context.insert(searchConfig)
            }
            
            for projectData in backup.projects {
                do {
                    let project = try projectData.toDataItem(context: context)
                    context.insert(project)
                } catch {
                    throw DataManagerError.modelConversionFailed(
                        model: "Project",
                        field: projectData.name,
                        reason: error.localizedDescription
                    )
                }
            }
            
            for conversationData in backup.conversations {
                do {
                    let conversation = try conversationData.toDataItem(context: context)
                    context.insert(conversation)
                } catch {
                    throw DataManagerError.modelConversionFailed(
                        model: "Conversation",
                        field: conversationData.title,
                        reason: error.localizedDescription
                    )
                }
            }
            
            for bookmarkData in backup.bookmarks {
                // Find the ConversationTurn by turnSequence in all conversations
                let allTurns = try context.fetch(FetchDescriptor<ConversationTurn>())
                if let turn = allTurns.first(where: { $0.sequenceNumber == bookmarkData.turnSequence }) {
                    let bookmark = bookmarkData.toDataItem(turn: turn)
                    context.insert(bookmark)
                }
            }
            
            for templateData in backup.promptTemplates {
                let template = templateData.toDataItem()
                context.insert(template)
            }
            
            for voiceConfigData in backup.voiceConfigurations {
                let voiceConfig = voiceConfigData.toDataItem()
                context.insert(voiceConfig)
            }
            
            let restoredApiConfigurations = try context.fetch(FetchDescriptor<APIConfigurationItem>())
            for modelData in backup.models {
                let model = modelData.toDataItem(apiConfigurations: restoredApiConfigurations)
                context.insert(model)
            }
            
            let queryManager = QueryManager(modelContext: context)
            queryManager.normalizeDefaultAPIConfigurations()
            queryManager.normalizeDefaultWebSearchConfigurations()
            try queryManager.saveContext()

            try await normalizeModelContext(context)
        } catch let error as DataManagerError {
            // Re-throw DataManagerError directly
            throw error
        } catch {
            // Wrap other errors
            throw DataManagerError.restoreFailed(
                reason: "Error writing data to database",
                error: error
            )
        }
    }
    
    // MARK: - Context Backup
    
    @MainActor
    func createBackup(from context: ModelContext) async throws -> Data {
        let projects = try context.fetch(FetchDescriptor<ProjectItem>())
        let allConversations = try context.fetch(FetchDescriptor<ConversationItem>())
        let standaloneConversations = allConversations.filter { $0.project == nil }
        let bookmarks = try context.fetch(FetchDescriptor<BookmarkItem>())
        let promptTemplates = try context.fetch(FetchDescriptor<PromptTemplate>())
        let voiceConfigurations = try context.fetch(FetchDescriptor<VoiceConfigurationItem>())
        let apiConfigurations = try context.fetch(FetchDescriptor<APIConfigurationItem>())
        let models = try context.fetch(FetchDescriptor<ModelItem>())
        let webSearchConfigurations = try context.fetch(FetchDescriptor<WebSearchConfigurationItem>())
        
        return try await createBackup(
            projects: projects,
            conversations: standaloneConversations,
            bookmarks: bookmarks,
            promptTemplates: promptTemplates,
            voiceConfigurations: voiceConfigurations,
            apiConfigurations: apiConfigurations,
            models: models,
            webSearchConfigurations: webSearchConfigurations
        )
    }
    
    @MainActor
    func saveBackup(from context: ModelContext) async throws {
        let data = try await createBackup(from: context)
        try await FileHelper.shared.save(data: data, filename: "backup_\(Date().ISO8601Format()).json")
    }
    
    // MARK: - Import/Export
    
    @MainActor
    func exportConversation(_ conversation: ConversationItem) async throws {
        let data = try JsonSerializer.exportConversation(conversation)
        try await FileHelper.shared.save(data: data, filename: "\(conversation.title).json")
    }
    
    @MainActor
    func exportProject(_ project: ProjectItem) async throws {
        let data = try JsonSerializer.exportProject(project)
        try await FileHelper.shared.save(data: data, filename: "\(project.name).json")
    }
    
    /// Imports a project or conversation from a file.
    /// - Parameter context: The ModelContext to import into
    /// - Returns: The imported item (either ProjectItem or ConversationItem)
    /// - Throws: If the import fails or the format is not recognized
    @MainActor
    func importData(into context: ModelContext) async throws -> Any {
        let data: Data
        
        do {
            data = try await FileHelper.shared.load()
        } catch {
            throw DataManagerError.importFailed(
                reason: "Could not load file", 
                underlyingErrors: [error]
            )
        }
        
        // Validate basic JSON structure first
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DataManagerError.invalidFileFormat(
                description: "The file is not valid JSON: \(error.localizedDescription)"
            )
        }
        
        // Try as project format
        var projectError: Error?
        do {
            let project = try JsonSerializer.importProject(from: data, context: context)
            try await normalizeModelContext(context)
            return project
        } catch {
            projectError = error
            vxAtelierPro.log.debug("Failed to import as project: \(error.localizedDescription)")
        }
        
        // Try as conversation format
        var conversationError: Error?
        do {
            let conversation = try JsonSerializer.importConversation(from: data, context: context)
            try await normalizeModelContext(context)
            return conversation
        } catch {
            conversationError = error
            vxAtelierPro.log.debug("Failed to import as conversation: \(error.localizedDescription)")
        }
        
        // Analyze errors to provide better feedback
        if projectError is DecodingError, conversationError is DecodingError {
            // Some other errors occurred during processing
            throw DataManagerError.importFailed(
                reason: "File format recognized but couldn't process data", 
                underlyingErrors: [projectError, conversationError].compactMap { $0 }
            )        
        } else {
            // Both were JSON parsing errors - likely wrong format entirely
            throw DataManagerError.invalidFileFormat(
                description: "File doesn't match project or conversation format"
            )
        }
    }
    
    @MainActor
    func exportSelectedMessages(_ messages: [MessageItem], conversationTitle: String) async throws {
        let exportData = messages.map { MessageExportData($0) }
        let data = try ExportUtils.encodeToData(exportData)
        try await FileHelper.shared.save(
            data: data,
            filename: "\(conversationTitle)_selected_messages.json"
        )
    }
    
    // MARK: - Model Context Normalization
    
    /// Normalizes the model context by deduplicating API configurations and ensuring proper references.
    /// - Parameter context: The ModelContext to normalize
    @MainActor
    func normalizeModelContext(_ context: ModelContext) async throws {
        vxAtelierPro.log.debug("Starting model context normalization")
        
        do {
            let configurations = try context.fetch(FetchDescriptor<APIConfigurationItem>())
            var uniqueConfigs: [String: APIConfigurationItem] = [:]
            var duplicates: [(original: APIConfigurationItem, duplicate: APIConfigurationItem)] = []
            
            for config in configurations {
                let key = "\(config.name)|\(config.providerID)|\(config.baseURL)|\(config.defaultEndpointFamily)"
                
                if let existing = uniqueConfigs[key] {
                    duplicates.append((original: existing, duplicate: config))
                } else {
                    uniqueConfigs[key] = config
                }
            }
            
            if duplicates.isEmpty {
                vxAtelierPro.log.debug("No duplicate configurations found")
                return
            }
            
            vxAtelierPro.log.notice("Found \(duplicates.count) duplicate API configurations")
            
            // Update references to use canonical configurations
            do {
                let conversations = try context.fetch(FetchDescriptor<ConversationItem>())
                for conversation in conversations {
                    if let config = conversation.options.apiConfiguration,
                       let duplicate = duplicates.first(where: { $0.duplicate.id == config.id }) {
                        conversation.options.apiConfiguration = duplicate.original
                        vxAtelierPro.log.debug("Updated conversation '\(conversation.title)' to use canonical API configuration")
                    }
                }
                
                let projects = try context.fetch(FetchDescriptor<ProjectItem>())
                for project in projects {
                    if let config = project.defaultOptions.apiConfiguration,
                       let duplicate = duplicates.first(where: { $0.duplicate.id == config.id }) {
                        project.defaultOptions.apiConfiguration = duplicate.original
                        vxAtelierPro.log.debug("Updated project '\(project.name)' to use canonical API configuration")
                    }
                }
                
                // Delete duplicates
                for (_, duplicate) in duplicates {
                    context.delete(duplicate)
                }
                
                vxAtelierPro.log.notice("Model context normalization completed. Removed \(duplicates.count) duplicate configurations")
                
            } catch {
                throw DataManagerError.normalizationFailed(
                    description: "Failed to update references",
                    error: error
                )
            }
        } catch {
            throw DataManagerError.normalizationFailed(
                description: "Failed to fetch configurations",
                error: error
            )
        }
    }

}

/// Represents errors that can occur during data operations
enum DataManagerError: LocalizedError {
    // Import/Export errors
    case invalidFileFormat(description: String)
    case importFailed(reason: String, underlyingErrors: [Error]?)
    case exportFailed(reason: String, error: Error?)
    
    // Backup/Restore errors
    case backupCreationFailed(reason: String, error: Error?)
    case restoreFailed(reason: String, error: Error?)
    
    // Data conversion errors
    case modelConversionFailed(model: String, field: String, reason: String)
    case referenceResolutionFailed(description: String)
    case normalizationFailed(description: String, error: Error?)
    
    var errorDescription: String? {
        switch self {
        case .invalidFileFormat(let description):
            return "Invalid file format: \(description)"
        case .importFailed(let reason, _):
            return "Import failed: \(reason)"
        case .exportFailed(let reason, _):
            return "Export failed: \(reason)"
        case .backupCreationFailed(let reason, _):
            return "Failed to create backup: \(reason)"
        case .restoreFailed(let reason, _):
            return "Failed to restore backup: \(reason)"
        case .modelConversionFailed(let model, let field, let reason):
            return "Failed to convert \(model).\(field): \(reason)"
        case .referenceResolutionFailed(let description):
            return "Failed to resolve reference: \(description)"
        case .normalizationFailed(let description, _):
            return "Failed to normalize data: \(description)"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .invalidFileFormat:
            return "The file does not match the expected format."
        case .importFailed(_, let errors):
            if let errors = errors, !errors.isEmpty {
                return "Import processing encountered \(errors.count) errors."
            }
            return "The import operation could not complete successfully."
        // ... additional cases
        default:
            return nil
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidFileFormat:
            return "Ensure the file is a valid JSON export from vxAtelier Pro."
        case .importFailed:
            return "Try exporting the data again from the source application."
        // ... additional cases
        default:
            return nil
        }
    }
} 
