import Foundation

/// Errors raised while loading or resolving bundled LLM defaults.
enum LLMDefaultsCatalogError: Error, Equatable, CustomStringConvertible {
    case missingResource(String)
    case emptyRegex(field: String)
    case invalidRegex(field: String, pattern: String, reason: String)

    var description: String {
        switch self {
        case .missingResource(let name):
            return "Missing bundled LLM defaults resource \(name)."
        case .emptyRegex(let field):
            return "Empty regex in bundled LLM defaults field \(field)."
        case .invalidRegex(let field, let pattern, let reason):
            return "Invalid regex in bundled LLM defaults field \(field): \(pattern) (\(reason))."
        }
    }
}

/// Bundled model metadata and parameter mapping defaults.
struct LLMDefaultsCatalog {
    static let bundled: LLMDefaultsCatalog = {
        do {
            return try loadBundled()
        } catch {
            fatalError("Failed to load bundled LLM defaults: \(error)")
        }
    }()

    private let providerDefaults: [LLMProviderDefault]
    private let rules: [LLMDefaultsRule]

    /// Decodes defaults from JSON data for bundled loading and tests.
    init(data: Data) throws {
        let decoder = JSONDecoder()
        let document = try decoder.decode(LLMDefaultsDocument.self, from: data)
        self.providerDefaults = document.providerDefaults
        self.rules = try document.rules.map { try LLMDefaultsRule(payload: $0) }
    }

    /// Loads `LLMDefaults.json` from the app, test, or SwiftPM resource bundle.
    static func loadBundled(resourceName: String = "LLMDefaults") throws -> LLMDefaultsCatalog {
        guard let url = bundledResourceURL(resourceName: resourceName, extension: "json") else {
            throw LLMDefaultsCatalogError.missingResource("\(resourceName).json")
        }
        return try LLMDefaultsCatalog(data: try Data(contentsOf: url))
    }

    /// Returns the configured default model identifier for a provider.
    func defaultModelID(for providerID: LLMProviderID) -> String? {
        providerDefaults.first { $0.provider == providerID }?.defaultModel
    }

    /// Returns model defaults after applying matching regex rules in declaration order.
    func modelDefaults(providerID: LLMProviderID, modelID: String) -> LLMResolvedModelDefaults? {
        var resolved = LLMResolvedModelDefaults()
        var didMatch = false
        for rule in rules where rule.matches(providerID: providerID, modelID: modelID, adapterID: nil) {
            guard let modelDefaults = rule.modelDefaults else { continue }
            resolved.apply(modelDefaults)
            didMatch = true
        }
        return didMatch ? resolved : nil
    }

    /// Builds a model candidate from bundled defaults for draft fetch/create flows.
    func modelDescriptor(
        providerID: LLMProviderID,
        modelID: String,
        displayName: String? = nil,
        rawMetadataJSON: String? = nil
    ) -> LLMModelDescriptor {
        let defaults = modelDefaults(providerID: providerID, modelID: modelID)
        return LLMModelDescriptor(
            id: modelID,
            displayName: displayName,
            providerID: providerID,
            contextWindow: defaults?.contextWindow,
            capabilities: defaults?.capabilities ?? [.text],
            rawMetadataJSON: rawMetadataJSON
        )
    }

    /// Returns parameter mappings for matching provider/model/adapter rules.
    func parameterMappings(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        modelID: String
    ) -> [LLMParameterMappingDescriptor] {
        var merged: [LLMParameterID: LLMParameterMappingDescriptor] = [:]
        var order: [LLMParameterID] = []

        for rule in rules {
            guard rule.matches(providerID: providerID, modelID: modelID, adapterID: adapterID),
                  let parameterMappings = rule.parameterMappings else {
                continue
            }

            for mapping in parameterMappings {
                let descriptor = mapping.descriptor(adapterID: adapterID)
                if merged[descriptor.semanticParameterID] == nil {
                    order.append(descriptor.semanticParameterID)
                }
                merged[descriptor.semanticParameterID] = descriptor
            }
        }

        return order.compactMap { merged[$0] }
    }

    private static func bundledResourceURL(resourceName: String, extension fileExtension: String) -> URL? {
        for bundle in candidateBundles {
            if let url = bundle.url(forResource: resourceName, withExtension: fileExtension) {
                return url
            }
            if let url = bundle.url(forResource: resourceName, withExtension: fileExtension, subdirectory: "llm_api/Resources") {
                return url
            }
            if let url = bundle.url(forResource: resourceName, withExtension: fileExtension, subdirectory: "src/llm_api/Resources") {
                return url
            }
        }

        let filename = "\(resourceName).\(fileExtension)"
        for bundle in candidateBundles {
            guard let resourceURL = bundle.resourceURL,
                  let enumerator = FileManager.default.enumerator(
                      at: resourceURL,
                      includingPropertiesForKeys: nil
                  ) else {
                continue
            }
            for case let url as URL in enumerator where url.lastPathComponent == filename {
                return url
            }
        }
        return nil
    }

