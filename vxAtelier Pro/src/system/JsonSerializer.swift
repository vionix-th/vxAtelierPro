import Foundation
import SwiftData

enum JsonSerializationError: Error {
    case encodingFailed
    case decodingFailed
    case invalidData
}

// TODO: Analyze if can use generics to reduce code duplication
class JsonSerializer {
    static func exportProject(_ project: ProjectItem) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        let exportData = ProjectExportData(project)
        return try encoder.encode(exportData)
    }
    
    static func importProject(from data: Data, context: ModelContext) throws -> ProjectItem {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let projectData = try decoder.decode(ProjectExportData.self, from: data)
        return try projectData.toDataItem(context: context)
    }
    
    static func exportDialog(_ dialog: ConversationItem) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        let exportData = ConversationExportData(dialog)
        return try encoder.encode(exportData)
    }
    
    static func importDialog(from data: Data, context: ModelContext) throws -> ConversationItem {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dialogData = try decoder.decode(ConversationExportData.self, from: data)
        return try dialogData.toDataItem(context: context)
    }
    
    static func exportMessages(_ messages: [MessageItem]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        let exportData = messages.map { MessageExportData($0) }
        return try encoder.encode(exportData)
    }
    
    static func importMessages(from data: Data) throws -> [MessageItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let messagesData = try decoder.decode([MessageExportData].self, from: data)
        
        return messagesData.map { $0.toDataItem() }
    }
    
    static func exportPromptTemplate(_ template: PromptTemplate) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let exportData = PromptTemplateExportData(template)
        return try encoder.encode(exportData)
    }
    
    static func importPromptTemplate(from data: Data, context: ModelContext) throws -> PromptTemplate {
        let decoder = JSONDecoder()
        let importData = try decoder.decode(PromptTemplateExportData.self, from: data)
        return importData.toDataItem()
    }
    
    static func exportVoiceConfiguration(_ config: VoiceConfigurationItem) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let exportData = VoiceConfigurationExportData(config)
        return try encoder.encode(exportData)
    }
    
    static func importVoiceConfiguration(from data: Data) throws -> VoiceConfigurationItem {
        let decoder = JSONDecoder()
        let importData = try decoder.decode(VoiceConfigurationExportData.self, from: data)
        return importData.toDataItem()
    }
    
    static func exportModel(_ model: ModelItem) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let exportData = ModelExportData(model)
        return try encoder.encode(exportData)
    }
    
    static func importModel(from data: Data) throws -> ModelItem {
        let decoder = JSONDecoder()
        let importData = try decoder.decode(ModelExportData.self, from: data)
        return importData.toDataItem()
    }
    
    static func importData(from data: Data, context: ModelContext) async throws -> Any {
        // Try project first
        if let project = try? importProject(from: data, context: context) {
            return project
        }
        
        // Then try dialog
        if let dialog = try? importDialog(from: data, context: context) {
            return dialog
        }
        
        // Try voice configuration
        if let voiceConfig = try? importVoiceConfiguration(from: data) {
            return voiceConfig
        }
        
        // Try model
        if let model = try? importModel(from: data) {
            return model
        }
        
        // Finally try prompt template
        return try importPromptTemplate(from: data, context: context)
    }
} 
