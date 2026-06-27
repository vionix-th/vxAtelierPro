import Foundation
import SwiftData

@Model
final class ModelParameterAvailabilityItem {
    var adapterIDRaw: String
    var parameterID: String
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

    var parameterIDEnum: LLMParameterID {
        get { LLMParameterID(rawValue: parameterID) ?? .maxOutputTokens }
        set {
            parameterID = newValue.rawValue
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

    var availability: LLMParameterAvailability {
        LLMParameterAvailability(
            adapterID: adapterIDEnum,
            parameterID: parameterIDEnum,
            isAvailable: isAvailable,
            isRequired: isRequired,
            isEnabled: isEnabled,
            defaultValue: defaultJSONValue,
            options: options
        )
    }

    init(
        adapterID: LLMAdapterID,
        parameterID: LLMParameterID,
        isAvailable: Bool = true,
        isRequired: Bool = false,
        isEnabled: Bool = false,
        defaultValue: JSONValue? = nil,
        isCustomized: Bool = false
    ) {
        self.adapterIDRaw = adapterID.rawValue
        self.parameterID = parameterID.rawValue
        self.isAvailable = isAvailable
        self.isRequired = isRequired
        self.isEnabled = isEnabled
        let presentation = AiParameterPresentationCatalog.presentation(for: parameterID)
        self.displayName = presentation.displayName
        self.paramDescription = presentation.description
        self.valueType = parameterID.valueType.rawValue
        self.controlType = presentation.controlType.rawValue
        self.minValue = parameterID.minValue
        self.maxValue = parameterID.maxValue
        self.step = presentation.step
        self.options = parameterID.options
        if let defaultValue {
            self.defaultValueData = try? JSONEncoder().encode(defaultValue)
        } else {
            self.defaultValueData = nil
        }
        self.isCustomized = isCustomized
    }

    convenience init(availability: LLMParameterAvailability, isCustomized: Bool = false) {
        self.init(
            adapterID: availability.adapterID,
            parameterID: availability.parameterID,
            isAvailable: availability.isAvailable,
            isRequired: availability.isRequired,
            isEnabled: availability.isEnabled,
            defaultValue: availability.defaultValue,
            isCustomized: isCustomized
        )
        options = availability.options ?? parameterIDEnum.options
    }

    func apply(_ availability: LLMParameterAvailability, markCustomized: Bool) {
        adapterIDEnum = availability.adapterID
        parameterIDEnum = availability.parameterID
        isAvailable = availability.isAvailable
        isRequired = availability.isRequired
        isEnabled = availability.isEnabled
        defaultJSONValue = availability.defaultValue
        options = availability.options ?? parameterIDEnum.options
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
