# AIService Framework Documentation

The AIService framework provides a flexible and extensible architecture for integrating various AI service providers into an application. It defines a set of protocols and base implementations that allow easy addition of new AI services while maintaining a consistent interface.

## Key Components

### AIService Protocol

The `AIService` protocol defines the core functionality that every AI service provider must implement. It includes methods for:

- Fetching available models (`fetchAvailableModels()`)
- Getting default request parameters (`getDefaultParameters()`) 
- Applying parameters to a request (`applyParameters(to:from:)`)
- Accessing the chat completion service (`chat` property)

Key associated types:
- `AIModel`: Represents a model supported by the service
- `AIChatCompletionRequest`: Provider-specific chat request type
- `AIChatCompletionResponse`: Provider-specific chat response type

### AIChatCompletionServiceStreamable Protocol

The `AIChatCompletionServiceStreamable` protocol defines the interface for a chat completion service. It includes methods for:

- Creating messages (`createMessage(role:content:toolCalls:toolCallId:)`)
- Creating requests (`createRequest(messages:)`)
- Registering tools (`registerTools(_:)`)
- Completing a chat request via the unified streaming API (`completeStream(request:)`)

All providers must implement `completeStream`, which always returns an `AsyncThrowingStream<AIChatCompletionChunk, Error>`. This stream yields one or more chunks, depending on whether streaming is enabled for the provider and request.

### AIServiceManager

The `AIServiceManager` class provides a simplified way to manage multiple AI services. It includes methods for:

- Getting a service for a specific configuration (`getService(with:)`)
- Getting the current default service (`getCurrentService(context:)`)

The manager automatically detects the provider type based on the configuration and creates the appropriate service instance.

### Provider Implementations

The framework includes concrete implementations for popular AI service providers:

- `OpenAIService`: Integration with the OpenAI API
- `AnthropicService`: Integration with the Anthropic API
- `XAIService`: Integration with the x.ai API
- `DeepSeekService`: Integration with the DeepSeek API

Each provider implements the `AIService` protocol and provides its own types for models, requests, and responses. The XAI and DeepSeek services extend the OpenAI service implementation, sharing much of the same structure and behavior while adding provider-specific customizations. AnthropicService now supports both streaming and non-streaming completions via the unified `completeStream` method.

## Usage

To use the AIService framework:

1. Create an `APIConfigurationItem` with the necessary credentials and endpoints for your desired AI service provider.

2. Get an instance of the appropriate `AIService` using the `AIServiceManager`:

```swift
let config = APIConfigurationItem(...)
let service = AIServiceManager.shared.getService(with: config)
```

3. Interact with the service using the methods defined in the `AIService` and `AIChatCompletionService` protocols:

```swift
let models = try await service.fetchAvailableModels()
let parameters = service.getDefaultParameters()

let messages = [
    service.chat.createMessage(role: "system", content: "You are a helpful assistant.")
]
let request = service.chat.createRequest(messages: messages)
let response = try await service.chat.complete(request: request)
```

4. For completions (streaming or non-streaming), use the unified `completeStream` method, which always returns an `AsyncThrowingStream<AIChatCompletionChunk, Error>`:

```swift
let stream = service.chat.completeStream(request: request)
for try await chunk in stream {
    // Handle each chunk (content, tool calls, isFinal)
}
```

The `stream` parameter in the request determines whether the provider will stream the response or return a single chunk. All providers now use this unified interface.

5. Customize the behavior by providing different configurations or by implementing additional `AIService` conformances for new providers.

## Implementing New AIServices

To add support for a new AI service provider, follow these steps:

1. Create a new type that conforms to the `AIService` protocol. Implement the required methods and properties:

```swift
class MyAIService: AIService {
    // Implement fetchAvailableModels()
    func fetchAvailableModels() async throws -> [AIModel] { ... }
    
    // Implement getDefaultParameters()
    func getDefaultParameters() -> [AiRequestArgument] { ... }
    
    // Implement applyParameters(to:from:)
    func applyParameters(to request: Any, from parameters: [AiRequestArgument]) -> Any { ... }
    
    // Provide a chat completion service
    lazy var chat: AIChatCompletionService = MyAIChatService(service: self)
}
```

2. Define the associated types for your service:

```swift
class MyAIService: AIService {
    typealias MyAIModel = ...
    typealias MyAIChatCompletionRequest = ...
    typealias MyAIChatCompletionResponse = ...
    
    // ...
}
```

3. Implement a custom chat completion service that conforms to `AIChatCompletionService`:

```swift
class MyAIChatService: AIChatCompletionService {
    // Implement createMessage(role:content:toolCalls:toolCallId:)
    func createMessage(role: String, content: String, toolCalls: [AIToolCall]?, toolCallId: String?) -> AIChatMessage { ... }
    
    // Implement createRequest(messages:)
    func createRequest(messages: [AIChatMessage]) -> AIChatCompletionRequest { ... }
    
    // Implement complete(request:)
    func complete(request: AIChatCompletionRequest) async throws -> AIChatCompletionResponse { ... }
    
    // Implement completeStream(request:)
    func completeStream(request: AIChatCompletionRequest) -> AsyncThrowingStream<AIChatCompletionChunk, Error> { ... }
    
    // Implement registerTools(_:)
    func registerTools(_ tools: [AITool]) { ... }
}
```

4. Handle provider-specific authentication, API calls, and response parsing within your service implementation. All providers must implement the unified `completeStream` method for chat completions.

5. Register your new service with the `AIServiceManager`:

