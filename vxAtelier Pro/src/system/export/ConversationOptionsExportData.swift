import Foundation
import SwiftData

// MARK: - Dialog Options Export

struct ConversationOptionsExportData: Codable {
    let avatarImageData: Data?
    let apiConfiguration: APIConfigurationExportData?
    let parameters: [ParameterValueExportData]
    let enabledToolsDict: [String: Bool]
    let isMarkdownEnabled: Bool
    
    init(_ options: ConversationOptions) {
        self.avatarImageData = options.avatarImageData
        self.apiConfiguration = options.apiConfiguration.map { APIConfigurationExportData($0) }
        self.parameters = options.parameters.map { ParameterValueExportData($0) }
        self.enabledToolsDict = options.enabledToolsDict
        self.isMarkdownEnabled = options.isMarkdownEnabled
    }
    
    func toDataItem(context: ModelContext) -> ConversationOptions {
        let options = ConversationOptions(
            avatarImageData: avatarImageData,
            apiConfiguration: apiConfiguration?.toDataItem()
        )
        
        // Add all parameters
        for paramData in parameters {
            options.parameters.removeAll { param in
                param.name == paramData.name
            }
            options.parameters.append(paramData.toParameter())
        }
        
        // Set enabled tools
        options.enabledToolsDict = enabledToolsDict
        options.isMarkdownEnabled = isMarkdownEnabled
        
        return options
    }
} 
