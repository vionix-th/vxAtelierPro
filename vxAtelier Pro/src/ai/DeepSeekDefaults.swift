import Foundation

struct DeepSeekDefaults {
    static let defaultModels: [AIModel] = [
        DeepSeekModel(
            id: "deepseek-chat",
            provider: AIServiceProvider.deepSeek.rawValue,
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 32768
        ),
        DeepSeekModel(
            id: "deepseek-reasoner",
            provider: AIServiceProvider.deepSeek.rawValue,
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 32768
        ),        
        DeepSeekModel(
            id: "DeepSeek-V3",
            provider: AIServiceProvider.deepSeek.rawValue,
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 32768
        ),
        DeepSeekModel(
            id: "DeepSeek-R1",
            provider: AIServiceProvider.deepSeek.rawValue,
            capabilities: [.text, .chat, .function, .streaming],
            contextSize: 32768
        ),
    ]
} 