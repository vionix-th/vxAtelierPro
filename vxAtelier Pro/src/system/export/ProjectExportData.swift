import Foundation
import SwiftData

// MARK: - Project Export

struct ProjectExportData: Codable {
    let name: String
    let defaultOptions: ConversationOptionsExportData
    let dialogs: [ConversationExportData]?
    let status: String
    let timestamp: Date
    
    init(_ project: ProjectItem) {
        self.name = project.name
        self.defaultOptions = ConversationOptionsExportData(project.defaultOptions)
        self.dialogs = project.conversations.isEmpty ? nil : project.conversations.map { ConversationExportData($0) }
        self.status = project.status.rawValue
        self.timestamp = project.timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Required fields with defaults if decoding fails
        name = try container.decode(String.self, forKey: .name)
        defaultOptions = try container.decodeIfPresent(ConversationOptionsExportData.self, forKey: .defaultOptions) ?? ConversationOptionsExportData(ConversationOptions())
        dialogs = try container.decodeIfPresent([ConversationExportData].self, forKey: .dialogs)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ItemStatus.active.rawValue
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }
    
    func toDataItem(context: ModelContext) throws -> ProjectItem {
        let project = ProjectItem(name, defaultOptions: defaultOptions.toDataItem(context: context), status: ItemStatus(rawValue: status) ?? ItemStatus.active, timestamp: timestamp)
        
        if let dialogs = dialogs {
            for dialogData in dialogs {
                do {
                    let dialog = try dialogData.toDataItem(context: context)
                    project.conversations.append(dialog)
                } catch {
                    throw DataManagerError.modelConversionFailed(
                        model: "Project.dialogs",
                        field: "dialog[\(dialogData.title)]",
                        reason: error.localizedDescription
                    )
                }
            }
        }
        
        return project
    }
} 
