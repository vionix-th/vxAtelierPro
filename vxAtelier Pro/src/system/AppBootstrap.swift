import Foundation
import SwiftData
import SwiftUI

#if os(macOS)
    import AppKit
#endif

@MainActor
struct AppBootstrap {
    let modelContainer: ModelContainer
    let queryManager: QueryManager
    let ttsQueue: TTSQueue
    let appSceneModel: AppSceneModel

    static func live() -> AppBootstrap {
        makeBootstrap(seedPreviewData: false, isStoredInMemoryOnly: false)
    }

    static func preview() -> AppBootstrap {
        makeBootstrap(seedPreviewData: true, isStoredInMemoryOnly: false)
    }

    static func inMemory() -> AppBootstrap {
        makeBootstrap(seedPreviewData: false, isStoredInMemoryOnly: true)
    }

    private static func makeBootstrap(
        seedPreviewData: Bool,
        isStoredInMemoryOnly: Bool
    ) -> AppBootstrap {
        vxAtelierPro.log.debug("Initializing model container")
        let modelContainer = makeModelContainer(isStoredInMemoryOnly: isStoredInMemoryOnly)
        vxAtelierPro.log.debug("Model container initialized")

        vxAtelierPro.log.debug("Initializing query manager")
        let queryManager = QueryManager(modelContext: modelContainer.mainContext)
        vxAtelierPro.log.debug("Query manager initialized")

        vxAtelierPro.log.debug("Initializing TTS queue")
        let ttsQueue = TTSQueue(modelContext: modelContainer.mainContext)
        vxAtelierPro.log.debug("TTS queue initialized")

        vxAtelierPro.log.debug("Initializing app scene model")
        let appSceneModel = AppSceneModel(modelContext: modelContainer.mainContext)
        vxAtelierPro.log.debug("App scene model initialized")

        let bootstrap = AppBootstrap(
            modelContainer: modelContainer,
            queryManager: queryManager,
            ttsQueue: ttsQueue,
            appSceneModel: appSceneModel
        )

        if seedPreviewData {
            bootstrap.seedPreviewData()
        }

        return bootstrap
    }

