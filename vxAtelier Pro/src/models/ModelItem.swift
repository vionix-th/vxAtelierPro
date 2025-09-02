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
        self.name = name
        self.contextSize = contextSize
        self.provider = provider ?? ModelProviderUtils.detectProvider(from: name)
        self.capabilities = []

        // Use the centralized utility method instead of our own implementation
        self.capabilities = ModelProviderUtils.inferCapabilities(from: name)
    }

    /// Checks if the model has a specific capability.
    ///
    /// - Parameter capability: The capability to check for
    /// - Returns: True if the model has this capability, false otherwise
    func hasCapability(_ capability: ModelCapability) -> Bool {
        return capabilities.contains(capability)
    }
} 