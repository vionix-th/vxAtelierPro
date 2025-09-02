/// Represents any valid JSON value
public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null
    
    // MARK: - Initialization
    
    /// Initialize from any value, attempting to convert to appropriate JSON type
    public init(_ value: Any?) {
        if let value = value {
            switch value {
            case let string as String:
                self = .string(string)
            case let int as Int:
                self = .integer(int)
            case let double as Double:
                self = .number(double)
            case let bool as Bool:
                self = .boolean(bool)
            case let array as [Any]:
                self = .array(array.map(JSONValue.init))
            case let dict as [String: Any]:
                self = .object(dict.mapValues(JSONValue.init))
            default:
                // Convert unknown types to their string representation
                self = .string(String(describing: value))
            }
        } else {
            self = .null
        }
    }
    
    // MARK: - Value Accessors
    
    public var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .integer(let value): return String(value)
        case .boolean(let value): return String(value)
        case .null: return nil
        default: return String(describing: self)
        }
    }
    
    public var integerValue: Int? {
        switch self {
        case .integer(let value): return value
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        case .boolean(let value): return value ? 1 : 0
        default: return nil
        }
    }
    
    public var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .integer(let value): return Double(value)
        case .string(let value): return Double(value)
        case .boolean(let value): return value ? 1.0 : 0.0
        default: return nil
        }
    }
    
    public var boolValue: Bool? {
        switch self {
        case .boolean(let value): return value
        case .integer(let value): return value != 0
        case .number(let value): return value != 0
        case .string(let value): return value.lowercased() == "true"
        default: return nil
        }
    }
    
    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }
    
    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }
    
    // MARK: - Type Checking
    
    public var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }
    
    // MARK: - Codable
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .boolean(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .integer(int)
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid JSON value"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .null:
            try container.encodeNil()
        case .boolean(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - ExpressibleBy Protocols
extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .boolean(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - Custom String Convertible
extension JSONValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .string(let value): return "\"\(value)\""
        case .number(let value): return String(value)
        case .integer(let value): return String(value)
        case .boolean(let value): return String(value)
        case .array(let value): return String(describing: value)
        case .object(let value): return String(describing: value)
        case .null: return "null"
        }
    }
} 