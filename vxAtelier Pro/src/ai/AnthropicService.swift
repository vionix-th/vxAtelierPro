import Foundation

/// Configuration type for Anthropic service
typealias AnthropicConfiguration = GenericConfiguration

/// Request type for Anthropic chat completion
typealias AnthropicChatCompletionRequest = GenericChatCompletionRequest

/// Implements the Anthropic API service integration
class AnthropicService: AIService {
    // MARK: - Properties

    let configuration: AnthropicConfiguration
    lazy var chat: AIChatCompletionServiceStreamable = AnthropicChatService(service: self)

    init(configuration: AnthropicConfiguration) {
        self.configuration = configuration
        vxAtelierPro.log.debug("Initialized with configuration")
    }

    convenience init(configurationItem: APIConfigurationItem) {
        vxAtelierPro.log.debug("Initializing with configuration item")
        self.init(
            configuration: AnthropicConfiguration(
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
        var modelMap = Dictionary(
            uniqueKeysWithValues: AnthropicDefaults.defaultModels.map { ($0.id, $0) })

        do {
            let headers = [
                "x-api-key": "\(configuration.apiKey)",
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
            ]
            // Fetch models from the API
            let url = try createURL(for: self.configuration.modelsEndpoint)
            let response = try await NetworkManager.shared.getRequest(
                url: url.absoluteString,                
                headers: headers,
                responseType: AnthropicCodableTypes.ModelsResponse.self
            )
            await vxAtelierPro.log.debug(
                "AnthropicService: Successfully fetched \(response.data.count) models from API")

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

                let model = AnthropicModel(
                    id: modelId,
                    provider: ModelProviderUtils.Provider.anthropic.rawValue,
                    capabilities: capabilities,
                    contextSize: contextSize
                )

                modelMap[modelId] = model
            }
        } catch {
            await vxAtelierPro.log.warning(
                "Failed to fetch models from API: \(error.localizedDescription). Using default models."
            )
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
            maxValue: 1.0,
            step: 0.05
        )
        temperatureParam.setValue(AppDefaults.Anthropic.temperature)

        let maxTokensParam = AiRequestArgument(
            name: "max_tokens",
            displayName: "Max Tokens",
            description: "Maximum number of tokens to generate",
            required: true,
            valueType: .integer,
            controlType: .stepper,
            minValue: 32,
            maxValue: Double(Int.max),
            step: 16
        )
        maxTokensParam.setValue(AppDefaults.Anthropic.max_tokens)

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
        topPParam.setValue(AppDefaults.Anthropic.top_p)

        let topKParam = AiRequestArgument(
            name: "top_k",
            displayName: "Top K",
            description: "Controls diversity by limiting to k most likely tokens",
            required: false,
            valueType: .integer,
            controlType: .stepper,
            minValue: 1,
            maxValue: 500,
            step: 1
        )
        topKParam.setValue(AppDefaults.Anthropic.top_k)

        let stopSequencesParam = AiRequestArgument(
            name: "stop_sequences",
            displayName: "Stop Sequences",
            description: "Sequences that trigger early stopping (comma-separated)",
            required: false,
            valueType: .string,
            controlType: .textField
        )
        stopSequencesParam.setValue("")

        let modelParam = AiRequestArgument(
            name: "model",
            displayName: "Model",
            description: "The model to use for this conversation",
            required: true,
            valueType: .string,
            controlType: .textField
        )
        modelParam.setValue(AppDefaults.Anthropic.model)

        let streamParam = AiRequestArgument(
            name: "stream",
            displayName: "Stream",
            description: "Stream the response",
            required: false,
            valueType: .boolean,
            controlType: .toggle
        )
        streamParam.setValue(AppDefaults.OpenAi.stream)

        return [
            modelParam,
            temperatureParam,
            topPParam,
            topKParam,
            maxTokensParam,
            stopSequencesParam,
            streamParam
        ]
    }

    func applyParameters(to request: Any, from parameters: [AiRequestArgument]) -> Any {
        guard let genericRequest = request as? GenericChatCompletionRequest else {
            return request
        }

        var modifiedRequest = genericRequest

        for param in parameters {
            if !param.isEnabled { continue }

            if let value = param.value {
                modifiedRequest.setParameter(name: param.name, value: value)
            }
        }

        return modifiedRequest
    }
}

// MARK: - Chat Completion Service

/// Handles chat completion requests for Anthropic
class AnthropicChatService: AIChatCompletionServiceStreamable {
    private let service: AnthropicService
    var configuration: Any { service.configuration }
    private(set) var availableTools: [AITool] = []

