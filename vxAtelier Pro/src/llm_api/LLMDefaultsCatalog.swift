import Foundation

enum LLMDefaultsCatalogError: Error, Equatable, CustomStringConvertible {
    case missingResource(String)
    case emptyRegex(field: String)
    case invalidRegex(field: String, pattern: String, reason: String)
    case invalidRule(level: String, reason: String)
    case invalidMapping(parameter: LLMParameterID, reason: String)

    var description: String {
        switch self {
        case .missingResource(let name):
            return "Missing bundled LLM defaults resource \(name)."
        case .emptyRegex(let field):
            return "Empty regex in bundled LLM defaults field \(field)."
        case .invalidRegex(let field, let pattern, let reason):
            return "Invalid regex in bundled LLM defaults field \(field): \(pattern) (\(reason))."
        case .invalidRule(let level, let reason):
            return "Invalid \(level) LLM defaults rule: \(reason)."
        case .invalidMapping(let parameter, let reason):
            return "Invalid mapping for \(parameter.rawValue): \(reason)."
        }
    }
}

struct LLMParameterDefaults: Equatable, Identifiable {
    var id: LLMParameterID { parameterID }
    var parameterID: LLMParameterID
    var isSupported: Bool
    var mapping: LLMParameterMapping?
    var isRequired: Bool
    var isEnabledByDefault: Bool
    var defaultValue: JSONValue?
    var options: [String]?
}

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

    init(data: Data) throws {
        let document = try JSONDecoder().decode(LLMDefaultsDocument.self, from: data)
        providerDefaults = document.providerDefaults
        rules = try document.rules.enumerated()
            .map { try LLMDefaultsRule(payload: $0.element, order: $0.offset) }
            .sorted {
                $0.level.rank == $1.level.rank
                    ? $0.order < $1.order
                    : $0.level.rank < $1.level.rank
            }
    }

    static func loadBundled(resourceName: String = "LLMDefaults") throws -> LLMDefaultsCatalog {
        guard let url = bundledResourceURL(resourceName: resourceName, extension: "json") else {
            throw LLMDefaultsCatalogError.missingResource("\(resourceName).json")
        }
        return try LLMDefaultsCatalog(data: try Data(contentsOf: url))
    }

    func defaultModelID(for providerID: LLMProviderID) -> String? {
        providerDefaults.first { $0.provider == providerID }?.defaultModel
    }

    func modelDefaults(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        modelID: String
    ) -> LLMResolvedModelDefaults? {
        var resolved = LLMResolvedModelDefaults()
        var didMatch = false
        for rule in matchingRules(providerID: providerID, adapterID: adapterID, modelID: modelID) {
            guard let defaults = rule.modelDefaults else { continue }
            resolved.apply(defaults)
            didMatch = true
        }
        return didMatch ? resolved : nil
    }

    func parameterDefaults(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        modelID: String
    ) -> [LLMParameterDefaults] {
        var resolved: [LLMParameterID: LLMParameterDefaults] = [:]
        var order: [LLMParameterID] = []

        for rule in matchingRules(providerID: providerID, adapterID: adapterID, modelID: modelID) {
            for patch in rule.parameters {
                if resolved[patch.parameterID] == nil {
                    order.append(patch.parameterID)
                    resolved[patch.parameterID] = LLMParameterDefaults(
                        parameterID: patch.parameterID,
                        isSupported: false,
                        mapping: nil,
                        isRequired: false,
                        isEnabledByDefault: false,
                        defaultValue: nil,
                        options: patch.parameterID.options
                    )
                }
                guard var parameter = resolved[patch.parameterID] else { continue }
                if let supported = patch.supported {
                    parameter.isSupported = supported
                }
                if let mapping = patch.mapping {
                    parameter.mapping = mapping.resolved(adapterID: adapterID, parameterID: patch.parameterID)
                }
                if let required = patch.required {
                    parameter.isRequired = required
                }
                if let enabledByDefault = patch.enabledByDefault {
                    parameter.isEnabledByDefault = enabledByDefault
                }
                switch patch.defaultValue {
                case .inherit:
                    break
                case .set(let value):
                    parameter.defaultValue = value
                }
                switch patch.options {
                case .inherit:
                    break
                case .set(let options):
                    parameter.options = options
                }
                resolved[patch.parameterID] = parameter
            }
        }

        return order.compactMap { resolved[$0] }
    }

    private func matchingRules(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        modelID: String
    ) -> [LLMDefaultsRule] {
        rules.filter {
            $0.matches(providerID: providerID, modelID: modelID, adapterID: adapterID)
        }
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

struct LLMResolvedModelDefaults: Equatable {
    var contextSize: Int?
    var capabilities: [LLMModelCapability]?

    mutating func apply(_ defaults: LLMModelDefaultsPayload) {
        if let contextSize = defaults.contextSize {
            self.contextSize = contextSize
        }
        if let capabilities = defaults.capabilities {
            self.capabilities = capabilities
        }
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

private enum LLMDefaultsRuleLevel: String, Decodable {
    case adapter
    case provider
    case model

    var rank: Int {
        switch self {
        case .adapter: return 0
        case .provider: return 1
        case .model: return 2
        }
    }
}

private struct LLMDefaultsRulePayload: Decodable {
    var level: LLMDefaultsRuleLevel
    var match: LLMDefaultsRuleMatchPayload?
    var modelDefaults: LLMModelDefaultsPayload?
    var parameters: [LLMParameterPatch]?
}

private struct LLMDefaultsRule {
    var level: LLMDefaultsRuleLevel
    var order: Int
    var match: LLMDefaultsRuleMatch
    var modelDefaults: LLMModelDefaultsPayload?
    var parameters: [LLMParameterPatch]

    init(payload: LLMDefaultsRulePayload, order: Int) throws {
        level = payload.level
        self.order = order
        match = try LLMDefaultsRuleMatch(payload: payload.match)
        modelDefaults = payload.modelDefaults
        parameters = payload.parameters ?? []

        switch level {
        case .adapter:
            guard match.providerRegex == nil, match.modelRegex == nil else {
                throw LLMDefaultsCatalogError.invalidRule(
                    level: level.rawValue,
                    reason: "adapter rules cannot constrain provider or model"
                )
            }
        case .provider:
            guard match.providerRegex != nil, match.modelRegex == nil else {
                throw LLMDefaultsCatalogError.invalidRule(
                    level: level.rawValue,
                    reason: "provider rules require providerRegex and cannot contain modelRegex"
                )
            }
        case .model:
            guard match.modelRegex != nil else {
                throw LLMDefaultsCatalogError.invalidRule(
                    level: level.rawValue,
                    reason: "model rules require modelRegex"
                )
            }
        }

        for parameter in parameters {
            try parameter.mapping?.validate(parameterID: parameter.parameterID)
            guard let mapping = parameter.mapping else { continue }
            switch mapping.kind {
            case .adapter:
                guard let adapterID = match.adapterID,
                      adapterID.ownsEncoding(of: parameter.parameterID) else {
                    throw LLMDefaultsCatalogError.invalidMapping(
                        parameter: parameter.parameterID,
                        reason: "adapter mapping is not implemented by the rule's adapter"
                    )
                }
            case .key:
                guard let adapterID = match.adapterID,
                      adapterID.supportsKeyParameterMappings else {
                    throw LLMDefaultsCatalogError.invalidMapping(
                        parameter: parameter.parameterID,
                        reason: "key mapping is not supported by the rule's adapter"
                    )
                }
            case .preset:
                guard let adapterID = match.adapterID,
                      let preset = mapping.preset,
                      preset.supports(adapterID) else {
                    throw LLMDefaultsCatalogError.invalidMapping(
                        parameter: parameter.parameterID,
                        reason: "preset is not implemented by the rule's adapter"
                    )
                }
            }
        }
    }

    func matches(providerID: LLMProviderID, modelID: String, adapterID: LLMAdapterID) -> Bool {
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
        providerRegex = try LLMCompiledRegex.compile(payload?.providerRegex, field: "match.providerRegex")
        modelRegex = try LLMCompiledRegex.compile(payload?.modelRegex, field: "match.modelRegex")
        adapterID = payload?.adapterID
    }

    func matches(providerID: LLMProviderID, modelID: String, adapterID requestedAdapterID: LLMAdapterID) -> Bool {
        if let providerRegex, !providerRegex.matches(providerID.rawValue) {
            return false
        }
        if let modelRegex, !modelRegex.matches(modelID) {
            return false
        }
        if let adapterID, adapterID != requestedAdapterID {
            return false
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
    var contextSize: Int?
    var capabilities: [LLMModelCapability]?
}

private enum LLMPatchValue<Value> {
    case inherit
    case set(Value?)
}

private struct LLMParameterPatch: Decodable {
    var parameterID: LLMParameterID
    var supported: Bool?
    var mapping: LLMParameterMappingPatch?
    var required: Bool?
    var enabledByDefault: Bool?
    var defaultValue: LLMPatchValue<JSONValue>
    var options: LLMPatchValue<[String]>

    private enum CodingKeys: String, CodingKey {
        case parameterID = "id"
        case supported
        case mapping
        case required
        case enabledByDefault
        case defaultValue
        case options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parameterID = try container.decode(LLMParameterID.self, forKey: .parameterID)
        supported = try container.decodeIfPresent(Bool.self, forKey: .supported)
        mapping = try container.decodeIfPresent(LLMParameterMappingPatch.self, forKey: .mapping)
        required = try container.decodeIfPresent(Bool.self, forKey: .required)
        enabledByDefault = try container.decodeIfPresent(Bool.self, forKey: .enabledByDefault)
        defaultValue = container.contains(.defaultValue)
            ? .set(try container.decodeIfPresent(JSONValue.self, forKey: .defaultValue))
            : .inherit
        options = container.contains(.options)
            ? .set(try container.decodeIfPresent([String].self, forKey: .options))
            : .inherit
    }
}

private struct LLMParameterMappingPatch: Decodable {
    var kind: LLMParameterEncodingKind
    var key: String?
    var preset: LLMParameterStructuredPreset?

    func validate(parameterID: LLMParameterID) throws {
        switch kind {
        case .adapter:
            break
        case .key:
            guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMDefaultsCatalogError.invalidMapping(parameter: parameterID, reason: "key mapping requires a key")
            }
        case .preset:
            guard preset != nil else {
                throw LLMDefaultsCatalogError.invalidMapping(parameter: parameterID, reason: "preset mapping requires a preset")
            }
        }
    }

    func resolved(adapterID: LLMAdapterID, parameterID: LLMParameterID) -> LLMParameterMapping {
        LLMParameterMapping(
            adapterID: adapterID,
            parameterID: parameterID,
            encodingKind: kind,
            wireKey: key ?? "",
            structuredPreset: preset
        )
    }
}