    private static var candidateBundles: [Bundle] {
        var bundles: [Bundle] = []
        #if SWIFT_PACKAGE
        bundles.append(.module)
        #endif
        bundles.append(.main)
        bundles.append(contentsOf: Bundle.allBundles)
        bundles.append(contentsOf: Bundle.allFrameworks)
        var seen = Set<String>()
        return bundles.filter { bundle in
            let key = bundle.bundleURL.path
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}

/// Fully resolved model metadata defaults after regex rule application.
struct LLMResolvedModelDefaults: Equatable {
    var contextWindow: Int?
    var capabilities: [LLMModelCapability]?

    mutating func apply(_ defaults: LLMModelDefaultsPayload) {
        if let contextWindow = defaults.contextWindow { self.contextWindow = contextWindow }
        if let capabilities = defaults.capabilities { self.capabilities = capabilities }
    }
}

private struct LLMDefaultsDocument: Decodable {
    var providerDefaults: [LLMProviderDefault]
    var rules: [LLMDefaultsRulePayload]
}

private struct LLMProviderDefault: Decodable {
    var provider: LLMProviderID
    var defaultModel: String
}

private struct LLMDefaultsRulePayload: Decodable {
    var match: LLMDefaultsRuleMatchPayload?
    var modelDefaults: LLMModelDefaultsPayload?
    var parameterMappings: [LLMParameterMappingDefault]?
}

private struct LLMDefaultsRule {
    var match: LLMDefaultsRuleMatch
    var modelDefaults: LLMModelDefaultsPayload?
    var parameterMappings: [LLMParameterMappingDefault]?

    init(payload: LLMDefaultsRulePayload) throws {
        self.match = try LLMDefaultsRuleMatch(payload: payload.match)
        self.modelDefaults = payload.modelDefaults
        self.parameterMappings = payload.parameterMappings
    }

    func matches(
        providerID: LLMProviderID,
        modelID: String,
        adapterID: LLMAdapterID?
    ) -> Bool {
        match.matches(providerID: providerID, modelID: modelID, adapterID: adapterID)
    }
}

private struct LLMDefaultsRuleMatchPayload: Decodable {
    var providerRegex: String?
    var modelRegex: String?
    var adapterID: LLMAdapterID?
}

private struct LLMDefaultsRuleMatch {
    var providerRegex: LLMCompiledRegex?
    var modelRegex: LLMCompiledRegex?
    var adapterID: LLMAdapterID?

    init(payload: LLMDefaultsRuleMatchPayload?) throws {
        self.providerRegex = try LLMCompiledRegex.compile(payload?.providerRegex, field: "match.providerRegex")
        self.modelRegex = try LLMCompiledRegex.compile(payload?.modelRegex, field: "match.modelRegex")
        self.adapterID = payload?.adapterID
    }

    func matches(
        providerID: LLMProviderID,
        modelID: String,
        adapterID requestedAdapterID: LLMAdapterID?
    ) -> Bool {
        if let providerRegex, !providerRegex.matches(providerID.rawValue) {
            return false
        }
        if let modelRegex, !modelRegex.matches(modelID) {
            return false
        }
        if let adapterID {
            return adapterID == requestedAdapterID
        }
        return true
    }
}

private struct LLMCompiledRegex {
    var regex: NSRegularExpression

    static func compile(_ pattern: String?, field: String) throws -> LLMCompiledRegex? {
        guard let pattern else { return nil }
        guard !pattern.isEmpty else {
            throw LLMDefaultsCatalogError.emptyRegex(field: field)
        }
        do {
            return LLMCompiledRegex(
                regex: try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            )
        } catch {
            throw LLMDefaultsCatalogError.invalidRegex(
                field: field,
                pattern: pattern,
                reason: error.localizedDescription
            )
        }
    }

    func matches(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }
}

struct LLMModelDefaultsPayload: Decodable, Equatable {
    var contextWindow: Int?
    var capabilities: [LLMModelCapability]?
}

private struct LLMParameterMappingDefault: Decodable {
    var parameter: LLMParameterID
    var enabled: Bool?
    var required: Bool?
    var encoding: LLMParameterEncodingKind?
    var wireKey: String?
    var preset: LLMParameterStructuredPreset?
    var defaultValue: JSONValue?

    func descriptor(adapterID: LLMAdapterID) -> LLMParameterMappingDescriptor {
        LLMParameterMappingDescriptor(
            adapterID: adapterID,
            semanticParameterID: parameter,
            isEnabled: enabled ?? true,
            isRequired: required ?? false,
            encodingKind: encoding ?? .scalarKey,
            wireKey: wireKey ?? "",
            structuredPreset: preset,
            defaultValue: defaultValue
        )
    }
}
