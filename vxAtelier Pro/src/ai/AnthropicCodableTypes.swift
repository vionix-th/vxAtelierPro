import Foundation

/// Namespace for Anthropic API codable types
struct AnthropicCodableTypes {
    struct AnthropicModel: Codable {
        let type: String
        let id: String
        let display_name: String
        let created_at: String
    }
    
    struct ModelsResponse: Codable {
        let data: [AnthropicModel]
    }
    
    struct Message: Codable {
        let role: String
        let content: String
        let tool_calls: [ToolCall]?
        let tool_call_id: String?
    }
    
    struct ToolCall: Codable {
        let id: String
        let type: String
        let function: FunctionCall
    }
    
    struct FunctionCall: Codable {
        let name: String
        let arguments: String
    }
    
    struct Tool: Codable {
        let type: String
        let function: Function
    }
    
    struct Function: Codable {
        let name: String
        let description: String
        let parameters: Parameters
    }
    
    struct Parameters: Codable {
        let type: String
        let properties: [String: Property]
        let required: [String]?
    }
    
    struct Property: Codable {
        let type: String
        let description: String
        let enumValues: [String]?
        
        enum CodingKeys: String, CodingKey {
            case type
            case description
            case enumValues = "enum"
        }
    }
    
    struct ChatRequest: Codable {
        var model: String
        var messages: [Message]
        var temperature: Double?
        var max_tokens: Int?
        var top_p: Double?
        var top_k: Int?
        var stream: Bool?
        var system: String?
        var stop_sequences: [String]?
        var metadata: [String: String]?
        var tools: [Tool]?
        var tool_choice: ToolChoice?
        
        func asDictionary() -> [String: Any] {
            guard let data = try? JSONEncoder().encode(self) else { return [:] }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
    }
    
    enum ToolChoice: Codable {
        case none
        case auto
        case function(name: String)
        
        private enum CodingKeys: String, CodingKey {
            case type
            case function
            case name
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .none:
                try container.encode("none", forKey: .type)
            case .auto:
                try container.encode("auto", forKey: .type)
            case .function(let name):
                try container.encode("function", forKey: .type)
                var functionContainer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .function)
                try functionContainer.encode(name, forKey: .name)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "none": self = .none
            case "auto": self = .auto
            case "function":
                let functionContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .function)
                let name = try functionContainer.decode(String.self, forKey: .name)
                self = .function(name: name)
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid tool choice type")
            }
        }
    }
    
    struct ChatResponse: Codable {
        let id: String
        let type: String
        let role: String
        let content: [Content]
        let model: String
        let stop_reason: String?
        let usage: Usage
        let tool_calls: [ToolCall]?
    }
    
    struct Content: Codable {
        let type: String
        let text: String?
        
        private enum CodingKeys: String, CodingKey {
            case type, text
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            text = try container.decodeIfPresent(String.self, forKey: .text)
        }
    }
    
    struct Usage: Codable {
        let input_tokens: Int
        let output_tokens: Int
    }
} 