import Foundation
import SwiftData
import SwiftUI
import Observation

/// Represents the possible types of argument values for AI request parameters
public enum AiArgumentValueType: String, Codable {
    case string
    case integer
    case float
    case boolean
}

/// Defines the possible UI control types for editing parameters
public enum AiArgumentControlType: String, Codable {
    case textField
    case stepper
    case slider
    case toggle
    case picker
}

/// Represents a parameter for AI service requests with its metadata.
///
/// This model provides a flexible way to define, validate, and store parameters
/// for AI service requests with appropriate typing and UI control hints.
@Model
public final class AiRequestArgument: ObservableObject {
    // Parameter metadata
    /// Unique identifier for this parameter
    public var name: String

    /// Human-readable name for display
    public var displayName: String

    /// Detailed explanation of the parameter's purpose
    public var paramDescription: String = ""

    /// Whether this parameter must have a value
    public var required: Bool = false

    /// The data type this parameter accepts (string, integer, etc.)
    public var valueType: String

    /// Suggested UI control type for editing this parameter
    public var controlType: String

    // Value constraints
    /// Minimum allowed value for numeric parameters
    public var minValue: Double? = nil

    /// Maximum allowed value for numeric parameters
    public var maxValue: Double? = nil

    /// Increment step for numeric UI controls
    public var step: Double? = nil

    /// Predefined options for picker-type parameters
    public var options: [String]? = nil

    // The actual value
    /// Serialized value data
    public var valueData: Data? = nil

    /// Whether the parameter is enabled and should be included
    public var isEnabled: Bool = true

    /// Creates a new parameter with specified metadata.
    ///
    /// - Parameters:
    ///   - name: Unique identifier for this parameter
    ///   - displayName: Human-readable name for display
    ///   - description: Detailed explanation of the parameter's purpose
    ///   - required: Whether this parameter must have a value
    ///   - valueType: The data type this parameter accepts
    ///   - controlType: Suggested UI control type for editing
    ///   - minValue: Minimum allowed value for numeric parameters
    ///   - maxValue: Maximum allowed value for numeric parameters
    ///   - step: Increment step for numeric UI controls
    ///   - options: Predefined options for picker-type parameters
    ///   - defaultValue: Initial value for this parameter
    public init(
        name: String,
        displayName: String,
        description: String = "",
        required: Bool = false,
        valueType: AiArgumentValueType,
        controlType: AiArgumentControlType,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        step: Double? = nil,
        options: [String]? = nil,
        defaultValue: Any? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.paramDescription = description
        self.required = required
        self.valueType = valueType.rawValue
        self.controlType = controlType.rawValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
        self.options = options
        self.isEnabled = required

        // Set default value if provided
        if let defaultValue = defaultValue {
            setValue(defaultValue)
        } else {
            // Set sensible defaults based on type
            switch valueType {
            case .string:
                setValue("")
            case .integer:
                setValue(0)
            case .float:
                setValue(0.0)
            case .boolean:
                setValue(false)
            }
        }
    }

    /// Returns the typed value according to the parameter's type.
    ///
    /// - Returns: The value in its native type (String, Int, Double, Bool),
    ///   or nil if the parameter is disabled or has no value
    public var value: Any? {
        guard isEnabled, let valueData = valueData else { return nil }

        let type = AiArgumentValueType(rawValue: self.valueType) ?? .string

        switch type {
        case .string:
            return String(data: valueData, encoding: .utf8)
        case .integer:
            do {
                return try JSONDecoder().decode(Int.self, from: valueData)
            } catch {
                vxAtelierPro.log.error("Failed to decode integer value: \(error.localizedDescription)")
                return nil
            }
        case .float:
            do {
                return try JSONDecoder().decode(Double.self, from: valueData)
            } catch {
                vxAtelierPro.log.error("Failed to decode float value: \(error.localizedDescription)")
                return nil
            }
        case .boolean:
            do {
                return try JSONDecoder().decode(Bool.self, from: valueData)
            } catch {
                vxAtelierPro.log.error("Failed to decode boolean value: \(error.localizedDescription)")
                return nil
            }
        }
    }

    var jsonValue: JSONValue? {
        guard isEnabled else { return nil }
        let type = AiArgumentValueType(rawValue: self.valueType) ?? .string
        switch type {
        case .string:
            return stringValue.map { .string($0) }
        case .integer:
            return intValue.map { .integer($0) }
        case .float:
            return floatValue.map { .number($0) }
        case .boolean:
            return boolValue.map { .boolean($0) }
        }
    }

    /// Sets the parameter value with appropriate type conversion.
    ///
    /// This method intelligently converts the provided value to the
    /// parameter's expected type and stores it as serialized data.
    ///
    /// - Parameter value: The value to set (can be any type that can be converted)
    public func setValue(_ value: Any?) {
        // Notify observers before changing valueData
        self.objectWillChange.send()

        guard let value = value else {
            valueData = nil
            return
        }

        let type = AiArgumentValueType(rawValue: self.valueType) ?? .string

        do {
            switch type {
            case .string:
                if let stringData = TypeConversionUtils.toString(value).data(using: .utf8) {
                    valueData = stringData
                } else {
                    vxAtelierPro.log.error("Failed to encode string value as UTF-8")
                }
            case .integer:
                valueData = try JSONEncoder().encode(TypeConversionUtils.toInt(value))
            case .float:
                valueData = try JSONEncoder().encode(TypeConversionUtils.toDouble(value))
            case .boolean:
                valueData = try JSONEncoder().encode(TypeConversionUtils.toBool(value))
            }
        } catch {
            vxAtelierPro.log.error("Failed to encode \(type.rawValue) value: \(error.localizedDescription)")
        }
    }

    func setJSONValue(_ value: JSONValue?) {
        guard let value else {
            setValue(nil)
            return
        }

        let type = AiArgumentValueType(rawValue: self.valueType) ?? .string
        switch type {
        case .string:
            setValue(value.stringValue ?? "")
        case .integer:
            setValue(value.integerValue ?? 0)
        case .float:
            setValue(value.doubleValue ?? 0)
        case .boolean:
            setValue(value.boolValue ?? false)
        }
    }

    /// Helper methods to get typed values directly

    /// Gets the value as a String if available.
    public var stringValue: String? {
        return value as? String
    }

    /// Gets the value as an Int if available.
    public var intValue: Int? {
        return value as? Int
    }

    /// Gets the value as a Double if available.
    public var floatValue: Double? {
        return value as? Double
    }

    /// Gets the value as a Bool if available.
    public var boolValue: Bool? {
        return value as? Bool
    }

    /// Creates a copy of this argument.
    ///
    /// - Returns: A new instance with the same properties and value
    public func copy() -> AiRequestArgument {
        let copy = AiRequestArgument(
            name: self.name,
            displayName: self.displayName,
            description: self.paramDescription,
            required: self.required,
            valueType: AiArgumentValueType(rawValue: self.valueType) ?? .string,
            controlType: AiArgumentControlType(rawValue: self.controlType) ?? .textField,
            minValue: self.minValue,
            maxValue: self.maxValue,
            step: self.step,
            options: self.options
        )

        copy.valueData = self.valueData
        copy.isEnabled = self.isEnabled

        return copy
    }

    /// Toggles the enabled state for optional parameters.
    ///
    /// Required parameters cannot be disabled.
    public func toggleEnabled() {
        if !required {
            isEnabled.toggle()
        }
    }
}
