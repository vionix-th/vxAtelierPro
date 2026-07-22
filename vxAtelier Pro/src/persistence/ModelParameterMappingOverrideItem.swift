import Foundation
import SwiftData

@Model
final class ModelParameterMappingOverrideItem {
    var adapterIDRaw: String
    var parameterIDRaw: String
    var encodingKindRaw: String
    var wireKey: String
    var structuredPresetRaw: String?

    var adapterID: LLMAdapterID {
        get { LLMAdapterID(rawValue: adapterIDRaw) ?? .openAIChatCompletions }
        set { adapterIDRaw = newValue.rawValue }
    }

    var parameterID: LLMParameterID {
        get { LLMParameterID(rawValue: parameterIDRaw) ?? .maxOutputTokens }
        set { parameterIDRaw = newValue.rawValue }
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
            adapterID: adapterID,
            parameterID: parameterID,
            encodingKind: encodingKind,
            wireKey: wireKey,
            structuredPreset: structuredPreset
        )
    }

    init(mapping: LLMParameterMapping) {
        adapterIDRaw = mapping.adapterID.rawValue
        parameterIDRaw = mapping.parameterID.rawValue
        encodingKindRaw = mapping.encodingKind.rawValue
        wireKey = mapping.wireKey
        structuredPresetRaw = mapping.structuredPreset?.rawValue
    }
}
