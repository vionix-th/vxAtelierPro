import Foundation
import SwiftData

// MARK: - API Configuration Export

struct APIConfigurationExportData: Codable {
    let name: String
    let baseURL: String
    let apiKey: String
    let chatCompletionsEndpoint: String
    let modelsEndpoint: String
    let isDefault: Bool?
    
    init(_ config: APIConfigurationItem) {
        self.name = config.name
        self.baseURL = config.baseURL
        self.apiKey = config.apiKey
        self.chatCompletionsEndpoint = config.chatCompletionsEndpoint
        self.modelsEndpoint = config.modelsEndpoint
        self.isDefault = config.isDefault
    }
    
    func toDataItem() -> APIConfigurationItem {
        return APIConfigurationItem(
            name: name,
            apiKey: apiKey,
            baseURL: baseURL,
            chatCompletionsEndpoint: chatCompletionsEndpoint,
            modelsEndpoint: modelsEndpoint,
            isDefault: isDefault ?? false
        )
    }
} 