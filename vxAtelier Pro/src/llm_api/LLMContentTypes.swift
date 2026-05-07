import Foundation

/// Provider-neutral content fragment carried by an LLM message.
struct LLMContentPart: Codable, Equatable, Identifiable {
    /// Semantic content kind before provider-specific request encoding.
    enum Kind: String, Codable {
        case text
        case image
        case audio
        case file
        case toolResult
        case reasoning
    }

    var id: UUID
    var kind: Kind
    var text: String?
    var mimeType: String?
    var dataBase64: String?
    var sourceURL: String?

    /// Creates a content part with only the fields needed by its semantic kind.
    init(
        id: UUID = UUID(),
        kind: Kind = .text,
        text: String? = nil,
        mimeType: String? = nil,
        dataBase64: String? = nil,
        sourceURL: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.mimeType = mimeType
        self.dataBase64 = dataBase64
        self.sourceURL = sourceURL
    }
}

/// Provider-neutral chat message, including optional assistant tool calls or tool results.
struct LLMMessage: Codable, Equatable, Identifiable {
    var id: UUID
    var role: String
    var content: [LLMContentPart]
    var toolCalls: [LLMToolCall]
    var toolCallID: String?

    /// Creates a provider-neutral message, including any assistant calls or tool-call result ID.
    init(
        id: UUID = UUID(),
        role: String,
        content: [LLMContentPart],
        toolCalls: [LLMToolCall] = [],
        toolCallID: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    /// Concatenates text-bearing content parts for display and tool-result transport.
    var displayText: String {
        content.compactMap(\.text).joined()
    }
}
