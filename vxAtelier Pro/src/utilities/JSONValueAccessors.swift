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
