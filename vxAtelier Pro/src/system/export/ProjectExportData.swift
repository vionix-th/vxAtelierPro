import Foundation
import SwiftData

// MARK: - Project Export

struct ProjectExportData: Codable {
    let name: String
    let defaultOptions: ConversationOptionsExportData
    let conversations: [ConversationExportData]?
    let status: String
    let timestamp: Date
    
    init(_ project: ProjectItem) {
        self.name = project.name
        self.defaultOptions = ConversationOptionsExportData(project.defaultOptions)
        self.conversations = project.conversations.isEmpty ? nil : project.conversations.map { ConversationExportData($0) }
        self.status = project.status.rawValue
        self.timestamp = project.timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Required fields with defaults if decoding fails
        name = try container.decode(String.self, forKey: .name)
        defaultOptions = try container.decodeIfPresent(ConversationOptionsExportData.self, forKey: .defaultOptions) ?? ConversationOptionsExportData(ConversationOptions())
        conversations = try container.decodeIfPresent([ConversationExportData].self, forKey: .conversations)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ItemStatus.active.rawValue
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }
    
    func toDataItem(context: ModelContext) throws -> ProjectItem {
        let project = ProjectItem(name, defaultOptions: defaultOptions.toDataItem(context: context), status: ItemStatus(rawValue: status) ?? ItemStatus.active, timestamp: timestamp)
        
        if let conversations = conversations {
            for conversationData in conversations {
                do {
                    let conversation = try conversationData.toDataItem(context: context)
                    project.conversations.append(conversation)
                } catch {
                    throw DataManagerError.modelConversionFailed(
                        model: "Project.conversations",
                        field: "conversation[\(conversationData.title)]",
                        reason: error.localizedDescription
                    )
                }
            }
        }
        
        return project
    }
} 
