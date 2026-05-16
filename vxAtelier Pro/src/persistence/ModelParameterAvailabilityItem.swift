import Foundation
import SwiftData

@Model
final class ModelParameterAvailabilityItem {
    var adapterIDRaw: String
    var semanticParameterID: String
    var isAvailable: Bool
    var isRequired: Bool
    var isEnabled: Bool
    var displayName: String
    var paramDescription: String
    var valueType: String
    var controlType: String
    var minValue: Double?
    var maxValue: Double?
    var step: Double?
    var options: [String]?
    var defaultValueData: Data?
    var isCustomized: Bool

    var adapterIDEnum: LLMAdapterID {
        get { LLMAdapterID(rawValue: adapterIDRaw) ?? .openAIChatCompletions }
        set { adapterIDRaw = newValue.rawValue }
    }

    var semanticParameterIDEnum: LLMParameterID {
        get { LLMParameterID(rawValue: semanticParameterID) ?? .maxOutputTokens }
        set {
            semanticParameterID = newValue.rawValue
            applyMetadata(from: newValue)
        }
    }

    var defaultJSONValue: JSONValue? {
        get {
            guard let defaultValueData else { return nil }
            return try? JSONDecoder().decode(JSONValue.self, from: defaultValueData)
        }
        set {
            if let newValue {
                defaultValueData = try? JSONEncoder().encode(newValue)
            } else {
                defaultValueData = nil
            }
        }
    }

    var descriptor: LLMParameterAvailabilityDescriptor {
        LLMParameterAvailabilityDescriptor(
            adapterID: adapterIDEnum,
            semanticParameterID: semanticParameterIDEnum,
            isAvailable: isAvailable,
            isRequired: isRequired,
            isEnabled: isEnabled,
            defaultValue: defaultJSONValue,
            options: options
        )
    }

    init(
        adapterID: LLMAdapterID,
        semanticParameterID: LLMParameterID,
        isAvailable: Bool = true,
        isRequired: Bool = false,
        isEnabled: Bool = false,
        defaultValue: JSONValue? = nil,
        isCustomized: Bool = false
    ) {
        self.adapterIDRaw = adapterID.rawValue
        self.semanticParameterID = semanticParameterID.rawValue
        self.isAvailable = isAvailable
        self.isRequired = isRequired
        self.isEnabled = isEnabled
        let presentation = AiParameterPresentationCatalog.presentation(for: semanticParameterID)
        self.displayName = presentation.displayName
        self.paramDescription = presentation.description
        self.valueType = semanticParameterID.valueType.rawValue
        self.controlType = presentation.controlType.rawValue
        self.minValue = semanticParameterID.minValue
        self.maxValue = semanticParameterID.maxValue
        self.step = presentation.step
        self.options = semanticParameterID.options
        if let defaultValue {
            self.defaultValueData = try? JSONEncoder().encode(defaultValue)
        } else {
            self.defaultValueData = nil
        }
        self.isCustomized = isCustomized
    }

    convenience init(descriptor: LLMParameterAvailabilityDescriptor, isCustomized: Bool = false) {
        self.init(
            adapterID: descriptor.adapterID,
            semanticParameterID: descriptor.semanticParameterID,
            isAvailable: descriptor.isAvailable,
            isRequired: descriptor.isRequired,
            isEnabled: descriptor.isEnabled,
            defaultValue: descriptor.defaultValue,
            isCustomized: isCustomized
        )
        options = descriptor.options ?? semanticParameterIDEnum.options
    }

    func apply(_ descriptor: LLMParameterAvailabilityDescriptor, markCustomized: Bool) {
        adapterIDEnum = descriptor.adapterID
        semanticParameterIDEnum = descriptor.semanticParameterID
        isAvailable = descriptor.isAvailable
        isRequired = descriptor.isRequired
        isEnabled = descriptor.isEnabled
        defaultJSONValue = descriptor.defaultValue
        options = descriptor.options ?? semanticParameterIDEnum.options
        isCustomized = markCustomized
    }

    func markCustomized() {
        isCustomized = true
    }

    private func applyMetadata(from parameterID: LLMParameterID) {
        let presentation = AiParameterPresentationCatalog.presentation(for: parameterID)
        displayName = presentation.displayName
        paramDescription = presentation.description
        valueType = parameterID.valueType.rawValue
        controlType = presentation.controlType.rawValue
        minValue = parameterID.minValue
        maxValue = parameterID.maxValue
        step = presentation.step
        options = parameterID.options
    }
}