    init(service: AnthropicService) {
        self.service = service
    }

    func createMessage(
        role: String, content: String, toolCalls: [AIToolCall]? = nil, toolCallId: String? = nil
    ) -> AIChatMessage {
        GenericChatMessage(
            role: role, content: content, toolCalls: toolCalls, toolCallId: toolCallId)
    }

    func createRequest(messages: [AIChatMessage]) -> AIChatCompletionRequest {
        return GenericChatCompletionRequest(
            messages: messages, tools: availableTools, toolChoice: "auto")
    }

    func registerTools(_ tools: [AITool]) {
        self.availableTools = tools
    }

    func completeStream(request: AIChatCompletionRequest) -> AsyncThrowingStream<AIChatCompletionChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // 1. Prepare Anthropic API request body
                    guard let model = request.getParameter("model") as? String, !model.isEmpty else {
                        throw AIServiceError.invalidConfiguration
                    }
                    let temperature = request.getParameter("temperature") as? Double ?? AppDefaults.Anthropic.temperature
                    let maxTokens = request.getParameter("max_tokens") as? Int ?? AppDefaults.Anthropic.max_tokens
                    let topP = request.getParameter("top_p") as? Double
                    let topK = request.getParameter("top_k") as? Int
                    let stopSequences = request.getParameter("stop_sequences") as? String
                    let streamParam = request.getParameter("stream") as? Bool ?? false

                    // Anthropic expects messages as [{role, content}]
                    let messagesForAPI: [[String: Any]] = request.messages.map { msg in
                        [
                            "role": msg.role,
                            "content": msg.content
                        ]
                    }

                    var anthropicRequest: [String: Any] = [
                        "model": model,
                        "messages": messagesForAPI,
                        "max_tokens": maxTokens,
                        "temperature": temperature,
                        "stream": streamParam
                    ]
                    if let topP = topP { anthropicRequest["top_p"] = topP }
                    if let topK = topK { anthropicRequest["top_k"] = topK }
                    if let stopSequences = stopSequences, !stopSequences.isEmpty {
                        anthropicRequest["stop_sequences"] = stopSequences.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    }

                    let url = try service.createURL(for: service.configuration.chatCompletionsEndpoint)
                    let headers = [
                        "x-api-key": service.configuration.apiKey,
                        "anthropic-version": "2023-06-01",
                        "Content-Type": "application/json"
                    ]

                    if streamParam {
                        // Streaming mode: parse SSE events
                        var accumulatedContent = ""
                        await NetworkManager.shared.streamRequest(
                            url: url.absoluteString,
                            body: anthropicRequest,
                            headers: headers,
                            chunkProcessor: { json async in
                                // Anthropic SSE events: look for content_block_delta and message_stop
                                if let type = json["type"] as? String {
                                    switch type {
                                    case "content_block_delta":
                                        if let delta = json["delta"] as? [String: Any],
                                           let text = delta["text"] as? String {
                                            accumulatedContent += text
                                            continuation.yield(AIChatCompletionChunk(content: text, toolCalls: nil, isFinal: false))
                                        }
                                    case "message_stop":
                                        continuation.yield(AIChatCompletionChunk(content: nil, toolCalls: nil, isFinal: true))
                                        continuation.finish()
                                    default:
                                        break // Ignore other event types for now
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
                        // Non-streaming mode: single POST request
                        struct AnthropicChatResponse: Decodable {
                            let content: [AnthropicContentBlock]
                        }
                        struct AnthropicContentBlock: Decodable {
                            let type: String
                            let text: String?
                        }
                        let response: AnthropicChatResponse = try await NetworkManager.shared.postRequest(
                            url: url.absoluteString,
                            body: anthropicRequest,
                            responseType: AnthropicChatResponse.self,
                            headers: headers
                        )
                        // Concatenate all text blocks
                        let content = response.content.compactMap { $0.text }.joined()
                        continuation.yield(AIChatCompletionChunk(content: content, toolCalls: nil, isFinal: true))
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
