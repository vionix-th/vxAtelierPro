import Foundation

/// Durable execution state for a tool call persisted by the app layer.
enum LLMToolCallStatus: String, Codable, CaseIterable {
    case readyToExecute
    case executing
    case completed
    case failed
    case cancelled
}

/// Provider-neutral tool schema exposed to an LLM request.
struct LLMToolDefinition: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var description: String
    var parameters: JSONValue
}

/// Provider-neutral function/tool call emitted by an LLM provider.
struct LLMToolCall: Codable, Equatable, Identifiable {
    var id: String
    var callID: String?
    var index: Int
    var name: String
    var argumentsJSON: String

    init(id: String, callID: String? = nil, index: Int = 0, name: String, argumentsJSON: String) {
        self.id = id
        self.callID = callID
        self.index = index
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}
