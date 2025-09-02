import Foundation
import SwiftData

// MARK: - Model Export

struct ModelExportData: Codable {
    let name: String
    let contextSize: Int
    let provider: String
    let capabilities: [String]
    
    init(_ model: ModelItem) {
        self.name = model.name
        self.contextSize = model.contextSize
        self.provider = model.provider
        self.capabilities = model.capabilities.map { $0.rawValue }
    }
    
    func toDataItem() -> ModelItem {
        let model = ModelItem(name: name, contextSize: contextSize, provider: provider)
        model.capabilities = capabilities.compactMap { ModelCapability(rawValue: $0) }
        return model
    }
} 