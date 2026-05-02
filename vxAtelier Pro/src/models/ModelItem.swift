import AVFoundation
import Foundation
import Observation
import SwiftData
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Represents an AI model with its capabilities and provider information.
///
/// This model stores information about AI models including:
/// - Base model name (e.g., "gpt-4", "claude-3")
/// - Context window size for token limits
/// - Provider identification (e.g., OpenAI, Anthropic)
/// - Capabilities the model supports (text generation, vision, etc.)
@Model
final class ModelItem {
    /// The name of the model (e.g., "gpt-4", "claude-3-opus")
    var name: String

    /// Maximum context size in tokens that this model supports
    var contextSize: Int

    /// The provider/company that created this model (e.g., "OpenAI", "Anthropic")
    var provider: String

    /// Array of capabilities this model supports (text, vision, etc.)
    var capabilities: [ModelCapability]

    var modelID: String
    var displayName: String
    var providerID: String
    var endpointFamiliesRaw: [String]
    var modalitiesRaw: [String]
    var supportedParameters: [String]
    var schemaFeaturesRaw: [String]
    var rawMetadataJSON: String?
    @Relationship(deleteRule: .cascade) var parameterMappings: [ModelParameterMappingItem] = []

    var descriptor: LLMModelDescriptor {
        get {
            LLMModelDescriptor(
                id: modelID,
                displayName: displayName,
                providerID: LLMProviderID(rawValue: providerID) ?? .customOpenAICompatible,
                contextWindow: contextSize,
                endpointFamilies: endpointFamiliesRaw.compactMap { LLMEndpointFamily(rawValue: $0) },
                modalities: modalitiesRaw.compactMap { LLMModality(rawValue: $0) },
                supportedParameters: supportedParameters,
                parameterMappings: parameterMappings.map(\.descriptor),
                schemaFeatures: schemaFeaturesRaw.compactMap { LLMSchemaFeature(rawValue: $0) },
                rawMetadataJSON: rawMetadataJSON
            )
        }
        set {
            modelID = newValue.id
            name = newValue.id
            displayName = newValue.displayName
            providerID = newValue.providerID.rawValue
            provider = newValue.providerID.displayName
            contextSize = newValue.contextWindow ?? AppDefaults.ModelContextSizes.defaultSize
            endpointFamiliesRaw = newValue.endpointFamilies.map(\.rawValue)
            modalitiesRaw = newValue.modalities.map(\.rawValue)
            supportedParameters = newValue.supportedParameters
            schemaFeaturesRaw = newValue.schemaFeatures.map(\.rawValue)
            rawMetadataJSON = newValue.rawMetadataJSON
            capabilities = Self.capabilities(from: newValue)
            LLMParameterMappingCatalog.materializeDefaults(on: self, preserveCustomized: true)
        }
    }

    /// Creates a new model item with the specified properties.
    ///
    /// - Parameters:
    ///   - name: The name of the model
    ///   - contextSize: Maximum context size in tokens, defaults to app's default size
    ///   - provider: The provider name, auto-detected from model name if nil
    init(
        name: String, contextSize: Int = AppDefaults.ModelContextSizes.defaultSize,
        provider: String? = nil
    ) {
        let resolvedProvider = provider ?? ModelProviderUtils.detectProvider(from: name)
        self.name = name
        self.modelID = name
        self.displayName = name
        self.contextSize = contextSize
        self.provider = resolvedProvider
        self.providerID = LLMProviderRegistry.providerID(fromProviderName: resolvedProvider).rawValue
        self.capabilities = []
        self.endpointFamiliesRaw = [LLMEndpointFamily.chatCompletions.rawValue]
        self.modalitiesRaw = [LLMModality.text.rawValue]
        self.supportedParameters = []
        self.schemaFeaturesRaw = [LLMSchemaFeature.streaming.rawValue]
        self.rawMetadataJSON = nil
        self.parameterMappings = []

        // Use the centralized utility method instead of our own implementation
        self.capabilities = ModelProviderUtils.inferCapabilities(from: name)
        LLMParameterMappingCatalog.materializeDefaults(on: self, preserveCustomized: true)
    }

    /// Checks if the model has a specific capability.
    ///
    /// - Parameter capability: The capability to check for
    /// - Returns: True if the model has this capability, false otherwise
    func hasCapability(_ capability: ModelCapability) -> Bool {
        return capabilities.contains(capability)
    }

    convenience init(descriptor: LLMModelDescriptor) {
        self.init(name: descriptor.id, contextSize: descriptor.contextWindow ?? AppDefaults.ModelContextSizes.defaultSize, provider: descriptor.providerID.displayName)
        self.descriptor = descriptor
    }

    private static func capabilities(from descriptor: LLMModelDescriptor) -> [ModelCapability] {
        var result: [ModelCapability] = []
        if descriptor.modalities.contains(.text) { result.append(.text) }
        if descriptor.modalities.contains(.image) { result.append(.vision) }
        if descriptor.modalities.contains(.audio) { result.append(.audio) }
        if descriptor.schemaFeatures.contains(.streaming) { result.append(.streaming) }
        if descriptor.schemaFeatures.contains(.tools) { result.append(.function) }
        if !result.contains(.chat) { result.append(.chat) }
        return result
    }
}
