import Foundation

/// Configuration type for XAI service
typealias XAIConfiguration = GenericConfiguration

/// Request type for XAI chat completion
typealias XAIChatCompletionRequest = GenericChatCompletionRequest

/// Implements the XAI API service integration
class XAIService: OpenAIService {
    // MARK: - Properties

    override init(configuration: GenericConfiguration) {
        super.init(configuration: configuration)
        vxAtelierPro.log.info("Initialized with configuration")
    }

    convenience init(configurationItem: APIConfigurationItem) {
        vxAtelierPro.log.info("Initializing with configuration item")
        self.init(
            configuration: XAIConfiguration(
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
        var modelMap = Dictionary(uniqueKeysWithValues: XAIDefaults.defaultModels.map { ($0.id, $0) })
        
        do {
            // Fetch models from the API
            let url = try createURL(for: self.configuration.modelsEndpoint)
            let response = try await NetworkManager.shared.getRequest(
                url: url.absoluteString,
                apiKey: self.configuration.apiKey,
                responseType: XAICodableTypes.ModelsResponse.self
            )
            await vxAtelierPro.log.debug("XAIService: Successfully fetched \(response.data.count) models from API")
            
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
                
                let model = XAIModel(
                    id: modelId,
                    provider: ModelProviderUtils.Provider.xAI.rawValue,
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

    // Override to provide XAI-specific defaults
    override func getDefaultParameters() -> [AiRequestArgument] {
        // Get the parameters from the parent implementation
        let params = super.getDefaultParameters()

        // Find the model parameter and set the XAI default
        if let modelParam = params.first(where: { $0.name == "model" }) {
            modelParam.setValue(AppDefaults.XAI.model)
        } 

        // Update each parameter with XAI-specific defaults
        for param in params {
            switch param.name {
            case "temperature":
                param.setValue(AppDefaults.XAI.temperature)
            case "top_p":
                param.setValue(AppDefaults.XAI.top_p)
            case "max_tokens":
                param.setValue(AppDefaults.XAI.max_tokens)
            case "frequency_penalty":
                param.setValue(AppDefaults.XAI.frequency_penalty)
            case "presence_penalty":
                param.setValue(AppDefaults.XAI.presence_penalty)
            case "n":
                param.setValue(AppDefaults.XAI.n)
            case "stream":
                param.setValue(AppDefaults.XAI.stream)
            default:
                break
            }
        }

        vxAtelierPro.log.debug("Returning parameters with XAI defaults")
        return params
    }
}

// MARK: - Chat Completion Service

/// Handles chat completion requests for XAI
class XAIChatService: OpenAIChatService {
    private let service: XAIService

    init(service: XAIService) {
        self.service = service
        super.init(service: service)
    }
}
