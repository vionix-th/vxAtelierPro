import Foundation
import SwiftData

@Model
final class ModelCapabilityOverrideItem {
    var capabilityRaw: String
    var supportRaw: String

    var capability: LLMModelCapability {
        get { LLMModelCapability(rawValue: capabilityRaw) ?? .text }
        set { capabilityRaw = newValue.rawValue }
    }

    var support: LLMSupportState {
        get { LLMSupportState(rawValue: supportRaw) ?? .unknown }
        set { supportRaw = newValue.rawValue }
    }

    init(capability: LLMModelCapability, support: LLMSupportState) {
        self.capabilityRaw = capability.rawValue
        self.supportRaw = support.rawValue
    }
}