```swift
enum AIServiceProvider: String, CaseIterable {
    // ...
    case myAI = "MyAI"
    
    func createService(with config: APIConfigurationItem) -> AIService {
        switch self {
        // ...
        case .myAI:
            return MyAIService(configurationItem: config)
        }
    }
    
    static func detectProvider(from config: APIConfigurationItem) -> AIServiceProvider {
        // Update to detect your provider based on configuration
        // ...
    }
}
```

## Implementing AITools

To define custom tools for your AI service:

1. Create a struct representing your tool, conforming to the `Codable` protocol:

```swift
struct MyAITool: Codable {
    let type: String
    let function: MyAIFunction
}

struct MyAIFunction: Codable {
    let name: String
    let description: String
    let parameters: MyAIParameters
}

struct MyAIParameters: Codable {
    let type: String
    let properties: [String: MyAIProperty]
    let required: [String]?
}

struct MyAIProperty: Codable {
    let type: String
    let description: String
    // Add any additional properties
}
```

2. Register your tools with the chat completion service:

```swift
class MyAIChatService: AIChatCompletionService {
    // ...
    
    func registerTools(_ tools: [AITool]) {
        // Convert AITool to MyAITool and store
        // ...
    }
}
```

3. Handle tool calls within your chat completion implementation:

```swift
class MyAIChatService: AIChatCompletionService {
    // ...
    
    func complete(request: AIChatCompletionRequest) async throws -> AIChatCompletionResponse {
        // ...
        // Process tool calls and generate appropriate responses
        // ...
    }
}
```

Best practices:
- Ensure your service handles authentication securely and respects rate limits
- Validate and sanitize input parameters to prevent security vulnerabilities
- Provide clear error messages and handle edge cases gracefully
- Document any provider-specific quirks or limitations

By following these steps and adhering to the `AIService` and `AIChatCompletionService` protocols, you can seamlessly integrate new AI services and tools into the framework.

## Provider-Specific Implementations

The AIService framework includes concrete implementations for popular AI service providers. Each provider has its own set of files that define provider-specific types, request/response formats, and service implementations.

For example, the OpenAI integration is implemented in the following files:

- `OpenAIService.swift`: Defines the `OpenAIService` class that conforms to the `AIService` protocol and implements OpenAI-specific functionality.
- `OpenAIModel.swift`: Implements the `AIModel` protocol for OpenAI models.
- `OpenAICodableTypes.swift`: Contains the Codable types used for API interactions.
- `OpenAIDefaults.swift`: Defines default parameters and configurations.

Anthropic integration is implemented in:

- `AnthropicService.swift`: Defines the `AnthropicService` class and its chat service. As of the latest update, Anthropic supports both streaming and non-streaming completions via the unified `completeStream` method. The `stream` parameter is now available in `getDefaultParameters` for Anthropic, allowing users to toggle streaming mode. Tool calls are not yet supported for Anthropic, but the API is ready for future support.

Similar structures exist for other providers like x.ai and DeepSeek.

#### Comparing Provider Implementations

While the overall structure and approach is similar between different provider integrations, there are some key differences:

1. **Type Definitions**: Each implementation defines provider-specific types for models, requests, responses, tools, and parameters. The field names and structures may differ to match each provider's API.

2. **Inheritance vs. Independent Implementation**: Some providers (like XAI and DeepSeek) extend the OpenAI service implementation due to API similarities, while others (like Anthropic) have independent implementations.

3. **API Interaction**: Each service class handles the interaction with its respective API, including authentication, request construction, and response parsing.

4. **Default Parameters**: Provider-specific default parameters are defined in separate files (e.g., `OpenAIDefaults.swift`, `AnthropicDefaults.swift`).

Despite these differences, the provider implementations follow a consistent pattern:

1. Define provider-specific types
2. Implement the `AIService` protocol in a provider-specific service class
3. Create a custom chat service that conforms to `AIChatCompletionService`
4. Handle conversion between generic and provider-specific formats

## Common Types and Utilities

The AIService framework provides some generic implementations and utility extensions for common use cases:

- `GenericConfiguration`: A concrete implementation of the `AIServiceConfiguration` protocol for configuring AI services.
- `GenericChatMessage`, `GenericChatCompletionRequest`, `GenericChatCompletionResponse`: Generic implementations of the core chat-related protocols.
- Token counting utilities: Extension methods on `Array` of `AIChatMessage` for estimating token counts in conversations.

These common types and utilities can be used directly or as a starting point for custom implementations.

## Error Handling

The framework defines an `AIServiceError` enum that covers various error conditions:

- Network and connectivity issues
- Authentication failures
- API-specific errors
- Context limit exceeded errors
- Configuration problems

Each error type provides localized descriptions suitable for user-facing error messages.

## Application Data Model Integration

The AIService framework is designed to be independent from the application's data models. In vxAtelier Pro:

- `DialogItem`, `MessageItem`, etc. in `ItemModel.swift` are SwiftData models optimized for UI requirements
- These models are completely separate from the AI service types
- Conversion logic in `DialogItem` methods (like `createChatMessages()` and `createConfiguredRequest()`) transforms between internal models and service types
- This separation allows the UI to work with consistent data structures regardless of which AI provider is being used

When communicating with AI services:
1. Internal models (DialogItem → MessageItem) are converted to service protocol types (AIChatMessage)
2. Service protocol types are converted to provider-specific implementations
3. Responses follow the reverse path back to the UI

This architecture enables:
- Switching between different AI providers without UI changes
- Customizing the UI data model independently from API requirements
- Handling provider-specific features like tool calls in a consistent way

## Conclusion

The AIService framework provides a powerful abstraction layer for integrating AI services into an application. By leveraging protocols and a modular architecture, it enables seamless addition of new providers and easy switching between different services. 
