import Foundation

/// Capability advertised by a provider or model.
enum LLMModelCapability: String, Codable, CaseIterable, Identifiable {
    case text
    case image
    case audio
    case file
    case video
    case tools
    case strictTools
    case jsonSchema
    case jsonObject
    case reasoning
    case usage
    case streaming

    var id: String { rawValue }

    var kind: Kind {
        switch self {
        case .text, .image, .audio, .file, .video:
            return .content
        case .tools, .strictTools, .jsonSchema, .jsonObject, .reasoning, .usage, .streaming:
            return .feature
        }
    }

    enum Kind {
        case content
        case feature
    }
}

/// Temporary model metadata candidate used during fetch/enrichment before persistence.
struct LLMModelDescriptor: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var providerID: LLMProviderID
    var contextWindow: Int?
    var capabilities: [LLMModelCapability]
    var rawMetadataJSON: String?

    /// Creates normalized candidate metadata from provider defaults plus optional model-list details.
    init(
        id: String,
        displayName: String? = nil,
        providerID: LLMProviderID,
        contextWindow: Int? = nil,
        capabilities: [LLMModelCapability] = [.text],
        rawMetadataJSON: String? = nil
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.providerID = providerID
        self.contextWindow = contextWindow
        self.capabilities = capabilities
        self.rawMetadataJSON = rawMetadataJSON
    }
}
