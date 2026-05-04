import Foundation

/// Input/output capability advertised by a provider or model.
enum LLMModality: String, Codable, CaseIterable {
    case text
    case image
    case audio
    case file
    case video
    case tool
    case reasoning
}

/// Structured-output and runtime feature advertised by a provider or model.
enum LLMSchemaFeature: String, Codable, CaseIterable {
    case tools
    case strictTools
    case jsonSchema
    case jsonObject
    case reasoning
    case usage
    case streaming
}

/// Provider-neutral model metadata used for validation and UI materialization.
struct LLMModelDescriptor: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var providerID: LLMProviderID
    var contextWindow: Int?
    var endpointFamilies: [LLMEndpointFamily]
    var modalities: [LLMModality]
    var supportedParameters: [String]
    var parameterMappings: [LLMParameterMappingDescriptor]
    var schemaFeatures: [LLMSchemaFeature]
    var rawMetadataJSON: String?

    init(
        id: String,
        displayName: String? = nil,
        providerID: LLMProviderID,
        contextWindow: Int? = nil,
        endpointFamilies: [LLMEndpointFamily],
        modalities: [LLMModality] = [.text],
        supportedParameters: [String] = [],
        parameterMappings: [LLMParameterMappingDescriptor] = [],
        schemaFeatures: [LLMSchemaFeature] = [],
        rawMetadataJSON: String? = nil
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.providerID = providerID
        self.contextWindow = contextWindow
        self.endpointFamilies = endpointFamilies
        self.modalities = modalities
        self.supportedParameters = supportedParameters
        self.parameterMappings = parameterMappings
        self.schemaFeatures = schemaFeatures
        self.rawMetadataJSON = rawMetadataJSON
    }
}
