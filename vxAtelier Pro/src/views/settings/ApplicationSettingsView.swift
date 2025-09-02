import SwiftUI
import SwiftData
import AVFoundation
import os

// MARK: - OSLogType Extension
extension OSLogType {
    static let notice = OSLogType(rawValue: 2) // Add notice level which is between info and debug
}

// MARK: - Application Settings View
struct ApplicationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(QueryManager.self) private var queryManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    enum SettingsTab: CaseIterable, Identifiable {
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

        var label: String {
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
    }

    @State private var selectedTab: SettingsTab? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.label, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .navigationTitle("Settings")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                        .padding(AppDefaults.paddingLarge)
                case .api:
                    APISettingsView()
                        .padding(AppDefaults.paddingLarge)
                case .webSearch:
                    WebSearchSettingsView()
                        .padding(AppDefaults.paddingLarge)
                case .models:
                    ModelsSettingsView()
                        .padding(AppDefaults.paddingLarge)
                case .prompts:
                    PromptsSettingsView()
                        .padding(AppDefaults.paddingLarge)
                case .tts:
                    TTSSettingsView()
                        .padding(AppDefaults.paddingLarge)
                case .permissions:
                    PermissionsSettingsView()
                        .padding(AppDefaults.paddingLarge)
                case .maintenance:
                    MaintenanceSettingsView()
                        .padding(AppDefaults.paddingLarge)
                case .developer:
                    DeveloperSettingsView()
                        .padding(AppDefaults.paddingLarge)
                case .logSources:
                    LogSourcesSettingsView()
                        .padding(AppDefaults.paddingLarge)
                case nil:
                    Text("Select a category from the sidebar.")
                        .font(.title)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            vxAtelierPro.log.debug("ApplicationSettingsView appeared")
            if horizontalSizeClass == .compact {
                if selectedTab != nil {
                    selectedTab = nil
                }
            } else {
                if selectedTab == nil {
                    selectedTab = .general
                }
            }
        }
    }
}

