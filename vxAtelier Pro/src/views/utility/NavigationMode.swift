import SwiftUI

enum NavigationMode: String, CaseIterable, Identifiable {
    case chats = "chats"
    case archive = "archive"
    case trash = "trash"

    var id: String { rawValue }
}

@MainActor
func setNavigationMode(
    _ mode: NavigationMode,
    navigationMode: Binding<NavigationMode>,
    animated: Bool = true
) {
    let update = {
        navigationMode.wrappedValue = mode
    }
    if animated {
        withAnimation(.easeInOut(duration: 0.3)) {
            update()
        }
    } else {
        update()
    }
}
