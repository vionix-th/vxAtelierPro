import Foundation
import SwiftData

// MARK: - Conversation Options Export - Parameter Value

// Parameter value export for serialization
struct ParameterValueExportData: Codable {
    let name: String
    let displayName: String
    let paramDescription: String
    let required: Bool
    let valueType: String
    let controlType: String
    
    // Constraints
    let minValue: Double?
    let maxValue: Double?
    let step: Double?
    let options: [String]?
    
    // Value storage
    let valueData: Data?
    let isEnabled: Bool
    
    init(_ param: AiRequestArgument) {
        self.name = param.name
        self.displayName = param.displayName
        self.paramDescription = param.paramDescription
        self.required = param.required
        self.valueType = param.valueType
        self.controlType = param.controlType
        
        self.minValue = param.minValue
        self.maxValue = param.maxValue
        self.step = param.step
        self.options = param.options
        
        self.valueData = param.valueData
        self.isEnabled = param.isEnabled
    }
    
    func toParameter() -> AiRequestArgument {
        let valueType = LLMParameterValueType(rawValue: self.valueType) ?? .string
        let controlType = AiArgumentControlType(rawValue: self.controlType) ?? .textField
        
        let param = AiRequestArgument(
            name: name,
            displayName: displayName,
            description: paramDescription,
            required: required,
            valueType: valueType,
            controlType: controlType,
            minValue: minValue,
            maxValue: maxValue,
            step: step,
            options: options
        )
        
        // Set raw value data directly
        param.valueData = valueData
        param.isEnabled = isEnabled
        
        return param
    }
} 