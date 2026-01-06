import Foundation

/// Configuration type for DeepSeek service
typealias DeepSeekConfiguration = GenericConfiguration

/// Request type for DeepSeek chat completion
typealias DeepSeekChatCompletionRequest = GenericChatCompletionRequest

/// Implements the DeepSeek API service integration
class DeepSeekService: OpenAIService {
    // MARK: - Properties

    override init(configuration: GenericConfiguration) {
        super.init(configuration: configuration)
        vxAtelierPro.log.info("Initialized with configuration")
    }

    convenience init(configurationItem: APIConfigurationItem) {
        vxAtelierPro.log.info("Initializing with configuration item")
        self.init(
            configuration: DeepSeekConfiguration(
                apiKey: configurationItem.apiKey,
                baseURL: configurationItem.baseURL,
                chatCompletionsEndpoint: configurationItem.chatCompletionsEndpoint,
                modelsEndpoint: configurationItem.modelsEndpoint
            ))
    }

    // MARK: - AIService Implementation

    override func fetchAvailableModels() async throws -> [AIModel] {
        await vxAtelierPro.log.info("Fetching available models")

        // Start with default models as the base
        var modelMap = Dictionary(
            uniqueKeysWithValues: getDefaultModels().map { ($0.id, $0) })

        // Fetch models from the API
        let url = try createURL(for: self.configuration.modelsEndpoint)
        let response = try await NetworkManager.shared.getRequest(
            url: url.absoluteString,
            apiKey: self.configuration.apiKey,
            responseType: DeepSeekCodableTypes.ModelsResponse.self
        )
        await vxAtelierPro.log.debug(
            "DeepSeekService: Successfully fetched \(response.data.count) models from API")

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

            let model = DeepSeekModel(
                id: modelId,
                provider: ModelProviderUtils.Provider.deepSeek.rawValue,
                capabilities: capabilities,
                contextSize: contextSize
            )

            modelMap[modelId] = model
        }

        return Array(modelMap.values)
    }

    override func getDefaultModels() -> [AIModel] {
        DeepSeekDefaults.defaultModels
    }

    // Override to provide DeepSeek-specific defaults
    override func getDefaultParameters() -> [AiRequestArgument] {
        // Get the parameters from the parent implementation
        let params = super.getDefaultParameters()

        // Find the model parameter and set the DeepSeek default
        if let modelParam = params.first(where: { $0.name == "model" }) {
            modelParam.setValue(AppDefaults.DeepSeek.model)
        }

        // Update each parameter with DeepSeek-specific defaults
        for param in params {
            switch param.name {
            case "temperature":
                param.setValue(AppDefaults.DeepSeek.temperature)
            case "top_p":
                param.setValue(AppDefaults.DeepSeek.top_p)
            case "max_tokens":
                param.setValue(AppDefaults.DeepSeek.max_tokens)
            case "frequency_penalty":
                param.setValue(AppDefaults.DeepSeek.frequency_penalty)
            case "presence_penalty":
                param.setValue(AppDefaults.DeepSeek.presence_penalty)
            case "stream":
                param.setValue(AppDefaults.DeepSeek.stream)
            default:
                break
            }
        }

        vxAtelierPro.log.debug("Returning parameters with DeepSeek defaults")
        return params
    }
}

// MARK: - Chat Completion Service

/// Handles chat completion requests for DeepSeek
class DeepSeekChatService: OpenAIChatService {
    private let service: DeepSeekService

    init(service: DeepSeekService) {
        self.service = service
        super.init(service: service)
    }
}
