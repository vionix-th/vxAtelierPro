import Foundation

struct AnthropicDefaults {
    static let defaultModels: [AIModel] = [
        AnthropicModel(
            id: "claude-3-opus",
            provider: "Anthropic",
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 200000
        ),
        AnthropicModel(
            id: "claude-3-sonnet",
            provider: "Anthropic",
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 200000
        ),
        AnthropicModel(
            id: "claude-3-7-sonnet-20250219",
            provider: "Anthropic", 
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 200000
        ),
        AnthropicModel(
            id: "claude-3-5-sonnet-20240620",
            provider: "Anthropic",
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 200000
        ),
        AnthropicModel(
            id: "claude-3-haiku-20240307",
            provider: "Anthropic",
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 200000
        ),
        AnthropicModel(
            id: "claude-3-opus-20240229",
            provider: "Anthropic",
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 200000
        ),
        AnthropicModel(
            id: "claude-2.1",
            provider: "Anthropic",
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 100000
        )
    ]
} 