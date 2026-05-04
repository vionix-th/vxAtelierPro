import Foundation

/// Merges streaming tool-call fragments into stable calls by provider index.
struct LLMToolCallAssembler {
    private var callsByIndex: [Int: LLMToolCall] = [:]
    private var indexByID: [String: Int] = [:]

    /// Incorporates a provider delta and returns the current assembled call.
    mutating func merge(_ delta: LLMToolCall) -> LLMToolCall {
        let resolvedIndex: Int
        if let existingIndex = indexByID[delta.id] {
            resolvedIndex = existingIndex
        } else {
            resolvedIndex = delta.index
        }

        var existing = callsByIndex[resolvedIndex] ?? LLMToolCall(
            id: delta.id.isEmpty ? "tool-\(resolvedIndex)" : delta.id,
            callID: delta.callID,
            index: resolvedIndex,
            name: "",
            argumentsJSON: ""
        )

        if !delta.id.isEmpty {
            existing.id = delta.id
            indexByID[delta.id] = resolvedIndex
        }
        if let callID = delta.callID, !callID.isEmpty {
            existing.callID = callID
        }
        if !delta.name.isEmpty {
            existing.name = delta.name
        }
        existing.argumentsJSON += delta.argumentsJSON
        callsByIndex[resolvedIndex] = existing
        return existing
    }

    var assembled: [LLMToolCall] {
        callsByIndex.values.sorted { $0.index < $1.index }
    }
}
