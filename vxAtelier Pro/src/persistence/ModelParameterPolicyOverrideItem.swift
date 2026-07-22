import Foundation
import SwiftData

enum ModelDefaultValueOverrideKind: String, Codable, CaseIterable {
    case inherit
    case value
    case none
}

@Model
final class ModelParameterPolicyOverrideItem {
    var adapterIDRaw: String
    var parameterIDRaw: String
    var supportRaw: String?
    var requiredOverride: Bool?
    var enabledByDefaultOverride: Bool?
    var defaultValueOverrideKindRaw: String
    var defaultValueData: Data?

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

    var defaultValue: JSONValue? {
        get {
            guard let defaultValueData else { return nil }
            return try? JSONDecoder().decode(JSONValue.self, from: defaultValueData)
        }
        set { defaultValueData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var policy: LLMParameterPolicyOverride {
        let valueOverride: LLMDefaultValueOverride
        switch defaultValueOverrideKind {
        case .inherit:
            valueOverride = .inherit
        case .value:
            valueOverride = defaultValue.map(LLMDefaultValueOverride.value) ?? .none
        case .none:
            valueOverride = .none
        }
        return LLMParameterPolicyOverride(
            support: support,
            isRequired: requiredOverride,
            isEnabledByDefault: enabledByDefaultOverride,
            defaultValue: valueOverride
        )
    }

    init(
        adapterID: LLMAdapterID,
        parameterID: LLMParameterID,
        support: LLMSupportState? = nil,
        requiredOverride: Bool? = nil,
        enabledByDefaultOverride: Bool? = nil,
        defaultValueOverrideKind: ModelDefaultValueOverrideKind = .inherit,
        defaultValue: JSONValue? = nil
    ) {
        adapterIDRaw = adapterID.rawValue
        parameterIDRaw = parameterID.rawValue
        supportRaw = support?.rawValue
        self.requiredOverride = requiredOverride
        self.enabledByDefaultOverride = enabledByDefaultOverride
        defaultValueOverrideKindRaw = defaultValueOverrideKind.rawValue
        defaultValueData = defaultValue.flatMap { try? JSONEncoder().encode($0) }
    }
}
