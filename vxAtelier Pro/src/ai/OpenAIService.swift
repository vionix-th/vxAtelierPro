import Foundation

/// Configuration type for OpenAI service
typealias OpenAIConfiguration = GenericConfiguration

/// Request type for OpenAI chat completion
typealias OpenAIChatCompletionRequest = GenericChatCompletionRequest

/// Implements the OpenAI API service integration
class OpenAIService: AIService {
    // MARK: - Properties
    
    let configuration: OpenAIConfiguration
    lazy var chat: AIChatCompletionServiceStreamable = OpenAIChatService(service: self)
    
    init(configuration: OpenAIConfiguration) {
        self.configuration = configuration
        vxAtelierPro.log.debug("Initialized with configuration")
    }
    
    convenience init(configurationItem: APIConfigurationItem) {
        vxAtelierPro.log.debug("Initializing with configuration item")
        self.init(configuration: OpenAIConfiguration(
            apiKey: configurationItem.apiKey,
            baseURL: configurationItem.baseURL,
            chatCompletionsEndpoint: configurationItem.chatCompletionsEndpoint,
            modelsEndpoint: configurationItem.modelsEndpoint
        ))
    }
    
    // MARK: - URL Helpers
    
    public func createURL(for endpoint: String) throws -> URL {
        vxAtelierPro.log.debug("Creating URL for endpoint: \(endpoint)")
        guard let baseURL = URL(string: configuration.baseURL),
              let url = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)?
                .appendingPath(endpoint)
                .url
        else {
            vxAtelierPro.log.error("Failed to create URL for endpoint: \(endpoint)")
            throw AIServiceError.invalidURL
        }
        return url
    }
    
    // MARK: - AIService Implementation
    
    func fetchAvailableModels() async throws -> [AIModel] {
        await vxAtelierPro.log.info("Fetching available models")
        
        // Start with default models as the base
        var modelMap = Dictionary(uniqueKeysWithValues: OpenAIDefaults.defaultModels.map { ($0.id, $0) })
        
        do {
            // Fetch models from the API
            let url = try createURL(for: self.configuration.modelsEndpoint)
            let response = try await NetworkManager.shared.getRequest(
                url: url.absoluteString,
                apiKey: self.configuration.apiKey,
                responseType: OpenAICodableTypes.ModelsResponse.self
            )
            await vxAtelierPro.log.debug("OpenAIService: Successfully fetched \(response.data.count) models from API")
            
            // Process API models and merge with defaults
            for modelData in response.data {
                let modelId = modelData.id
                
                // If we already have this model in defaults, keep it
                if modelMap[modelId] != nil {
                    continue
                }
                
                // Otherwise create a new model entry
                let capabilities = ModelProviderUtils.inferCapabilities(from: modelId)
                // Use default fallback size for unknown models
                let contextSize = AppDefaults.ModelContextSizes.defaultSize
                
                let model = OpenAIModel(
                    id: modelId,
                    provider: ModelProviderUtils.Provider.openAI.rawValue,
                    capabilities: capabilities,
                    contextSize: contextSize
                )
                
                modelMap[modelId] = model
            }
        } catch {
            await vxAtelierPro.log.warning("Failed to fetch models from API: \(error.localizedDescription). Using default models.")
        }
        
        return Array(modelMap.values)
    }
    
    func getDefaultParameters() -> [AiRequestArgument] {
        vxAtelierPro.log.debug("Getting default parameters")
        let temperatureParam = AiRequestArgument(
            name: "temperature",
            displayName: "Temperature",
            description: "Controls randomness: lowering results in less random completions",
            required: false,
            valueType: .float,
            controlType: .slider,
            minValue: 0.0,
            maxValue: 2.0,
            step: 0.1
        )
        temperatureParam.setValue(AppDefaults.OpenAi.temperature)
        
        let topPParam = AiRequestArgument(
            name: "top_p",
            displayName: "Top P",
            description: "Controls diversity via nucleus sampling",
            required: false,
            valueType: .float,
            controlType: .slider,
            minValue: 0.0,
            maxValue: 1.0,
            step: 0.05
        )
        topPParam.setValue(AppDefaults.OpenAi.top_p)
        
        let maxTokensParam = AiRequestArgument(
            name: "max_tokens",
            displayName: "Max Tokens",
            description: "Maximum number of tokens to generate",
            required: false,
            valueType: .integer,
            controlType: .stepper,
            minValue: 32,
            maxValue: Double(Int.max),
            step: 16
        )
        maxTokensParam.setValue(AppDefaults.OpenAi.max_tokens)
        
        let frequencyPenaltyParam = AiRequestArgument(
            name: "frequency_penalty",
            displayName: "Frequency Penalty",
            description: "Decreases likelihood of repeating the same tokens",
            required: false,
            valueType: .float,
            controlType: .slider,
            minValue: -2.0,
            maxValue: 2.0,
            step: 0.1
        )
        frequencyPenaltyParam.setValue(AppDefaults.OpenAi.frequency_penalty)
        
        let presencePenaltyParam = AiRequestArgument(
            name: "presence_penalty",
            displayName: "Presence Penalty",
            description: "Decreases likelihood of repeating any token used so far",
            required: false,
            valueType: .float,
            controlType: .slider,
            minValue: -2.0,
            maxValue: 2.0,
            step: 0.1
        )
        presencePenaltyParam.setValue(AppDefaults.OpenAi.presence_penalty)
        
        let seedParam = AiRequestArgument(
            name: "seed",
            displayName: "Seed",
            description: "Random number seed for deterministic results",
            required: false,
            valueType: .integer,
            controlType: .textField,
            minValue: 0.0,
            maxValue: Double(Int.max)
        )
        seedParam.setValue(0)
        
        let nParam = AiRequestArgument(
            name: "n",
            displayName: "N",
            description: "Number of response alternatives to generate",
            required: false,
            valueType: .integer,
            controlType: .stepper,
            minValue: 1,
            maxValue: 5,
            step: 1
        )
        nParam.setValue(AppDefaults.OpenAi.n)
        
        let streamParam = AiRequestArgument(
            name: "stream",
            displayName: "Stream",
            description: "Stream the response",
            required: false,
            valueType: .boolean,
            controlType: .toggle
        )
        streamParam.setValue(AppDefaults.OpenAi.stream)

        let responseFormatParam = AiRequestArgument(
            name: "response_format",
            displayName: "Response Format",
            description: "Format for model responses (text or JSON)",
            required: false,
            valueType: .string,
            controlType: .picker,
            options: ["text", "json_object"]
        )
        responseFormatParam.setValue("text")

        let modelParam = AiRequestArgument(
            name: "model",
            displayName: "Model",
            description: "The model to use for this conversation",
            required: true,
            valueType: .string,
            controlType: .textField // Or Picker if a list were available
        )
        modelParam.setValue(AppDefaults.OpenAi.model) // Set default model

        return [
            modelParam, // Add model param to the list
            temperatureParam,
            topPParam,
            maxTokensParam,
            frequencyPenaltyParam,
            presencePenaltyParam,
            seedParam,
            nParam,
            streamParam,
            responseFormatParam
        ]
    }
    
    func applyParameters(to request: Any, from parameters: [AiRequestArgument]) -> Any {
        guard let genericRequest = request as? GenericChatCompletionRequest else {
            return request
        }
        
        var modifiedRequest = genericRequest
        
        for param in parameters {
            if param.isEnabled {                        
                if let value = param.value {
                    modifiedRequest.setParameter(name: param.name, value: value)
                }
            }
        }
        
        return modifiedRequest
    }
}

