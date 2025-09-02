import Foundation

struct OpenAIDefaults {
    static let defaultModels: [AIModel] = [
        OpenAIModel(
            id: "gpt-4o",
            provider: "OpenAI",
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 128000
        ),
        OpenAIModel(
            id: "gpt-4o-mini",
            provider: "OpenAI",
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 128000
        ),
        OpenAIModel(
            id: "gpt-3.5-turbo",
            provider: "OpenAI",
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 16384
        ),
        OpenAIModel(
            id: "gpt-4-turbo",
            provider: "OpenAI",
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 128000
        ),
        OpenAIModel(
            id: "gpt-4-turbo-preview",
            provider: "OpenAI",
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 128000
        ),
        OpenAIModel(
            id: "gpt-4",
            provider: "OpenAI",
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 8192
        ),
        OpenAIModel(
            id: "o1",
            provider: "OpenAI",
            capabilities: [.text, .chat, .vision, .function],
            contextSize: 200000
        ),
        OpenAIModel(
            id: "o1-mini",
            provider: "OpenAI",
            capabilities: [.text, .chat, .vision, .function],
            contextSize: 128000
        ),
        OpenAIModel(
            id: "text-embedding-3-small",
            provider: "OpenAI",
            capabilities: [.text, .chat, .embedding],
            contextSize: 4096
        ),
        OpenAIModel(
            id: "text-embedding-3-large",
            provider: "OpenAI",
            capabilities: [.text, .chat, .embedding],
            contextSize: 4096
        )
    ]
} 