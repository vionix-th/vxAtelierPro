import SwiftUI

/// Thin wrapper that renders one shared settings destination.
struct SettingsDestinationView: View {
    let destination: SettingsDestination

    var body: some View {
        destination.content
    }
}