// MARK: - Chat Completion Service

/// Handles chat completion requests for OpenAI
class OpenAIChatService: AIChatCompletionServiceStreamable {
    private let service: OpenAIService
    var configuration: Any { service.configuration }
    private(set) var availableTools: [AITool] = []
    
    init(service: OpenAIService) {
        self.service = service
    }
    
    func createMessage(role: String, content: String, toolCalls: [AIToolCall]? = nil, toolCallId: String? = nil) -> AIChatMessage {
        struct Message: AIChatMessage {
            let role: String
            let content: String
            let toolCalls: [AIToolCall]?
            let toolCallId: String?
        }
        return Message(role: role, content: content, toolCalls: toolCalls, toolCallId: toolCallId)
    }
    
    func createRequest(messages: [AIChatMessage]) -> AIChatCompletionRequest {
        return GenericChatCompletionRequest(
            messages: messages,
            tools: availableTools.isEmpty ? nil : availableTools,
            toolChoice: availableTools.isEmpty ? nil : "auto"
        )
    }
    
    func registerTools(_ tools: [AITool]) {
        self.availableTools = tools
    }
    
    // Helper method to convert generic messages to OpenAI format
    private func convertToOpenAIMessages(_ messages: [AIChatMessage]) -> [OpenAICodableTypes.Message] {
        return messages.map { message in
            OpenAICodableTypes.Message(
                role: message.role,
                content: message.content,
                tool_calls: message.toolCalls?.map { toolCall in
                    OpenAICodableTypes.ToolCall(
                        id: toolCall.id,
                        type: "function",
                        function: OpenAICodableTypes.FunctionCall(
                            name: toolCall.name, 
                            arguments: toolCall.arguments
                        )
                    )
                },
                tool_call_id: message.toolCallId
            )
        }
    }
    
