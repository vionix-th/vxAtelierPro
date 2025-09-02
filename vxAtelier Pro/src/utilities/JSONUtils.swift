import Foundation

/// Utility methods for JSON operations, including string conversions, validation, and data manipulation.
/// 
/// This utility provides common operations for working with JSON data in various formats:
/// - Converting between JSON strings and dictionaries
/// - Validating JSON data
/// - Formatting JSON with optional pretty printing
/// - Merging JSON objects
public enum JSONUtils {
    
    /// Converts a JSON string to a dictionary.
    /// 
    /// - Parameter jsonString: A valid JSON string to convert
    /// - Returns: A dictionary representation of the JSON, or nil if conversion fails
    public static func jsonStringToDictionary(_ jsonString: String) -> [String: Any]? {
        guard let jsonData = jsonString.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        return config
    }
    
    /// Converts a dictionary to a JSON string.
    ///
    /// - Parameter dictionary: Dictionary to convert
    /// - Returns: JSON string representation, or nil if conversion fails
    public static func dictionaryToJsonString(_ dictionary: [String: Any]) -> String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dictionary, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
    
    /// Converts any JSON-compatible object to a JSON string.
    ///
    /// - Parameters:
    ///   - object: Any JSON-compatible object (array, dictionary, etc.)
    ///   - prettyPrinted: Whether to format the JSON with indentation and line breaks (default: false)
    /// - Returns: JSON string representation, or nil if conversion fails
    public static func objectToJsonString(_ object: Any, prettyPrinted: Bool = false) -> String? {
        let options: JSONSerialization.WritingOptions = prettyPrinted ? [.prettyPrinted] : []
        guard let jsonData = try? JSONSerialization.data(withJSONObject: object, options: options),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
    
    /// Checks if a string is valid JSON.
    ///
    /// - Parameter jsonString: String to validate
    /// - Returns: Boolean indicating if the string is valid JSON
    public static func isValidJson(_ jsonString: String) -> Bool {
        guard let jsonData = jsonString.data(using: .utf8) else {
            return false
        }
        return (try? JSONSerialization.jsonObject(with: jsonData)) != nil
    }
    
    /// Merges two dictionaries, with values from the second dictionary taking precedence.
    ///
    /// - Parameters:
    ///   - dict1: First dictionary
    ///   - dict2: Second dictionary (values take precedence)
    /// - Returns: Merged dictionary
    public static func mergeDictionaries(_ dict1: [String: Any], _ dict2: [String: Any]) -> [String: Any] {
        var result = dict1
        for (key, value) in dict2 {
            result[key] = value
        }
        return result
    }
} 