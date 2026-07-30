import Foundation

enum LLMModelCapability: String, Codable, CaseIterable, Identifiable {
    case text
    case image
    case audio
    case file
    case video
    case tools
    case strictTools
    case jsonSchema
    case jsonObject
    case reasoning
    case usage
    case streaming

    var id: String { rawValue }

    var kind: Kind {
        switch self {
        case .text, .image, .audio, .file, .video:
            return .content
        case .tools, .strictTools, .jsonSchema, .jsonObject, .reasoning, .usage, .streaming:
            return .feature
        }
    }

    enum Kind {
        case content
        case feature
    }
}

enum LLMSupportState: String, Codable, CaseIterable {
    case supported
    case unsupported
    case unknown
}

enum LLMMetadataSource: String, Codable {
    case catalog
    case provider
    case userOverride
    case fallback
}

struct LLMSupport: Codable, Equatable {
    var state: LLMSupportState
    var source: LLMMetadataSource
}

struct LLMCapabilityClaim: Codable, Equatable, Identifiable {
    var id: LLMModelCapability { capability }
    var capability: LLMModelCapability
    var state: LLMSupportState
}

struct LLMParameterSupportClaim: Codable, Equatable, Identifiable {
    var id: LLMParameterID { parameterID }
    var parameterID: LLMParameterID
    var state: LLMSupportState
}

struct LLMProviderModelMetadata: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String?
    var providerID: LLMProviderID
    var contextSize: Int?
    var capabilityClaims: [LLMCapabilityClaim]
    var parameterSupportClaims: [LLMParameterSupportClaim]
    var rawMetadataJSON: String?

    init(
        id: String,
        displayName: String? = nil,
        providerID: LLMProviderID,
        contextSize: Int? = nil,
        capabilityClaims: [LLMCapabilityClaim] = [],
        parameterSupportClaims: [LLMParameterSupportClaim] = [],
        rawMetadataJSON: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.providerID = providerID
        self.contextSize = contextSize
        self.capabilityClaims = capabilityClaims
        self.parameterSupportClaims = parameterSupportClaims
        self.rawMetadataJSON = rawMetadataJSON
    }
}

struct LLMModelOverrides: Equatable {
    var displayName: String?
    var contextSize: Int?
    var capabilitySupport: [LLMModelCapability: LLMSupportState]
    var parameterOverrides: [LLMParameterID: LLMParameterOverrides]

    init(
        displayName: String? = nil,
        contextSize: Int? = nil,
        capabilitySupport: [LLMModelCapability: LLMSupportState] = [:],
        parameterOverrides: [LLMParameterID: LLMParameterOverrides] = [:]
    ) {
        self.displayName = displayName
        self.contextSize = contextSize
        self.capabilitySupport = capabilitySupport
        self.parameterOverrides = parameterOverrides
    }
}

enum LLMDefaultValueOverride: Equatable {
    case inherit
    case value(JSONValue)
    case none
}

enum LLMOptionsOverride: Equatable {
    case inherit
    case value([String])
    case none
}

struct LLMParameterOverrides: Equatable {
    var support: LLMSupportState?
    var mapping: LLMParameterMapping?
    var isRequired: Bool?
    var isEnabledByDefault: Bool?
    var defaultValue: LLMDefaultValueOverride
    var options: LLMOptionsOverride

    init(
        support: LLMSupportState? = nil,
        mapping: LLMParameterMapping? = nil,
        isRequired: Bool? = nil,
        isEnabledByDefault: Bool? = nil,
        defaultValue: LLMDefaultValueOverride = .inherit,
        options: LLMOptionsOverride = .inherit
    ) {
        self.support = support
        self.mapping = mapping
        self.isRequired = isRequired
        self.isEnabledByDefault = isEnabledByDefault
        self.defaultValue = defaultValue
        self.options = options
    }
}

struct LLMParameterProfile: Equatable, Identifiable {
    var id: LLMParameterID { parameterID }
    var parameterID: LLMParameterID
    var support: LLMSupport
    var mapping: LLMParameterMapping?
    var mappingSource: LLMMetadataSource?
    var isRequired: Bool
    var isEnabledByDefault: Bool
    var defaultValue: JSONValue?
    var options: [String]?
}

struct LLMModelProfile: Equatable, Identifiable {
    var id: String { modelID }
    var modelID: String
    var providerID: LLMProviderID
    var adapterID: LLMAdapterID
    var displayName: String
    var displayNameSource: LLMMetadataSource
    var contextSize: Int
    var contextSizeSource: LLMMetadataSource
    var capabilities: [LLMModelCapability: LLMSupport]
    var parameters: [LLMParameterID: LLMParameterProfile]

    var supportedCapabilities: [LLMModelCapability] {
        LLMModelCapability.allCases.filter { capabilities[$0]?.state == .supported }
    }
}

struct LLMModelProfileResolver {
    var defaultsCatalog: LLMDefaultsCatalog
    var fallbackContextSize: Int

    init(defaultsCatalog: LLMDefaultsCatalog = .bundled, fallbackContextSize: Int) {
        self.defaultsCatalog = defaultsCatalog
        self.fallbackContextSize = fallbackContextSize
    }

