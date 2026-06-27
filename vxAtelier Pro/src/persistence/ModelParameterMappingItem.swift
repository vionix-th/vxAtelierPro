import Foundation
import SwiftData

@Model
final class ModelParameterMappingItem {
    var adapterIDRaw: String
    var parameterID: String
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

    var encodingKind: LLMParameterEncodingKind {
        get { LLMParameterEncodingKind(rawValue: encodingKindRaw) ?? .scalarKey }
        set { encodingKindRaw = newValue.rawValue }
    }

    var structuredPreset: LLMParameterStructuredPreset? {
        get { structuredPresetRaw.flatMap(LLMParameterStructuredPreset.init(rawValue:)) }
        set { structuredPresetRaw = newValue?.rawValue }
    }

    var mapping: LLMParameterMapping {
        LLMParameterMapping(
            adapterID: adapterIDEnum,
            parameterID: parameterIDEnum,
            encodingKind: encodingKind,
            wireKey: wireKey,
            structuredPreset: structuredPreset
        )
    }

    init(
        adapterID: LLMAdapterID,
        parameterID: LLMParameterID,
        encodingKind: LLMParameterEncodingKind = .scalarKey,
        wireKey: String = "",
        structuredPreset: LLMParameterStructuredPreset? = nil,
        isCustomized: Bool = false
    ) {
        self.adapterIDRaw = adapterID.rawValue
        self.parameterID = parameterID.rawValue
        self.encodingKindRaw = encodingKind.rawValue
        self.wireKey = wireKey
        self.structuredPresetRaw = structuredPreset?.rawValue
        let presentation = AiParameterPresentationCatalog.presentation(for: parameterID)
        self.displayName = presentation.displayName
        self.paramDescription = presentation.description
        self.valueType = parameterID.valueType.rawValue
        self.controlType = presentation.controlType.rawValue
        self.minValue = parameterID.minValue
        self.maxValue = parameterID.maxValue
        self.step = presentation.step
        self.options = parameterID.options
        self.isCustomized = isCustomized
    }

    convenience init(mapping: LLMParameterMapping, isCustomized: Bool = false) {
        self.init(
            adapterID: mapping.adapterID,
            parameterID: mapping.parameterID,
            encodingKind: mapping.encodingKind,
            wireKey: mapping.wireKey,
            structuredPreset: mapping.structuredPreset,
            isCustomized: isCustomized
        )
    }

    func apply(_ mapping: LLMParameterMapping, markCustomized: Bool) {
        adapterIDEnum = mapping.adapterID
        parameterIDEnum = mapping.parameterID
        encodingKind = mapping.encodingKind
        wireKey = mapping.wireKey
        structuredPreset = mapping.structuredPreset
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
