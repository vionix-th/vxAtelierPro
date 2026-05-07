import Foundation

public enum AiArgumentControlType: String, Codable {
    case textField
    case stepper
    case slider
    case toggle
    case picker
}

struct AiParameterPresentation {
    var displayName: String
    var description: String
    var controlType: AiArgumentControlType
    var step: Double?
}

enum AiParameterPresentationCatalog {
    static func presentation(for parameterID: LLMParameterID) -> AiParameterPresentation {
        switch parameterID {
        case .model:
            return .init(
                displayName: "Model",
                description: "Model identifier used for this conversation",
                controlType: .textField
            )
        case .systemPrompt:
            return .init(
                displayName: "System Prompt",
                description: "Instructions for the assistant",
                controlType: .textField
            )
        case .maxOutputTokens:
            return .init(
                displayName: "Max Output Tokens",
                description: "Maximum number of generated tokens",
                controlType: .stepper,
                step: 1
            )
        case .temperature:
            return .init(
                displayName: "Temperature",
                description: "Sampling temperature",
                controlType: .slider,
                step: 0.1
            )
        case .topP:
            return .init(
                displayName: "Top P",
                description: "Nucleus sampling probability",
                controlType: .slider,
                step: 0.05
            )
        case .stopSequences:
            return .init(
                displayName: "Stop Sequences",
                description: "Stop sequences, one per line",
                controlType: .textField
            )
        case .responseFormat:
            return .init(
                displayName: "Response Format",
                description: "Generated response format",
                controlType: .picker
            )
        case .reasoningEffort:
            return .init(
                displayName: "Reasoning Effort",
                description: "Reasoning effort control",
                controlType: .textField
            )
        case .serviceTier:
            return .init(
                displayName: "Service Tier",
                description: "Provider service tier",
                controlType: .textField
            )
        }
    }

    static func displayName(for parameterID: LLMParameterID) -> String {
        presentation(for: parameterID).displayName
    }
}
