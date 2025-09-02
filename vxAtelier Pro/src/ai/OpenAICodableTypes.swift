import Foundation

/// Contains all the Codable structures used for OpenAI API requests and responses
/// These structures are shared across multiple API providers that follow the OpenAI API format
class OpenAICodableTypes {
    // MARK: - Models
    
    struct Model: Codable {
        let id: String
        let object: String
        let owned_by: String
        let created: Int
    }
    
    struct ModelsResponse: Codable {
        let data: [Model]
    }
    
    // MARK: - Messages and Responses
    
    struct Message: Codable {
        let role: String
        let content: String?
        let tool_calls: [ToolCall]?
        let tool_call_id: String?
    }
    
    struct StreamingResponse: Codable {
        struct Delta: Codable {
            let content: String?
            let tool_calls: [ToolCall]?
        }
        
        struct StreamingChoice: Codable {
            let delta: Delta
            let index: Int
            let finish_reason: String?
        }
        
        let id: String
        let object: String
        let created: Int
        let model: String
        let choices: [StreamingChoice]
    }
    
    // MARK: - Tool Calls and Functions
    
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
    
    // MARK: - Chat Requests and Responses
    
    struct ChatRequest: Codable {
        var model: String
        var messages: [Message]
        var n: Int?
        var frequency_penalty: Double?
        var presence_penalty: Double?
        var top_p: Double?
        var temperature: Double?
        var max_tokens: Int?
        var response_format: ResponseFormat?
        var seed: Int?
        var stop: [String]?
        var user: String?
        var tools: [Tool]?
        var tool_choice: ToolChoice?
        var stream: Bool?
        
        struct ResponseFormat: Codable {
            let type: String
            
            static let json = ResponseFormat(type: "json_object")
            static let text = ResponseFormat(type: "text")
        }
        
        func asDictionary() -> [String: Any] {
            guard let data = try? JSONEncoder().encode(self) else { return [:] }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
    }
    
    enum ToolChoice: Codable {
        case auto
        case required
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .auto:
                try container.encode("auto")
            case .required:
                try container.encode("required")
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            switch value {
            case "auto": self = .auto
            case "required": self = .required
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid tool choice type")
            }
        }
    }
    
    struct ChatResponse: Codable {
        struct Choice: Codable {
            let message: Message
        }
        let choices: [Choice]
    }
} 