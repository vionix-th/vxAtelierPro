import Foundation

extension ModelCapability {
    var displayName: String {
        switch self {
        case .vision: return "Vision"
        case .audio: return "Audio"
        case .streaming: return "Stream"
        case .function: return "Functions"
        case .text: return "Text"
        case .chat: return "Chat"
        case .image: return "Image"
        case .video: return "Video"
        case .embedding: return "Embed"
        }
    }

    var systemName: String {
        switch self {
        case .text: return "text.justify"
        case .chat: return "bubble.left.and.bubble.right"
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "video"
        case .function: return "function"
        case .embedding: return "point.3.connected.trianglepath.dotted"
        case .vision: return "eye"
        case .streaming: return "sparkles"
        }
    }
}
