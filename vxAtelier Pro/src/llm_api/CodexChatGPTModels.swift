import Foundation

/// Static model inventory for the Codex ChatGPT subscription backend route.
enum CodexChatGPTModels {
    static let modelIDs = [
        "gpt-5.5",
        "gpt-5.4",
        "gpt-5.4-mini",
        "gpt-5.3-codex",
        "gpt-5.3-codex-spark",
        "gpt-5.2"
    ]

    static func candidates() -> [LLMModelMetadata] {
        modelIDs.map {
            LLMDefaultsCatalog.bundled.modelMetadata(
                providerID: .openAICodexChatGPTSubscription,
                modelID: $0
            )
        }
    }
}