    func defaultModelID(
        for providerID: LLMProviderID,
        configuredModelID: String? = nil
    ) -> String? {
        let configured = configuredModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured.isEmpty ? defaultsCatalog.defaultModelID(for: providerID) : configured
    }

    func resolve(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        modelID: String,
        metadata: LLMProviderModelMetadata?,
        overrides: LLMModelOverrides = LLMModelOverrides()
    ) -> LLMModelProfile {
        let modelDefaults = defaultsCatalog.modelDefaults(
            providerID: providerID,
            adapterID: adapterID,
            modelID: modelID
        )
        let catalogParameters = defaultsCatalog.parameterDefaults(
            providerID: providerID,
            adapterID: adapterID,
            modelID: modelID
        )

        let display: (String, LLMMetadataSource)
        if let override = normalized(overrides.displayName) {
            display = (override, .userOverride)
        } else if let observed = normalized(metadata?.displayName) {
            display = (observed, .provider)
        } else {
            display = (modelID, .fallback)
        }

        let context: (Int, LLMMetadataSource)
        if let override = overrides.contextSize {
            context = (override, .userOverride)
        } else if let observed = metadata?.contextSize {
            context = (observed, .provider)
        } else if let catalog = modelDefaults?.contextSize {
            context = (catalog, .catalog)
        } else {
            context = (fallbackContextSize, .fallback)
        }

        let catalogCapabilities = Set(modelDefaults?.capabilities ?? [])
        let providerClaims = (metadata?.capabilityClaims ?? []).reduce(into: [LLMModelCapability: LLMSupportState]()) {
            $0[$1.capability] = $1.state
        }
        let capabilities = Dictionary(uniqueKeysWithValues: LLMModelCapability.allCases.map { capability in
            if let override = overrides.capabilitySupport[capability] {
                return (capability, LLMSupport(state: override, source: .userOverride))
            }
            if let provider = providerClaims[capability] {
                return (capability, LLMSupport(state: provider, source: .provider))
            }
            if catalogCapabilities.contains(capability) {
                return (capability, LLMSupport(state: .supported, source: .catalog))
            }
            return (capability, LLMSupport(state: .unknown, source: .fallback))
        })

        let catalogParameterIndex = Dictionary(uniqueKeysWithValues: catalogParameters.map { ($0.parameterID, $0) })
        let providerParameterClaims = (metadata?.parameterSupportClaims ?? []).reduce(into: [LLMParameterID: LLMSupportState]()) {
            $0[$1.parameterID] = $1.state
        }
        let parameterIDs = Set(catalogParameterIndex.keys).union(overrides.parameterOverrides.keys)
        let parameters = Dictionary(uniqueKeysWithValues: parameterIDs.map { parameterID in
            let catalog = catalogParameterIndex[parameterID]
            let override = overrides.parameterOverrides[parameterID]
            let mapping = override?.mapping ?? catalog?.mapping
            let mappingSource: LLMMetadataSource? = override?.mapping != nil
                ? .userOverride
                : (catalog?.mapping != nil ? .catalog : nil)

            var isSupported = catalog?.isSupported ?? false
            var supportSource: LLMMetadataSource = catalog == nil ? .fallback : .catalog
            if let provider = providerParameterClaims[parameterID] {
                switch provider {
                case .supported where catalog?.mapping != nil:
                    isSupported = true
                    supportSource = .provider
                case .unsupported:
                    isSupported = false
                    supportSource = .provider
                case .supported, .unknown:
                    break
                }
            }
            if let state = override?.support, state != .unknown {
                isSupported = state == .supported && mapping != nil
                supportSource = .userOverride
            }
            if isSupported && mapping == nil {
                isSupported = false
            }
            let support = LLMSupport(
                state: isSupported ? .supported : .unsupported,
                source: supportSource
            )

            let defaultValue: JSONValue?
            switch override?.defaultValue ?? .inherit {
            case .inherit:
                defaultValue = catalog?.defaultValue
            case .value(let value):
                defaultValue = value
            case .none:
                defaultValue = nil
            }

            let options: [String]?
            switch override?.options ?? .inherit {
            case .inherit:
                options = catalog?.options ?? parameterID.options
            case .value(let value):
                options = value
            case .none:
                options = nil
            }

            return (parameterID, LLMParameterProfile(
                parameterID: parameterID,
                support: support,
                mapping: mapping,
                mappingSource: mappingSource,
                isRequired: isSupported && (override?.isRequired ?? catalog?.isRequired ?? false),
                isEnabledByDefault: override?.isEnabledByDefault ?? catalog?.isEnabledByDefault ?? false,
                defaultValue: defaultValue,
                options: options
            ))
        })

        return LLMModelProfile(
            modelID: modelID,
            providerID: providerID,
            adapterID: adapterID,
            displayName: display.0,
            displayNameSource: display.1,
            contextSize: context.0,
            contextSizeSource: context.1,
            capabilities: capabilities,
            parameters: parameters
        )
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
