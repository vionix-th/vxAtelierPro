import Foundation

/// Utility methods for safely converting between different data types.
///
/// This utility provides robust type conversion functions that:
/// - Handle multiple source types intelligently
/// - Provide sensible default values when conversion fails
/// - Support primitive types and complex data structures
/// - Prevent runtime crashes from failed type conversions
public enum TypeConversionUtils {

    /// Converts any value to a String representation.
    ///
    /// - Parameter value: Value to convert
    /// - Returns: String representation of the value
    public static func toString(_ value: Any) -> String {
        if let str = value as? String {
            return str
        } else {
            return String(describing: value)
        }
    }
    
    /// Safely converts any value to an Int.
    ///
    /// - Parameters:
    ///   - value: Value to convert (String, Int, Double, etc.)
    ///   - defaultValue: Default value to return if conversion fails (defaults to 0)
    /// - Returns: Int representation of the value, or defaultValue if conversion fails
    public static func toInt(_ value: Any, defaultValue: Int = 0) -> Int {
        if let int = value as? Int {
            return int
        } else if let double = value as? Double {
            return Int(double)
        } else if let str = value as? String, let parsed = Int(str) {
            return parsed
        } else {
            return defaultValue
        }
    }
    
    /// Safely converts any value to a Double.
    ///
    /// - Parameters:
    ///   - value: Value to convert (String, Int, Double, etc.)
    ///   - defaultValue: Default value to return if conversion fails (defaults to 0.0)
    /// - Returns: Double representation of the value, or defaultValue if conversion fails
    public static func toDouble(_ value: Any, defaultValue: Double = 0.0) -> Double {
        if let double = value as? Double {
            return double
        } else if let int = value as? Int {
            return Double(int)
        } else if let str = value as? String, let parsed = Double(str) {
            return parsed
        } else {
            return defaultValue
        }
    }
    
    /// Safely converts any value to a Bool.
    ///
    /// Accepts various truthy values:
    /// - Boolean true/false
    /// - Numeric values (0 = false, non-zero = true)
    /// - Strings ("true", "yes", "1" = true)
    ///
    /// - Parameters:
    ///   - value: Value to convert (String, Int, Bool, etc.)
    ///   - defaultValue: Default value to return if conversion fails (defaults to false)
    /// - Returns: Bool representation of the value, or defaultValue if conversion fails
    public static func toBool(_ value: Any, defaultValue: Bool = false) -> Bool {
        if let bool = value as? Bool {
            return bool
        } else if let int = value as? Int {
            return int != 0
        } else if let double = value as? Double {
            return double != 0
        } else if let str = value as? String {
            let lowercased = str.lowercased()
            return lowercased == "true" || lowercased == "yes" || lowercased == "1"
        } else {
            return defaultValue
        }
    }
    
    /// Safely converts any value to a [String: Any] dictionary.
    ///
    /// - Parameter value: Value to convert (must be a dictionary or a JSON string)
    /// - Returns: Dictionary, or nil if conversion fails
    public static func toDictionary(_ value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            return dict
        } else if let jsonString = value as? String {
            return JSONUtils.jsonStringToDictionary(jsonString)
        }
        return nil
    }
    
    /// Safely converts any value to an array.
    ///
    /// - Parameter value: Value to convert (must be an array or a JSON string representing an array)
    /// - Returns: Array, or nil if conversion fails
    public static func toArray(_ value: Any) -> [Any]? {
        if let array = value as? [Any] {
            return array
        } else if let jsonString = value as? String,
                  let data = jsonString.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return array
        }
        return nil
    }
} 