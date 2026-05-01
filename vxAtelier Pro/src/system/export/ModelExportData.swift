import Foundation
import SwiftData

// MARK: - Model Export

struct ModelExportData: Codable {
    let name: String
    let contextSize: Int
    let provider: String
    let capabilities: [String]
    let modelID: String?
    let displayName: String?
    let providerID: String?
    let endpointFamilies: [String]?
    let modalities: [String]?
    let supportedParameters: [String]?
    let schemaFeatures: [String]?
    let rawMetadataJSON: String?
    
    init(_ model: ModelItem) {
        self.name = model.name
        self.contextSize = model.contextSize
        self.provider = model.provider
        self.capabilities = model.capabilities.map { $0.rawValue }
        self.modelID = model.modelID
        self.displayName = model.displayName
        self.providerID = model.providerID
        self.endpointFamilies = model.endpointFamiliesRaw
        self.modalities = model.modalitiesRaw
        self.supportedParameters = model.supportedParameters
        self.schemaFeatures = model.schemaFeaturesRaw
        self.rawMetadataJSON = model.rawMetadataJSON
    }
    
    func toDataItem() -> ModelItem {
        let model = ModelItem(name: name, contextSize: contextSize, provider: provider)
        model.capabilities = capabilities.compactMap { ModelCapability(rawValue: $0) }
        model.modelID = modelID ?? name
        model.displayName = displayName ?? name
        model.providerID = providerID ?? LLMProviderRegistry.providerID(fromProviderName: provider).rawValue
        model.endpointFamiliesRaw = endpointFamilies ?? [LLMEndpointFamily.chatCompletions.rawValue]
        model.modalitiesRaw = modalities ?? [LLMModality.text.rawValue]
        model.supportedParameters = supportedParameters ?? []
        model.schemaFeaturesRaw = schemaFeatures ?? []
        model.rawMetadataJSON = rawMetadataJSON
        return model
    }
}
