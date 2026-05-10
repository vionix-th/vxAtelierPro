import SwiftUI

extension LLMModelCapability {
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .audio: return "Audio"
        case .file: return "File"
        case .video: return "Video"
        case .tools: return "Tools"
        case .strictTools: return "Strict Tools"
        case .jsonSchema: return "JSON Schema"
        case .jsonObject: return "JSON Object"
        case .reasoning: return "Reasoning"
        case .usage: return "Usage"
        case .streaming: return "Streaming"
        }
    }

    var systemName: String {
        switch self {
        case .text: return "text.justify"
        case .image: return "photo"
        case .audio: return "waveform"
        case .file: return "doc"
        case .video: return "video"
        case .tools: return "function"
        case .strictTools: return "checkmark.shield"
        case .jsonSchema: return "curlybraces.square"
        case .jsonObject: return "curlybraces"
        case .reasoning: return "brain"
        case .usage: return "chart.bar"
        case .streaming: return "sparkles"
        }
    }
}

extension ModelItem {
    var metadataIconSystemNames: [String] {
        capabilities.map(\.systemName)
            .reduce(into: [String]()) { result, symbol in
                if !result.contains(symbol) {
                    result.append(symbol)
                }
            }
    }

    var metadataSearchTerms: [String] {
        capabilities.map(\.displayName)
    }
}
