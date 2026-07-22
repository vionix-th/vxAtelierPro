import Foundation

enum CodexChatGPTModels {
    static let modelIDs = [
        "gpt-5.5",
        "gpt-5.4",
        "gpt-5.4-mini",
        "gpt-5.3-codex",
        "gpt-5.3-codex-spark",
        "gpt-5.2",
    ]

    static func candidates() -> [LLMProviderModelObservation] {
        modelIDs.map {
            LLMProviderModelObservation(
                id: $0,
                providerID: .openAICodexChatGPTSubscription
            )
        }
    }
}
