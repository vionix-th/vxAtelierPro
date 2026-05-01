import Foundation
import SwiftData

// MARK: - API Configuration Export

struct APIConfigurationExportData: Codable {
    let name: String
    let providerID: String?
    let authKind: String?
    let baseURL: String
    let apiKey: String
    let defaultEndpointFamily: String?
    let defaultModelID: String?
    let headersJSON: String?
    let optionsJSON: String?
    let isDefault: Bool?
    
    init(_ config: APIConfigurationItem) {
        self.name = config.name
        self.providerID = config.providerID
        self.authKind = config.authKind
        self.baseURL = config.baseURL
        self.apiKey = config.apiKey
        self.defaultEndpointFamily = config.defaultEndpointFamily
        self.defaultModelID = config.defaultModelID
        self.headersJSON = config.headersJSON
        self.optionsJSON = config.optionsJSON
        self.isDefault = config.isDefault
    }
    
    func toDataItem() -> APIConfigurationItem {
        let item = APIConfigurationItem(
            name: name,
            apiKey: apiKey,
            baseURL: baseURL,
            isDefault: isDefault ?? false,
            defaultModel: defaultModelID,
            providerID: providerID.flatMap(LLMProviderID.init(rawValue:)) ?? .customOpenAICompatible
        )
        if let authKind { item.authKind = authKind }
        if let defaultEndpointFamily { item.defaultEndpointFamily = defaultEndpointFamily }
        if let headersJSON { item.headersJSON = headersJSON }
        if let optionsJSON { item.optionsJSON = optionsJSON }
        return item
    }
}
