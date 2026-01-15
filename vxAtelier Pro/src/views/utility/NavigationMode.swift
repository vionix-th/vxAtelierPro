import SwiftUI

enum NavigationMode {
    case chats
    case archive
    case trash
}

@MainActor
func setNavigationMode(
    _ mode: NavigationMode,
    showArchived: Binding<Bool>,
    showTrashed: Binding<Bool>,
    animated: Bool = true
) {
    let update = {
        showArchived.wrappedValue = (mode == .archive)
        showTrashed.wrappedValue = (mode == .trash)
    }
    if animated {
        withAnimation(.easeInOut(duration: 0.3)) {
            update()
        }
    } else {
        update()
    }
}
