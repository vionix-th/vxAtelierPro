import SwiftData

enum SidebarSelection: Hashable {
    case project(PersistentIdentifier)
    case conversation(PersistentIdentifier)

    var conversationID: PersistentIdentifier? {
        if case .conversation(let id) = self { return id }
        return nil
    }

    var projectID: PersistentIdentifier? {
        if case .project(let id) = self { return id }
        return nil
    }
}

enum ProjectRoute: Hashable {
    case conversation(PersistentIdentifier)
}

struct ProjectConversationSelection: Equatable {
    let projectID: PersistentIdentifier
    let conversationID: PersistentIdentifier
}

func selectionMatches(_ selection: SidebarSelection?, item: any PersistentModel) -> Bool {
    if let conversation = item as? ConversationItem {
        return selection == .conversation(conversation.id)
    }
    if let project = item as? ProjectItem {
        return selection == .project(project.id)
    }
    return false
}
