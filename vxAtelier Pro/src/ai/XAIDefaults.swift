import Foundation

struct XAIDefaults {
    static let defaultModels: [AIModel] = [
        XAIModel(
            id: "grok-1",
            provider: "xAI",
            capabilities: [.text, .chat, .function, .streaming, .image],
            contextSize: 8192
        ),
        XAIModel(
            id: "grok-beta",
            provider: "xAI",
            capabilities: [.text, .chat, .function, .streaming, .image],
            contextSize: 4096
        ),
        XAIModel(
            id: "grok-1.5",
            provider: "xAI",
            capabilities: [.text, .chat, .function, .streaming, .image],
            contextSize: 128000
        ),
        XAIModel(
            id: "grok-1.5-vision",
            provider: "xAI",
            capabilities: [.text, .chat, .vision, .function, .streaming, .image],
            contextSize: 128000
        ),
        XAIModel(
            id: "grok-2-1212",
            provider: "xAI",
            capabilities: [.text, .chat, .function, .streaming, .image],
            contextSize: 4096
        ),
        XAIModel(
            id: "grok-2-image-1212",
            provider: "xAI",
            capabilities: [.text, .chat, .function, .streaming, .image],
            contextSize: 4096
        ),
        XAIModel(
            id: "grok-2-vision-1212",
            provider: "xAI",
            capabilities: [.text, .chat, .vision, .function, .streaming, .image],
            contextSize: 4096
        ),
        XAIModel(
            id: "grok-vision-beta",
            provider: "xAI",
            capabilities: [.text, .chat, .vision, .function, .streaming, .image],
            contextSize: 4096
        )
    ]
} 