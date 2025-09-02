import Foundation

/// Model for DeepSeek API
struct DeepSeekModel: AIModel {
    let id: String
    let provider: String
    let capabilities: [ModelCapability]
    let contextSize: Int
    
    init(id: String, provider: String, capabilities: [ModelCapability], contextSize: Int) {
        self.id = id
        self.provider = provider
        self.capabilities = capabilities
        self.contextSize = contextSize
    }
} 