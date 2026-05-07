import SwiftUI

/// Defines the available appearance styles for the application.
enum AppearanceStyle: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { self.rawValue }

    /// Maps the enum case to the SwiftUI ColorScheme.
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil // nil uses the system setting
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
} 