import SwiftUI

/// A reusable action button with icon and text for settings screens
struct ActionButton: View {
    let title: String
    let iconName: String
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                Image(systemName: iconName)
                Text(title).frame(maxWidth: .infinity)
            }
        }
        .padding(AppDefaults.paddingMedium)
    }
} 