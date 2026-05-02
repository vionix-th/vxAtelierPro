import Foundation
import SwiftData

@Model
final class ModelParameterMappingItem {
    var endpointFamilyRaw: String
    var semanticParameterID: String
    var isEnabled: Bool
    var isRequired: Bool
    var encodingKindRaw: String
    var wireKey: String
    var structuredPresetRaw: String?
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

    var endpointFamilyEnum: LLMEndpointFamily {
        get { LLMEndpointFamily(rawValue: endpointFamilyRaw) ?? .chatCompletions }
        set { endpointFamilyRaw = newValue.rawValue }
    }

    var semanticParameterIDEnum: LLMApplicationParameterID {
        get { LLMApplicationParameterID(rawValue: semanticParameterID) ?? .maxOutputTokens }
        set {
            semanticParameterID = newValue.rawValue
            applyMetadata(from: newValue)
        }
    }

    var encodingKind: ModelParameterEncodingKind {
        get { ModelParameterEncodingKind(rawValue: encodingKindRaw) ?? .scalarKey }
        set { encodingKindRaw = newValue.rawValue }
    }

    var structuredPreset: ModelParameterStructuredPreset? {
        get { structuredPresetRaw.flatMap(ModelParameterStructuredPreset.init(rawValue:)) }
        set { structuredPresetRaw = newValue?.rawValue }
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

    var descriptor: LLMParameterMappingDescriptor {
        LLMParameterMappingDescriptor(
            endpointFamily: endpointFamilyEnum,
            semanticParameterID: semanticParameterIDEnum,
            isEnabled: isEnabled,
            isRequired: isRequired,
            encodingKind: encodingKind,
            wireKey: wireKey,
            structuredPreset: structuredPreset,
            defaultValue: defaultJSONValue
        )
    }

    init(
        endpointFamily: LLMEndpointFamily,
        semanticParameterID: LLMApplicationParameterID,
        isEnabled: Bool = true,
        isRequired: Bool = false,
        encodingKind: ModelParameterEncodingKind = .scalarKey,
        wireKey: String = "",
        structuredPreset: ModelParameterStructuredPreset? = nil,
        defaultValue: JSONValue? = nil,
        isCustomized: Bool = false
    ) {
        self.endpointFamilyRaw = endpointFamily.rawValue
        self.semanticParameterID = semanticParameterID.rawValue
        self.isEnabled = isEnabled
        self.isRequired = isRequired
        self.encodingKindRaw = encodingKind.rawValue
        self.wireKey = wireKey
        self.structuredPresetRaw = structuredPreset?.rawValue
        self.displayName = semanticParameterID.displayName
        self.paramDescription = semanticParameterID.parameterDescription
        self.valueType = semanticParameterID.valueType.rawValue
        self.controlType = semanticParameterID.controlType.rawValue
        self.minValue = semanticParameterID.minValue
        self.maxValue = semanticParameterID.maxValue
        self.step = semanticParameterID.step
        self.options = semanticParameterID.options
        if let defaultValue {
            self.defaultValueData = try? JSONEncoder().encode(defaultValue)
        } else {
            self.defaultValueData = nil
        }
        self.isCustomized = isCustomized
    }

    convenience init(descriptor: LLMParameterMappingDescriptor, isCustomized: Bool = false) {
        self.init(
            endpointFamily: descriptor.endpointFamily,
            semanticParameterID: descriptor.semanticParameterID,
            isEnabled: descriptor.isEnabled,
            isRequired: descriptor.isRequired,
            encodingKind: descriptor.encodingKind,
            wireKey: descriptor.wireKey,
            structuredPreset: descriptor.structuredPreset,
            defaultValue: descriptor.defaultValue,
            isCustomized: isCustomized
        )
    }

    func apply(_ descriptor: LLMParameterMappingDescriptor, markCustomized: Bool) {
        endpointFamilyEnum = descriptor.endpointFamily
        semanticParameterIDEnum = descriptor.semanticParameterID
        isEnabled = descriptor.isEnabled
        isRequired = descriptor.isRequired
        encodingKind = descriptor.encodingKind
        wireKey = descriptor.wireKey
        structuredPreset = descriptor.structuredPreset
        defaultJSONValue = descriptor.defaultValue
        isCustomized = markCustomized
    }

    func markCustomized() {
        isCustomized = true
    }

    private func applyMetadata(from parameterID: LLMApplicationParameterID) {
        displayName = parameterID.displayName
        paramDescription = parameterID.parameterDescription
        valueType = parameterID.valueType.rawValue
        controlType = parameterID.controlType.rawValue
        minValue = parameterID.minValue
        maxValue = parameterID.maxValue
        step = parameterID.step
        options = parameterID.options
    }
}