    // Helper method to prepare the OpenAI request with all parameters
    private func prepareOpenAIRequest(_ request: AIChatCompletionRequest, streaming: Bool = false) throws -> OpenAICodableTypes.ChatRequest {
        guard let model = request.getParameter("model") as? String, !model.isEmpty else {
            throw AIServiceError.invalidConfiguration
        }
        var messagesForAPI: [OpenAICodableTypes.Message] = []
        let systemPromptValue = request.getParameter("system_prompt") as? String
        if let prompt = systemPromptValue, !prompt.isEmpty {
            messagesForAPI.append(OpenAICodableTypes.Message(
                role: "system", 
                content: prompt,
                tool_calls: nil,
                tool_call_id: nil
            ))
        }
        messagesForAPI.append(contentsOf: convertToOpenAIMessages(request.messages))
        var openAIRequest = OpenAICodableTypes.ChatRequest(
            model: model,
            messages: messagesForAPI
        )
        if streaming {
            openAIRequest.stream = true
        }
        for (name, value) in request.getAllParameters() {
            switch name {
            case "model", "system_prompt": break
            case "temperature":
                openAIRequest.temperature = value as? Double
            case "max_tokens":
                openAIRequest.max_tokens = value as? Int
            case "top_p":
                openAIRequest.top_p = value as? Double
            case "frequency_penalty":
                openAIRequest.frequency_penalty = value as? Double
            case "presence_penalty":
                openAIRequest.presence_penalty = value as? Double
            case "n":
                openAIRequest.n = value as? Int
            case "seed":
                openAIRequest.seed = value as? Int
            case "response_format":
                if let format = value as? String {
                    openAIRequest.response_format = OpenAICodableTypes.ChatRequest.ResponseFormat(type: format)
                }
            default:
                break
            }
        }
        if let tools = request.tools, !tools.isEmpty {
            openAIRequest.tools = tools.map { tool in
                OpenAICodableTypes.Tool(
                    type: "function",
                    function: OpenAICodableTypes.Function(
                        name: tool.name,
                        description: tool.description,
                        parameters: OpenAICodableTypes.Parameters(
                            type: tool.parameters.type,
                            properties: Dictionary(uniqueKeysWithValues: tool.parameters.properties.map { key, value in
                                (key, OpenAICodableTypes.Property(
                                    type: value.type,
                                    description: value.description,
                                    enumValues: (value as? GenericToolProperty)?.enumValues
                                ))
                            }),
                            required: tool.parameters.required
                        )
                    )
                )
            }
            if let toolChoice = request.getParameter("tool_choice") as? String {
                switch toolChoice {
                case "required":
                    openAIRequest.tool_choice = .required
                case "auto":
                    openAIRequest.tool_choice = .auto
                default:
                    openAIRequest.tool_choice = .auto
                }
            } else {
                openAIRequest.tool_choice = .auto
            }
        }
        return openAIRequest
    }

