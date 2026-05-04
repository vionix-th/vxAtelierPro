import Foundation

extension ModelItem {
    func materializeDefaultParameterMappings(preserveCustomized: Bool = true) {
        let providerID = LLMProviderID(rawValue: providerID) ?? .customOpenAICompatible
        let endpointFamilies = endpointFamiliesRaw
            .compactMap { LLMEndpointFamily(rawValue: $0) }
            .filter { $0 != .models }

        for endpointFamily in endpointFamilies {
            materializeDefaultParameterMappings(
                endpointFamily: endpointFamily,
                providerID: providerID,
                preserveCustomized: preserveCustomized
            )
        }
    }

    func resetDefaultParameterMappings(endpointFamily: LLMEndpointFamily) {
        let providerID = LLMProviderID(rawValue: providerID) ?? .customOpenAICompatible
        materializeDefaultParameterMappings(
            endpointFamily: endpointFamily,
            providerID: providerID,
            preserveCustomized: false
        )
    }

    private func materializeDefaultParameterMappings(
        endpointFamily: LLMEndpointFamily,
        providerID: LLMProviderID,
        preserveCustomized: Bool
    ) {
        let defaults = LLMParameterMappingCatalog.defaults(
            providerID: providerID,
            endpointFamily: endpointFamily,
            modelID: modelID
        )

        for descriptor in defaults {
            if let existing = parameterMappings.first(where: {
                $0.endpointFamilyEnum == endpointFamily && $0.semanticParameterIDEnum == descriptor.semanticParameterID
            }) {
                if preserveCustomized && existing.isCustomized {
                    continue
                }
                existing.apply(descriptor, markCustomized: false)
            } else {
                parameterMappings.append(ModelParameterMappingItem(descriptor: descriptor))
            }
        }

        if !preserveCustomized {
            let defaultIDs = Set(defaults.map(\.semanticParameterID))
            parameterMappings.removeAll { mapping in
                mapping.endpointFamilyEnum == endpointFamily && !defaultIDs.contains(mapping.semanticParameterIDEnum)
            }
        }
    }
}
