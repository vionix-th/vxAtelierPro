import Foundation

#if os(macOS)
enum MacOSApplicationSettingsSelection {
    static func select(_ destination: SettingsDestination?, defaults: UserDefaults = .standard) {
        let resolvedDestination = destination ?? .general
        defaults.set(resolvedDestination.rawValue, forKey: AppSettings.Keys.selectedSettingsDestination)
        defaults.set(
            MacOSSettingsSection.section(containing: resolvedDestination).rawValue,
            forKey: AppSettings.Keys.selectedMacSettingsSection
        )
    }
}
#endif
