import SwiftUI

struct ApplicationSettingsDestinationContentView: View {
    let destination: SettingsDestination

    var body: some View {
        destination.content
    }
}