    // Unified streaming/non-streaming completion method
    func completeStream(request: AIChatCompletionRequest) -> AsyncThrowingStream<AIChatCompletionChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Determine if streaming is enabled
                    let streamParam = request.getParameter("stream") as? Bool ?? false
                    if streamParam {
                        // Streaming mode
                        let openAIRequest = try prepareOpenAIRequest(request, streaming: true)
                        let url = try service.createURL(for: service.configuration.chatCompletionsEndpoint)
                        let requestDict = openAIRequest.asDictionary()
                        var accumulatedContent = ""
                        var accumulatedToolCalls: [GenericToolCall] = []
                        await NetworkManager.shared.streamRequest(
                            url: url.absoluteString,
                            body: requestDict,
                            apiKey: service.configuration.apiKey,
                            chunkProcessor: { json async in
                                if let choices = json["choices"] as? [[String: Any]],
                                   let firstChoice = choices.first,
                                   let delta = firstChoice["delta"] as? [String: Any] {
                                    var chunkContent: String? = nil
                                    var chunkToolCalls: [AIToolCall]? = nil
                                    // Handle text content
                                    if let content = delta["content"] as? String, !content.isEmpty {
                                        accumulatedContent += content
                                        chunkContent = content
                                    }
                                    // Handle tool calls
                                    if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                                        for toolCallData in toolCalls {
                                            guard let id = toolCallData["id"] as? String else { continue }
                                            let name = (toolCallData["function"] as? [String: Any])?["name"] as? String ?? ""
                                            let arguments = (toolCallData["function"] as? [String: Any])?["arguments"] as? String ?? ""
                                            let toolCall = GenericToolCall(id: id, name: name, arguments: arguments)
                                            // Update or append
                                            if let idx = accumulatedToolCalls.firstIndex(where: { $0.id == id }) {
                                                var updated = accumulatedToolCalls[idx]
                                                updated = GenericToolCall(
                                                    id: updated.id,
                                                    name: updated.name.isEmpty ? name : updated.name,
                                                    arguments: updated.arguments + arguments
                                                )
                                                accumulatedToolCalls[idx] = updated
                                            } else {
                                                accumulatedToolCalls.append(toolCall)
                                            }
                                        }
                                        chunkToolCalls = accumulatedToolCalls
                                    }
                                    // Yield chunk if any content or tool calls
                                    if chunkContent != nil || chunkToolCalls != nil {
                                        continuation.yield(AIChatCompletionChunk(content: chunkContent, toolCalls: chunkToolCalls, isFinal: false))
                                    }
                                    // Check for finish_reason
                                    if let finishReason = firstChoice["finish_reason"] as? String, finishReason == "stop" || finishReason == "tool_calls" {
                                        continuation.yield(AIChatCompletionChunk(content: nil, toolCalls: nil, isFinal: true))
                                        continuation.finish()
                                    }
                                }
                            },
                            completionHandler: {
                                continuation.yield(AIChatCompletionChunk(content: nil, toolCalls: nil, isFinal: true))
                                continuation.finish()
                            },
                            errorHandler: { error in
                                continuation.finish(throwing: error)
                            }
                        )
                    } else {
                        // Non-streaming mode
                        let openAIRequest = try prepareOpenAIRequest(request, streaming: false)
                        let url = try service.createURL(for: service.configuration.chatCompletionsEndpoint)
                        let response: OpenAICodableTypes.ChatResponse = try await NetworkManager.shared.postRequest(
                            url: url.absoluteString,
                            body: openAIRequest.asDictionary(),
                            responseType: OpenAICodableTypes.ChatResponse.self,
                            apiKey: service.configuration.apiKey
                        )
                        let message = response.choices[0].message
                        let toolCalls = message.tool_calls?.map { toolCall in
                            GenericToolCall(
                                id: toolCall.id,
                                name: toolCall.function.name,
                                arguments: toolCall.function.arguments
                            )
                        }
                        continuation.yield(AIChatCompletionChunk(content: message.content, toolCalls: toolCalls, isFinal: true))
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}



