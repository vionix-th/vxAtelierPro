import Foundation
import SwiftData

// MARK: - Web Search Configuration Export

struct WebSearchConfigurationExportData: Codable {
    let name: String
    let provider: String // Stored as raw String value from WebSearchProvider enum
    let apiKey: String // Export optional as empty string if nil
    let searchEngineId: String // Export optional as empty string if nil

    init(_ config: WebSearchConfigurationItem) {
        self.name = config.name
        self.provider = config.provider // Already a String
        self.apiKey = config.apiKey ?? "" // Handle optional String
        self.searchEngineId = config.searchEngineId ?? "" // Handle optional String
    }

    func toDataItem() -> WebSearchConfigurationItem {
        let configItem = WebSearchConfigurationItem(
            name: name,
            provider: provider, // Use the stored string directly
            apiKey: apiKey.isEmpty ? nil : apiKey, // Convert empty string back to nil
            searchEngineId: searchEngineId.isEmpty ? nil : searchEngineId // Convert empty string back to nil
            // isDefault and createdAt will use default values on import
        )
        return configItem
    }
} 