    private static func makeModelContainer(isStoredInMemoryOnly: Bool) -> ModelContainer {
        let schema = Schema([
            APIConfigurationItem.self,
            ModelItem.self,
            ModelParameterMappingItem.self,
            ModelParameterAvailabilityItem.self,
            ConversationOptions.self,
            MessageItem.self,
            MessageContentPartItem.self,
            ToolCallItem.self,
            ResponseRunItem.self,
            ConversationTurn.self,
            TurnEvent.self,
            ConversationItem.self,
            ProjectItem.self,
            BookmarkItem.self,
            PromptTemplate.self,
            VoiceConfigurationItem.self,
            WebSearchConfigurationItem.self,
        ])

        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isRunningPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let shouldStoreInMemory = isStoredInMemoryOnly || isRunningTests || isRunningPreviews
        vxAtelierPro.log.debug(
            "Creating ModelContainer with in-memory store: \(shouldStoreInMemory)"
        )
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: shouldStoreInMemory
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: vxAtelierPro.ProjectMigrationPlan.self,
                configurations: modelConfiguration
            )
        } catch {
            vxAtelierPro.log.error("Failed to create ModelContainer: \(error.localizedDescription)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    func performLaunchBootstrap() {
        vxAtelierPro.log.debug("Ensuring system conversation")
        queryManager.ensureSystemConversation()
        vxAtelierPro.log.debug("System conversation ensured")

        vxAtelierPro.log.debug("Registering tools")
        registerDefaultTools()
        vxAtelierPro.log.debug("Tools registered")

        #if os(macOS)
            if UserDefaults.standard.bool(forKey: AppSettings.Keys.makeKeyAndOrderFront) {
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    vxAtelierPro.log.debug("Brought app to front on startup")
                }
            }
        #endif
    }

    #if os(macOS)
        func installLaunchHooks(on appDelegate: AppDelegate) {
            vxAtelierPro.log.debug("Initializing Global Hotkey Controller")
            let hotkeyController = GlobalHotkeyController(appSceneModel: appSceneModel)
            appDelegate.onDidFinishLaunching = { [hotkeyController] in
                Task { @MainActor in
                    hotkeyController.register()
                }
            }
            vxAtelierPro.log.debug("Global Hotkey Controller initialized")
        }
    #endif

    private func registerDefaultTools() {
        let registry = LLMToolRegistry.shared
        let context = modelContainer.mainContext

        registry.registerTool(ListConversationsTool(modelContext: context))
        registry.registerTool(RenameConversationTool(modelContext: context))
        registry.registerTool(FindConversationTool(modelContext: context))
        registry.registerTool(CurrentConversationTool())

        #if os(macOS)
            registry.registerTool(ListShortcutsTool())
            registry.registerTool(RunShortcutTool())
        #endif

        registry.registerTool(ListSettingsTool())
        registry.registerTool(ReadSettingTool())
        registry.registerTool(WriteSettingTool())
        registry.registerTool(WebSearchTool(queryManager: queryManager))
        registry.registerTool(ReadWebsiteTool())
    }

    private func seedPreviewData() {
        vxAtelierPro.log.debug("Seeding preview data")
        let context = modelContainer.mainContext

        let apiConfiguration = APIConfigurationItem(
            name: "Preview API",
            apiKey: "preview-key",
            baseURL: "https://example.invalid",
            isDefault: true,
            defaultModel: "preview-model",
            providerID: .openAIPlatform
        )

        let previewModel = ModelItem(modelID: "preview-model", apiConfiguration: apiConfiguration)
        previewModel.displayName = "Preview Model"

        let conversationOptions = ConversationOptions(apiConfiguration: apiConfiguration)
        conversationOptions.selectedModelID = previewModel.modelID

        let project = ProjectItem(
            "Preview Project",
            defaultOptions: ConversationOptions(apiConfiguration: apiConfiguration)
        )
        let conversation = ConversationItem("Preview Conversation", options: conversationOptions)
        conversation.project = project

        let userMessage = MessageItem(role: "user", text: "Show the preview-ready settings view.")
        let turn = ConversationTurn(sequenceNumber: 0, userMessage: userMessage, conversation: conversation)
        conversation.turns.append(turn)

        context.insert(apiConfiguration)
        context.insert(previewModel)
        context.insert(project)
        context.insert(conversation)

        do {
            try context.save()
            vxAtelierPro.log.debug("Preview data seeded")
        } catch {
            vxAtelierPro.log.error("Failed to seed preview data: \(error.localizedDescription)")
        }
    }

    func applyingDependencies<V: View>(to content: V) -> some View {
        content
            .modelContainer(modelContainer)
            .environment(queryManager)
            .environment(ttsQueue)
            .environment(appSceneModel)
            .environment(appSceneModel.router)
    }

    #if os(macOS)
        final class AppDelegate: NSObject, NSApplicationDelegate {
            var onDidFinishLaunching: (() -> Void)?

            func applicationDidFinishLaunching(_ notification: Notification) {
                vxAtelierPro.log.debug("Application did finish launching")
                onDidFinishLaunching?()
            }

            func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
                let shouldTerminate = UserDefaults.standard.bool(
                    forKey: AppSettings.Keys.shouldTerminateAfterLastWindowClosed)
                vxAtelierPro.log.debug(
                    "Checking if should terminate after last window closed: \(shouldTerminate)")
                return shouldTerminate
            }
        }

        @MainActor
        final class GlobalHotkeyController {
            private let hotkeys = HotkeyManager()
            private let appSceneModel: AppSceneModel
            private var didRegister = false

            init(appSceneModel: AppSceneModel) {
                self.appSceneModel = appSceneModel
            }

            func register() {
                guard !didRegister else { return }
                didRegister = true
                vxAtelierPro.log.debug("Registering global hotkeys")
                hotkeys.register(
                    key: "k",
                    modifierFlags: [.command],
                    action: { [weak self] _ in
                        guard let self else { return false }
                        vxAtelierPro.log.debug("Global utility panel hotkey triggered")
                        Task { @MainActor in
                            self.appSceneModel.requestUtilityPanel()
                        }
                        return true
                    }
                )
            }
        }
    #endif
}

extension View {
    func bootstrapped(with bootstrap: AppBootstrap) -> some View {
        bootstrap.applyingDependencies(to: self)
    }
}
