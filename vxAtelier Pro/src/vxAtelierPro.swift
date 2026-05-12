import Observation
import SwiftData
import SwiftUI

#if os(macOS)
    import AppKit
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
    // MARK: - Platform-Specific Properties

    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppBootstrap.AppDelegate.self) private var appDelegate
    #endif

    /// Centralized logging system for the application
    /// Uses LoggingService to route messages to both system logger and status bar
    static let log = LoggingService.shared

    // MARK: - Platform Detection

    #if os(iOS)
        static let iOS: Bool = true
    #else
        static let iOS: Bool = false
    #endif

    #if os(macOS)
        static let macOS: Bool = true
    #else
        static let macOS: Bool = false
    #endif

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

    /// Shared app bootstrap and dependency graph
    private let bootstrap: AppBootstrap

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

        vxAtelierPro.log.debug("Initializing app bootstrap")
        self.bootstrap = AppBootstrap.live()
        vxAtelierPro.log.debug("App bootstrap initialized")

        #if os(macOS)
            vxAtelierPro.log.debug("Installing bootstrap launch hooks")
            bootstrap.installLaunchHooks(on: appDelegate)
            vxAtelierPro.log.debug("Bootstrap launch hooks installed")
        #endif

        bootstrap.performLaunchBootstrap()

        vxAtelierPro.log.debug("vxAtelierPro initialized")
    }

    // MARK: - Scene Configuration

    var body: some Scene {
        WindowGroup("Main Window", id: "mainWindow") {
            AppShellView()
                .preferredColorScheme(effectiveColorScheme)
                .bootstrapped(with: bootstrap)
        }
        .commands {
            AppCommands()
        }

        #if os(macOS)
            Window("Utility", id: "utilityPanel") {
                UtilityPanelView()
                    .preferredColorScheme(effectiveColorScheme)
                    .bootstrapped(with: bootstrap)
            }
            .windowResizability(.contentSize)
            .defaultSize(width: 420, height: 140)

            MenuBarExtra("vxAtelier Pro", systemImage: "message.circle") {
                MenuBarContent()
            }
        #endif
    }
}

// MARK: - Platform-Specific Components

#if os(macOS)
    /// Menu bar extra content for macOS
    struct MenuBarContent: View {
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            Button("New Window") {
                openWindow(id: "mainWindow")
                vxAtelierPro.log.info("Opened new window from menu bar")
            }

            Divider()

            Button("Quit vxAtelier Pro") {
                vxAtelierPro.log.notice("Application quit requested from menu bar")
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
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
