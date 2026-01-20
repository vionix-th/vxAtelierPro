// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "vxAtelier-Pro",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .executable(
            name: "vxAtelier-Pro",
            targets: ["vxAtelier-Pro"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/gonzalezreal/MarkdownUI.git", from: "2.1.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        .executableTarget(
            name: "vxAtelier-Pro",
            dependencies: [
                .product(name: "MarkdownUI", package: "MarkdownUI"),
            ],
            path: "vxAtelier Pro/src",
            exclude: [".DS_Store", 
                      "ai/README.md", 
                      "tts/README.md"],
            sources: [
                // AI Service
                "ai/AIService.swift",
                "ai/AIServiceCommon.swift",
                "ai/AIServiceManager.swift",
                "ai/AnthropicAPIModel.swift",
                "ai/AnthropicCodableTypes.swift",
                "ai/AnthropicDefaults.swift",
                "ai/AnthropicService.swift",
                "ai/DeepSeekCodableTypes.swift",
                "ai/DeepSeekDefaults.swift",
                "ai/DeepSeekModel.swift",
                "ai/DeepSeekService.swift",
                "ai/ModelProviderUtils.swift",
                "ai/NetworkManager.swift",
                "ai/OpenAICodableTypes.swift",
                "ai/OpenAIDefaults.swift",
                "ai/OpenAIModel.swift",
                "ai/OpenAIService.swift",                
                "ai/tooling/AIToolDialog.swift",
                "ai/tooling/AITooling.swift",
                "ai/tooling/AIToolRegistry.swift",
                "ai/tooling/AIToolShortcuts.swift",
                "ai/tooling/AIToolSettings.swift",
                "ai/tooling/AIToolWebSearch.swift",
                "ai/tooling/AIToolWebsiteReader.swift",
                "ai/XAICodableTypes.swift",
                "ai/XAIDefaults.swift",
                "ai/XAIModel.swift",
                "ai/XAIService.swift",
                // App Core
                "vxAtelierPro.swift",
                "system/StreamingState.swift",
                "system/StreamingConversationHandler.swift",
                // Models
                "models/AiRequestArgument.swift",
                "models/APIConfigurationItem.swift",
                "models/BookmarkItem.swift",
                "models/ContentItem.swift",
                "models/ConversationItem.swift",
                "models/ConversationTurn.swift",
                "models/TurnEvent.swift",
                "models/ConversationOptions.swift",                
                "models/ItemStatus.swift",
                "models/MessageItem.swift",
                "models/ModelItem.swift",
                "models/ProjectItem.swift",
                "models/PromptTemplate.swift",
                "models/VoiceConfigurationItem.swift",
                "models/AppearanceStyle.swift",
                "models/WebSearchConfigurationItem.swift",
                "models/CompletionStreamProcessor.swift",
                // Search Service
                "search/WebSearchService.swift",
                "search/WebSearchServiceManager.swift",
                "search/GoogleCustomSearchService.swift",
                // System
                "system/AppDefaults.swift",
                "system/DataManager.swift",
                "system/export/APIConfigurationExportData.swift",
                "system/export/BookmarkExportData.swift",
                "system/export/ConversationExportData.swift",
                "system/export/ConversationOptionsExportData.swift",
                "system/export/ExportUtils.swift",
                "system/export/FullBackup.swift",
                "system/export/MessageExportData.swift",
                "system/export/ModelExportData.swift",
                "system/export/ParameterValueExportData.swift",
                "system/export/ProjectExportData.swift",
                "system/export/PromptTemplateExportData.swift",
                "system/export/PromptExportDocument.swift",
                "system/export/VoiceConfigurationExportData.swift",
                "system/export/WebSearchConfigurationExportData.swift",
                "system/JsonSerializer.swift",
                "system/MenuItemStyle.swift",
                "system/PermissionManager.swift",
                "system/AppSettings.swift",
                "system/QueryManager.swift",
                // TTS
                "tts/TTSControlView.swift",
                "tts/TTSSystem.swift",
                // Logging
                "log/LogSource.swift",
                "log/LoggingService.swift",
                // Utilities
                "utilities/ErrorHandling.swift",
                "utilities/FileHelper.swift",
                "utilities/HotkeyManager.swift",
                "utilities/JSONUtils.swift",
                "utilities/JSONValue.swift",
                "utilities/ParameterExpansion.swift",
                "utilities/ShortcutsManager.swift",
                "utilities/TypeConversionUtils.swift",
                "utilities/URLExtensions.swift",
                "viewmodels/AppSceneModel.swift",
                "views/AppShellView.swift",
                "views/ContentView.swift",
                "views/content/ContentRouting.swift",
                "views/content/NavigationRouter.swift",
                "views/content/ContentSidebarView.swift",
                "views/StatusBar.swift",
                // Views - Components
                "views/components/AvatarView.swift",
                "views/components/AvatarPickerView.swift",
                "views/components/SidebarSortButton.swift",
                "views/components/NavigationItem.swift",
                "views/components/PermissionRowView.swift",
                "views/components/DetailPlaceholderView.swift",
                "views/components/markdown/MarkdownUIRenderer.swift",
                // Splash removed: no highlighter helpers
                "views/components/HybridNumericInputView.swift",        
                "views/components/ImagePicker.swift",        
                // Views - Dialog
                "views/dialog/MessageView.swift",                
                "views/dialog/BookmarkSheetView.swift",
                "views/dialog/MessageInputView.swift",
                "views/dialog/ConversationView.swift",
                "views/dialog/ConversationOptionsView.swift",                
                "views/dialog/MessageAction.swift",
                "views/dialog/ConversationViewModel.swift",
                "views/dialog/ConversationViewModelStore.swift",
                // Views - Project
                "views/project/ProjectView.swift",
                // Views - Status Bar
                // Views - Settings
                "views/settings/APIConfigurationEditView.swift",
                "views/settings/ApplicationSettingsView.swift",
                "views/settings/ConfirmationContext.swift",
                "views/settings/ModelSelectionView.swift",
                "views/settings/ModelEditorView.swift",
                "views/settings/PromptTemplateEditView.swift",
                "views/settings/PromptTemplateList.swift",
                "views/settings/VoiceConfigurationListView.swift",
                "views/settings/WebSearchConfigurationEditView.swift",
                "views/settings/APISettingsView.swift",
                "views/settings/GeneralSettingsView.swift",
                "views/settings/WebSearchSettingsView.swift",
                "views/settings/TTSSettingsView.swift",
                "views/settings/ModelsSettingsView.swift",
                "views/settings/PromptsSettingsView.swift",
                "views/settings/PermissionsSettingsView.swift",
                "views/settings/LogSourcesSettingsView.swift",
                "views/settings/MaintenanceSettingsView.swift",
                "views/settings/DeveloperSettingsView.swift",
                // Views - Settings Components
                "views/settings/components/ActionButton.swift",
                "views/settings/components/ModelProviderSectionView.swift",
                "views/settings/components/SettingsActionBar.swift",
                "views/settings/components/SettingsListSectionView.swift",
                "views/settings/components/SettingsRowComponents.swift",
                "views/settings/components/SettingsSectionView.swift",
                "views/settings/components/SelfSignedCertWhitelistView.swift",
                "views/settings/components/SettingsListRow.swift",
                "views/settings/components/SettingsRowActions.swift",
                // Views - Utility
                "views/utility/GlobalUtilityPanel.swift",
                "views/utility/LogHistorySheet.swift",
                "views/utility/ContentFilter.swift",
                "views/utility/Sorters.swift"
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("RELEASE", .when(configuration: .release))
            ]
        )
    ]
) 
