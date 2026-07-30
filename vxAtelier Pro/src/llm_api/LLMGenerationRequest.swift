import Foundation

/// Fully resolved provider-neutral request ready for adapter encoding.
struct LLMGenerationRequest: Codable, Equatable {
    var providerID: LLMProviderID
    var adapterID: LLMAdapterID
    var modelID: String
    var activeParameters: [LLMActiveParameter]
    var messages: [LLMMessage]
    var tools: [LLMToolDefinition]
    var options: LLMGenerationOptions

    /// Creates a resolved request after runtime configuration has selected provider, adapter, and model.
    init(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        modelID: String,
        activeParameters: [LLMActiveParameter] = [],
        messages: [LLMMessage],
        tools: [LLMToolDefinition] = [],
        options: LLMGenerationOptions = LLMGenerationOptions()
    ) {
        self.providerID = providerID
        self.adapterID = adapterID
        self.modelID = modelID
        self.activeParameters = activeParameters
        self.messages = messages
        self.tools = tools
        self.options = options
    }

    func isParameterActive(_ parameterID: LLMParameterID) -> Bool {
        activeParameters.contains { $0.parameterID == parameterID }
    }

    func usesAdapterEncoding(_ parameterID: LLMParameterID) -> Bool {
        activeParameters.contains {
            $0.parameterID == parameterID && $0.mapping.encodingKind == .adapter
        }
    }

    func validateActiveParameterMappings() throws {
        var parameterIDs = Set<LLMParameterID>()
        for parameter in activeParameters {
            let mapping = parameter.mapping
            guard parameterIDs.insert(parameter.parameterID).inserted else {
                throw LLMProviderError.requestEncoding(
                    "Active parameter \(parameter.parameterID.rawValue) is duplicated."
                )
            }
            guard mapping.adapterID == adapterID,
                  mapping.parameterID == parameter.parameterID else {
                throw LLMProviderError.requestEncoding(
                    "Active parameter \(parameter.parameterID.rawValue) has a mismatched mapping identity."
                )
            }
            switch mapping.encodingKind {
            case .adapter:
                guard adapterID.ownsEncoding(of: parameter.parameterID) else {
                    throw LLMProviderError.requestEncoding(
                        "\(adapterID.displayName) has no adapter encoding for \(parameter.parameterID.rawValue)."
                    )
                }
            case .key:
                guard adapterID.supportsKeyParameterMappings,
                      !mapping.wireKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw LLMProviderError.requestEncoding(
                        "\(parameter.parameterID.rawValue) has no valid key mapping for \(adapterID.displayName)."
                    )
                }
            case .preset:
                guard let preset = mapping.structuredPreset,
                      preset.supports(adapterID) else {
                    throw LLMProviderError.requestEncoding(
                        "\(parameter.parameterID.rawValue) has no valid preset mapping for \(adapterID.displayName)."
                    )
                }
            }
        }
    }
}

/// Provider-neutral events emitted by adapters for streamed and complete responses.
enum LLMGenerationEvent: Equatable {
    case generationStarted(requestID: String?)
    case responseMetadata(LLMResponseMetadata)
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallDelta(LLMToolCall)
    case toolCallCompleted(LLMToolCall)
    case toolOutputCompleted(LLMToolOutput)
    case usage(LLMUsage)
    case generationCompleted(responseID: String?, modelID: String?)
}
