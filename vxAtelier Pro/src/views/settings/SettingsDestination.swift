import SwiftUI

enum SettingsDestination: CaseIterable, Identifiable, Hashable {
    case general
    case api
    case webSearch
    case models
    case prompts
    case tts
    case permissions
    case maintenance
    case developer
    case logSources

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .api: "API"
        case .webSearch: "Web Search"
        case .models: "Models"
        case .prompts: "Prompts"
        case .tts: "Speech"
        case .permissions: "Permissions"
        case .maintenance: "Maintenance"
        case .developer: "Developer"
        case .logSources: "Log Sources"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .api: "key.fill"
        case .webSearch: "magnifyingglass"
        case .models: "cpu"
        case .prompts: "text.bubble.fill"
        case .tts: "person.wave.2.fill"
        case .permissions: "lock.shield"
        case .maintenance: "wrench.and.screwdriver"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .logSources: "list.bullet.rectangle"
        }
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .general:
            GeneralSettingsView()
        case .api:
            APISettingsView()
        case .webSearch:
            WebSearchSettingsView()
        case .models:
            ModelsSettingsView()
        case .prompts:
            PromptsSettingsView()
        case .tts:
            TTSSettingsView()
        case .permissions:
            PermissionsSettingsView()
        case .maintenance:
            MaintenanceSettingsView()
        case .developer:
            DeveloperSettingsView()
        case .logSources:
            LogSourcesSettingsView()
        }
    }
}
