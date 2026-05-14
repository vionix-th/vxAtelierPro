import SwiftUI

enum MacOSSettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case providers
    case content
    case speech
    case security
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .providers: "Providers"
        case .content: "Content"
        case .speech: "Speech"
        case .security: "Security"
        case .advanced: "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .providers: "network"
        case .content: "text.bubble.fill"
        case .speech: "person.wave.2.fill"
        case .security: "lock.shield"
        case .advanced: "wrench.and.screwdriver"
        }
    }

    var destinations: [SettingsDestination] {
        switch self {
        case .general:
            [.general]
        case .providers:
            [.api, .models, .webSearch]
        case .content:
            [.prompts]
        case .speech:
            [.tts]
        case .security:
            [.permissions]
        case .advanced:
            [.maintenance, .developer, .logSources]
        }
    }

    static func section(containing destination: SettingsDestination?) -> MacOSSettingsSection {
        guard let destination else { return .general }
        return allCases.first { $0.destinations.contains(destination) } ?? .general
    }
}
