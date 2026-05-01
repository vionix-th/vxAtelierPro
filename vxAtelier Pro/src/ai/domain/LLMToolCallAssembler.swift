import Foundation

struct LLMToolCallAssembler {
    private var callsByIndex: [Int: LLMToolCall] = [:]
    private var indexByID: [String: Int] = [:]

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

extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? {
        self[key]?.stringValue
    }

    func int(_ key: String) -> Int? {
        self[key]?.integerValue
    }

    func double(_ key: String) -> Double? {
        self[key]?.doubleValue
    }

    func bool(_ key: String) -> Bool? {
        self[key]?.boolValue
    }

    func object(_ key: String) -> [String: JSONValue]? {
        self[key]?.objectValue
    }

    func array(_ key: String) -> [JSONValue]? {
        self[key]?.arrayValue
    }
}

extension JSONValue {
    var compactObject: [String: Any] {
        guard let object = objectValue else { return [:] }
        return object.mapValues { value in
            switch value {
            case .string(let string): return string
            case .number(let double): return double
            case .integer(let int): return int
            case .boolean(let bool): return bool
            case .array(let array): return array.map { $0.anyValue }
            case .object(let object): return object.mapValues { $0.anyValue }
            case .null: return NSNull()
            }
        }
    }

    var anyValue: Any {
        switch self {
        case .string(let string): return string
        case .number(let double): return double
        case .integer(let int): return int
        case .boolean(let bool): return bool
        case .array(let array): return array.map { $0.anyValue }
        case .object(let object): return object.mapValues { $0.anyValue }
        case .null: return NSNull()
        }
    }
}
