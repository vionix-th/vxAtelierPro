import Foundation
import SwiftData

// MARK: - API Configuration Export

struct APIConfigurationExportData: Codable {
    let name: String
    let providerID: String
    let authKind: String
    let baseURL: String
    let apiKey: String
    let adapterID: String
    let defaultModelID: String?
    let headersJSON: String?
    let optionsJSON: String?
    let credentialJSON: String?
    let isDefault: Bool?
    
    init(_ config: APIConfigurationItem) {
        self.name = config.name
        self.providerID = config.providerID
        self.authKind = config.authKind
        self.baseURL = config.baseURL
        self.apiKey = config.apiKey
        self.adapterID = config.adapterID
        self.defaultModelID = config.defaultModelID
        self.headersJSON = config.headersJSON
        self.optionsJSON = config.optionsJSON
        self.credentialJSON = config.credentialJSON
        self.isDefault = config.isDefault
    }
    
    func toDataItem() throws -> APIConfigurationItem {
        guard let providerID = LLMProviderID(rawValue: providerID) else {
            throw LLMProviderError.invalidConfiguration("Unknown provider id \(providerID).")
        }
        guard let adapterID = LLMAdapterID(rawValue: adapterID) else {
            throw LLMProviderError.invalidConfiguration("Unknown generation adapter id \(adapterID).")
        }
        guard let authKind = LLMAuthKind(rawValue: authKind) else {
            throw LLMProviderError.invalidConfiguration("Unknown authentication kind \(authKind).")
        }
        let item = APIConfigurationItem(
            name: name,
            apiKey: apiKey,
            baseURL: baseURL,
            isDefault: isDefault ?? false,
            defaultModel: defaultModelID,
            providerID: providerID
        )
        item.authKind = authKind.rawValue
        item.adapterID = adapterID.rawValue
        if let headersJSON { item.headersJSON = headersJSON }
        if let optionsJSON { item.optionsJSON = optionsJSON }
        if let credentialJSON { item.credentialJSON = credentialJSON }
        let configuration = try item.makeLLMProviderConfiguration()
        _ = try LLMProviderRegistry.shared.resolveRoute(
            adapterID: adapterID,
            providerID: providerID,
            modelID: defaultModelID,
            configuration: configuration
        )
        return item
    }
}
