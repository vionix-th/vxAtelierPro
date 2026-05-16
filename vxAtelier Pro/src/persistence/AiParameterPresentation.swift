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
        case .topK:
            return .init(
                displayName: "Top K",
                description: "Sample only from the top K tokens",
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
                controlType: .picker
            )
        case .reasoningSummary:
            return .init(
                displayName: "Reasoning Summary",
                description: "Reasoning summary detail level",
                controlType: .picker
            )
        case .reasoningBudgetTokens:
            return .init(
                displayName: "Reasoning Budget Tokens",
                description: "Anthropic thinking budget in tokens",
                controlType: .stepper,
                step: 1
            )
        case .serviceTier:
            return .init(
                displayName: "Service Tier",
                description: "Provider service tier",
                controlType: .picker
            )
        case .textVerbosity:
            return .init(
                displayName: "Text Verbosity",
                description: "Response verbosity level",
                controlType: .picker
            )
        case .stream:
            return .init(
                displayName: "Stream",
                description: "Whether the provider request uses streaming transport",
                controlType: .toggle
            )
        case .store:
            return .init(
                displayName: "Store",
                description: "Whether the provider stores the response",
                controlType: .toggle
            )
        case .toolChoice:
            return .init(
                displayName: "Tool Choice",
                description: "Provider tool choice control",
                controlType: .textField
            )
        case .parallelToolCalls:
            return .init(
                displayName: "Parallel Tool Calls",
                description: "Whether the provider may run tool calls in parallel",
                controlType: .toggle
            )
        case .promptCacheKey:
            return .init(
                displayName: "Prompt Cache Key",
                description: "Provider prompt cache key",
                controlType: .textField
            )
        case .previousResponseID:
            return .init(
                displayName: "Previous Response ID",
                description: "Provider previous response identifier",
                controlType: .textField
            )
        case .include:
            return .init(
                displayName: "Include",
                description: "Additional provider response fields to include",
                controlType: .textField
            )
        case .frequencyPenalty:
            return .init(
                displayName: "Frequency Penalty",
                description: "Frequency penalty",
                controlType: .slider,
                step: 0.1
            )
        case .presencePenalty:
            return .init(
                displayName: "Presence Penalty",
                description: "Presence penalty",
                controlType: .slider,
                step: 0.1
            )
        case .logitBias:
            return .init(
                displayName: "Logit Bias",
                description: "Provider logit bias JSON",
                controlType: .textField
            )
        case .seed:
            return .init(
                displayName: "Seed",
                description: "Deterministic sampling seed",
                controlType: .stepper,
                step: 1
            )
        case .user:
            return .init(
                displayName: "User",
                description: "Provider user identifier",
                controlType: .textField
            )
        case .safetyIdentifier:
            return .init(
                displayName: "Safety Identifier",
                description: "Provider safety identifier",
                controlType: .textField
            )
        }
    }

    static func displayName(for parameterID: LLMParameterID) -> String {
        presentation(for: parameterID).displayName
    }
}
