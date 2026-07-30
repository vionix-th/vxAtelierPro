import Foundation
import SwiftData

enum ModelDefaultValueOverrideKind: String, Codable, CaseIterable {
    case inherit
    case value
    case none
}

@Model
final class ModelParameterOverrideItem {
    var adapterIDRaw: String
    var parameterIDRaw: String
    var supportRaw: String?
    var encodingKindRaw: String?
    var wireKey: String?
    var structuredPresetRaw: String?
    var requiredOverride: Bool?
    var enabledByDefaultOverride: Bool?
    var defaultValueOverrideKindRaw: String
    var defaultValueData: Data?
    var optionsOverrideKindRaw: String
    var optionsData: Data?

    var adapterID: LLMAdapterID {
        get { LLMAdapterID(rawValue: adapterIDRaw) ?? .openAIChatCompletions }
        set { adapterIDRaw = newValue.rawValue }
    }

    var parameterID: LLMParameterID {
        get { LLMParameterID(rawValue: parameterIDRaw) ?? .maxOutputTokens }
        set { parameterIDRaw = newValue.rawValue }
    }

    var support: LLMSupportState? {
        get { supportRaw.flatMap(LLMSupportState.init(rawValue:)) }
        set { supportRaw = newValue?.rawValue }
    }

    var defaultValueOverrideKind: ModelDefaultValueOverrideKind {
        get { ModelDefaultValueOverrideKind(rawValue: defaultValueOverrideKindRaw) ?? .inherit }
        set { defaultValueOverrideKindRaw = newValue.rawValue }
    }

    var encodingKind: LLMParameterEncodingKind? {
        get { encodingKindRaw.flatMap(LLMParameterEncodingKind.init(rawValue:)) }
        set { encodingKindRaw = newValue?.rawValue }
    }

    var structuredPreset: LLMParameterStructuredPreset? {
        get { structuredPresetRaw.flatMap(LLMParameterStructuredPreset.init(rawValue:)) }
        set { structuredPresetRaw = newValue?.rawValue }
    }

    var mapping: LLMParameterMapping? {
        guard let encodingKind else { return nil }
        return LLMParameterMapping(
            adapterID: adapterID,
            parameterID: parameterID,
            encodingKind: encodingKind,
            wireKey: wireKey ?? "",
            structuredPreset: structuredPreset
        )
    }

    var optionsOverrideKind: ModelDefaultValueOverrideKind {
        get { ModelDefaultValueOverrideKind(rawValue: optionsOverrideKindRaw) ?? .inherit }
        set { optionsOverrideKindRaw = newValue.rawValue }
    }

    var options: [String]? {
        get {
            guard let optionsData else { return nil }
            return try? JSONDecoder().decode([String].self, from: optionsData)
        }
        set { optionsData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var defaultValue: JSONValue? {
        get {
            guard let defaultValueData else { return nil }
            return try? JSONDecoder().decode(JSONValue.self, from: defaultValueData)
        }
        set { defaultValueData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var overrides: LLMParameterOverrides {
        let valueOverride: LLMDefaultValueOverride
        switch defaultValueOverrideKind {
        case .inherit:
            valueOverride = .inherit
        case .value:
            valueOverride = defaultValue.map(LLMDefaultValueOverride.value) ?? .none
        case .none:
            valueOverride = .none
        }
        let optionsOverride: LLMOptionsOverride
        switch optionsOverrideKind {
        case .inherit:
            optionsOverride = .inherit
        case .value:
            optionsOverride = .value(options ?? [])
        case .none:
            optionsOverride = .none
        }
        return LLMParameterOverrides(
            support: support,
            mapping: mapping,
            isRequired: requiredOverride,
            isEnabledByDefault: enabledByDefaultOverride,
            defaultValue: valueOverride,
            options: optionsOverride
        )
    }

    var isEmpty: Bool {
        support == nil
            && mapping == nil
            && requiredOverride == nil
            && enabledByDefaultOverride == nil
            && defaultValueOverrideKind == .inherit
            && optionsOverrideKind == .inherit
    }

    init(
        adapterID: LLMAdapterID,
        parameterID: LLMParameterID,
        support: LLMSupportState? = nil,
        mapping: LLMParameterMapping? = nil,
        requiredOverride: Bool? = nil,
        enabledByDefaultOverride: Bool? = nil,
        defaultValueOverrideKind: ModelDefaultValueOverrideKind = .inherit,
        defaultValue: JSONValue? = nil,
        optionsOverrideKind: ModelDefaultValueOverrideKind = .inherit,
        options: [String]? = nil
    ) {
        adapterIDRaw = adapterID.rawValue
        parameterIDRaw = parameterID.rawValue
        supportRaw = support?.rawValue
        encodingKindRaw = mapping?.encodingKind.rawValue
        wireKey = mapping?.wireKey
        structuredPresetRaw = mapping?.structuredPreset?.rawValue
        self.requiredOverride = requiredOverride
        self.enabledByDefaultOverride = enabledByDefaultOverride
        defaultValueOverrideKindRaw = defaultValueOverrideKind.rawValue
        defaultValueData = defaultValue.flatMap { try? JSONEncoder().encode($0) }
        optionsOverrideKindRaw = optionsOverrideKind.rawValue
        optionsData = options.flatMap { try? JSONEncoder().encode($0) }
    }
}
