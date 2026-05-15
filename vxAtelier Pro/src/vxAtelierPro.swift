import Observation
import SwiftData
import SwiftUI

#if os(macOS)
    import AppKit
    import CoreGraphics
#elseif os(iOS)
    import UIKit
#endif

// MARK: - Commands

/// Custom commands for the application's main menu
struct AppCommands: Commands {
    @AppStorage(AppSettings.Keys.showEmptySections) private var showEmptySections: Bool = AppDefaults.showEmptySections
    @AppStorage(AppSettings.Keys.contentFilter) private var contentFilter: ContentFilter = .active

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            Toggle(
                "Show Empty Sections",
                isOn: $showEmptySections
            )
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Button("Show Conversations") {
                setContentFilter(.active, contentFilter: $contentFilter)
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Show Archive") {
                setContentFilter(.archived, contentFilter: $contentFilter)
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Show Trash") {
                setContentFilter(.trashed, contentFilter: $contentFilter)
            }
            .keyboardShortcut("3", modifiers: [.command])

            Divider()
        }
    }
}

/// vxAtelier Pro - An AI-powered writing and conversation assistant
///
/// This is the main entry point for the vxAtelier Pro application. It handles the core setup
/// of the application, including the logging system, data model container, and platform-specific UI elements.
@main
struct vxAtelierPro: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppBootstrap.AppDelegate.self) private var appDelegate
    #endif

    static let log = LoggingService.shared

    // MARK: - Data Management
    enum ProjectMigrationPlan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] {
            [CurrentSchema.self]
        }

        static var stages: [MigrationStage] = []  // Empty stages = lightweight migration

        enum CurrentSchema: VersionedSchema {
            static var versionIdentifier = Schema.Version(1, 0, 0)
            static var models: [any PersistentModel.Type] {
                [
                    ConversationItem.self,
                    ProjectItem.self,
                    BookmarkItem.self,
                    PromptTemplate.self,
                    VoiceConfigurationItem.self,
                    APIConfigurationItem.self,
                    ModelItem.self,
                    ModelParameterMappingItem.self,
                    ModelParameterAvailabilityItem.self,
                    MessageItem.self,
                    MessageContentPartItem.self,
                    ToolCallItem.self,
                    ResponseRunItem.self,
                    ConversationTurn.self,
                    TurnEvent.self,
                    ConversationOptions.self,
                    WebSearchConfigurationItem.self,
                ]
            }
        }
    }

    private enum LaunchMode {
        case normal(AppBootstrap)
        case recovery

        var bootstrap: AppBootstrap? {
            switch self {
            case .normal(let bootstrap):
                return bootstrap
            case .recovery:
                return nil
            }
        }
    }

    private let launchMode: LaunchMode

    private var isRecoveryLaunch: Bool {
        if case .recovery = launchMode {
            return true
        }
        return false
    }

    @AppStorage(AppSettings.Keys.appearanceStyle) private var appearanceStyle: AppearanceStyle = .system

    private var effectiveColorScheme: ColorScheme? {
        switch appearanceStyle {
        case .system:
            return nil  // Follow system, do not override
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    init() {
        vxAtelierPro.log.debug("Initializing vxAtelierPro")

        let recoveryLaunch = Self.shouldLaunchInRecoveryMode()

        if recoveryLaunch {
            vxAtelierPro.log.notice("Launching in startup recovery mode")
            launchMode = .recovery
        } else {
            vxAtelierPro.log.debug("Initializing app bootstrap")
            let bootstrap = AppBootstrap.live()
            vxAtelierPro.log.debug("App bootstrap initialized")
            launchMode = .normal(bootstrap)

            #if os(macOS)
                vxAtelierPro.log.debug("Installing bootstrap launch hooks")
                bootstrap.installLaunchHooks(on: appDelegate)
                vxAtelierPro.log.debug("Bootstrap launch hooks installed")
            #endif

            bootstrap.performLaunchBootstrap()
        }

        vxAtelierPro.log.debug("vxAtelierPro initialized")
    }

    #if os(macOS)
        static func shouldLaunchInRecoveryMode(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            modifierFlags: CGEventFlags = CGEventSource.flagsState(.combinedSessionState)
        ) -> Bool {
            if environment["VXATELIER_FORCE_RECOVERY_MODE"] == "1" {
                return true
            }
            return modifierFlags.contains(.maskAlternate)
        }
    #else
        static func shouldLaunchInRecoveryMode() -> Bool {
            false
        }
    #endif

    // MARK: - Scene Configuration

    var body: some Scene {
        #if os(macOS)
            WindowGroup("Main Window", id: "mainWindow") {
                MainWindowRootView(
                    bootstrap: launchMode.bootstrap,
                    isRecoveryLaunch: isRecoveryLaunch,
                    effectiveColorScheme: effectiveColorScheme
                )
            }
            .commands {
                AppCommands()
            }

            Settings {
                MacOSSettingsRootView(
                    bootstrap: launchMode.bootstrap,
                    effectiveColorScheme: effectiveColorScheme
                )
            }

            Window("Utility", id: "utilityPanel") {
                MacOSUtilityWindowRootView(
                    bootstrap: launchMode.bootstrap,
                    effectiveColorScheme: effectiveColorScheme
                )
            }
            .windowResizability(.contentSize)
            .defaultSize(width: 420, height: 140)

            MenuBarExtra("vxAtelier Pro", systemImage: "message.circle") {
                MenuBarContent(bootstrap: launchMode.bootstrap)
            }
        #else
            WindowGroup("Main Window", id: "mainWindow") {
                AppShellView()
                    .preferredColorScheme(effectiveColorScheme)
                    .bootstrapped(with: launchMode.bootstrap!)
            }
            .commands {
                AppCommands()
            }
        #endif
    }
}

// MARK: - Platform-Specific Components

#if os(macOS)
    private struct MainWindowRootView: View {
        let bootstrap: AppBootstrap?
        let isRecoveryLaunch: Bool
        let effectiveColorScheme: ColorScheme?

        var body: some View {
            if isRecoveryLaunch {
                StartupRecoveryView()
            } else if let bootstrap {
                AppShellView()
                    .preferredColorScheme(effectiveColorScheme)
                    .bootstrapped(with: bootstrap)
            }
        }
    }

    private struct MacOSSettingsRootView: View {
        let bootstrap: AppBootstrap?
        let effectiveColorScheme: ColorScheme?

        var body: some View {
            if let bootstrap {
                MacOSApplicationSettingsSceneView()
                    .preferredColorScheme(effectiveColorScheme)
                    .bootstrapped(with: bootstrap)
            } else {
                StartupRecoveryPlaceholderView()
            }
        }
    }

    private struct MacOSUtilityWindowRootView: View {
        let bootstrap: AppBootstrap?
        let effectiveColorScheme: ColorScheme?

        var body: some View {
            if let bootstrap {
                UtilityPanelView()
                    .preferredColorScheme(effectiveColorScheme)
                    .bootstrapped(with: bootstrap)
            } else {
                StartupRecoveryPlaceholderView()
            }
        }
    }

    /// Menu bar extra content for macOS
    struct MenuBarContent: View {
        let bootstrap: AppBootstrap?
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            if bootstrap != nil {
                Button("New Window") {
                    openWindow(id: "mainWindow")
                    vxAtelierPro.log.info("Opened new window from menu bar")
                }

                Divider()

                SettingsLink {
                    Label("Settings", systemImage: "gear")
                }

                Divider()
            } else {
                Text("Recovery mode active")
                    .font(.caption)

                Divider()
            }

            Button("Quit vxAtelier Pro") {
                vxAtelierPro.log.notice("Application quit requested from menu bar")
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private enum RecoveryImportMode {
        case backup
        case genericImport
    }

    /// Startup recovery view shown when the Option key is held at launch.
    struct StartupRecoveryView: View {
        @State private var confirmation: SettingsConfirmation?
        @State private var completionMessage = ""
        @State private var showCompletionAlert = false
        @State private var showFileImporter = false
        @State private var selectedImportMode: RecoveryImportMode?

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: AppDefaults.paddingLarge) {
                    VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                        Text("Startup Recovery")
                            .font(.system(size: 28, weight: .semibold))
                        Text("Option-key startup bypasses the normal shell so local settings and stored data can be repaired before the app launches normally.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                        recoveryActionButton(
                            title: "Reset Settings",
                            systemImage: "arrow.uturn.backward.circle.fill"
                        ) {
                            confirmation = SettingsConfirmation(
                                title: "Reset Settings",
                                message: "Reset all application settings to their default values? The app will remain in recovery mode.",
                                confirmTitle: "Reset",
                                action: {
                                    AppRecoveryService.resetUserDefaults()
                                    showCompletion(
                                        message: "Application settings reset to defaults. Quit recovery mode and relaunch normally when ready."
                                    )
                                }
                            )
                        }

                        recoveryActionButton(
                            title: "Wipe Store",
                            systemImage: "trash.circle.fill",
                            role: .destructive
                        ) {
                            confirmation = SettingsConfirmation(
                                title: "Wipe Store",
                                message: "Delete the local SwiftData store and relaunch the app into a fresh empty state?",
                                confirmTitle: "Wipe",
                                action: {
                                    Task { @MainActor in
                                        await wipeStoreAndRelaunch()
                                    }
                                }
                            )
                        }

                        recoveryActionButton(
                            title: "Restore Backup",
                            systemImage: "arrow.down.doc",
                            role: .destructive
                        ) {
                            confirmation = SettingsConfirmation(
                                title: "Restore Backup",
                                message: "Choose a full backup file next. The current local store will be replaced after the file is validated.",
                                confirmTitle: "Choose File",
                                action: {
                                    selectedImportMode = .backup
                                    showFileImporter = true
                                }
                            )
                        }

                        recoveryActionButton(
                            title: "Generic Import",
                            systemImage: "square.and.arrow.down",
                            role: .destructive
                        ) {
                            confirmation = SettingsConfirmation(
                                title: "Generic Import",
                                message: "Choose a project, conversation, prompt, voice, or model JSON file next. The current local store will be replaced after validation.",
                                confirmTitle: "Choose File",
                                action: {
                                    selectedImportMode = .genericImport
                                    showFileImporter = true
                                }
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                        Text("Notes")
                            .font(.headline)
                        Text("Reset Settings only changes UserDefaults. Wipe Store deletes local data and relaunches. Restore Backup and Generic Import validate the file first, then wipe and repopulate the store before relaunching.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, AppDefaults.paddingSmall)
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .alert(completionMessage, isPresented: $showCompletionAlert) {
                Button("OK", role: .cancel) { }
            }
            .settingsConfirmationDialog($confirmation)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                guard let selectedImportMode else { return }
                self.selectedImportMode = nil

                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { @MainActor in
                        await performRecoveryImport(mode: selectedImportMode, url: url)
                    }
                case .failure(let error):
                    if (error as NSError).code != CocoaError.userCancelled.rawValue {
                        showCompletion(message: "Recovery import failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        private func showCompletion(message: String) {
            completionMessage = message
            showCompletionAlert = true
        }

        @MainActor
        private func wipeStoreAndRelaunch() async {
            do {
                try AppRecoveryService.wipePersistentStore()
                try AppRecoveryService.relaunchNormalApp()
            } catch {
                showCompletion(message: "Store wipe failed: \(error.localizedDescription)")
            }
        }

        @MainActor
        private func performRecoveryImport(mode: RecoveryImportMode, url: URL) async {
            do {
                switch mode {
                case .backup:
                    try await AppRecoveryService.validateBackup(from: url)
                case .genericImport:
                    try await AppRecoveryService.validateImport(from: url)
                }

                try AppRecoveryService.wipePersistentStore()

                let bootstrap = AppBootstrap.live()
                switch mode {
                case .backup:
                    try await AppRecoveryService.restoreBackup(from: url, into: bootstrap.modelContainer.mainContext)
                case .genericImport:
                    _ = try await AppRecoveryService.importData(from: url, into: bootstrap.modelContainer.mainContext)
                }
                bootstrap.queryManager.ensureSystemConversation()
                try AppRecoveryService.relaunchNormalApp()
            } catch {
                showCompletion(message: "Recovery import failed: \(error.localizedDescription)")
            }
        }

        @ViewBuilder
        private func recoveryActionButton(
            title: String,
            systemImage: String,
            role: ButtonRole? = nil,
            action: @escaping () -> Void
        ) -> some View {
            Button(role: role, action: action) {
                HStack(spacing: AppDefaults.paddingSmall) {
                    Label(title, systemImage: systemImage)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
    }

    private struct StartupRecoveryPlaceholderView: View {
        var body: some View {
            VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                Text("Recovery mode active")
                    .font(.headline)
                Text("Use the main recovery window to reset settings, wipe the store, restore a backup, or import data.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

#endif

// MARK: - View Extensions

extension View {
    /// Hides the keyboard on iOS devices
    func hideKeyboard() {
        #if os(iOS)
            vxAtelierPro.log.debug("Hiding keyboard")
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
