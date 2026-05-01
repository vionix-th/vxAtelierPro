import SwiftUI

/// Content filter defining which bucket (active/archive/trash) is visible.
/// Raw values are kept stable to avoid altering persisted defaults.
enum ContentFilter: String, CaseIterable, Identifiable {
    case active = "chats"
    case archived = "archive"
    case trashed = "trash"

    var id: String { rawValue }
}

@MainActor
func setContentFilter(
    _ filter: ContentFilter,
    contentFilter: Binding<ContentFilter>,
    animated: Bool = true
) {
    let update = {
        contentFilter.wrappedValue = filter
    }
    if animated {
        withAnimation(.easeInOut(duration: 0.3)) {
            update()
        }
    } else {
        update()
    }
}
