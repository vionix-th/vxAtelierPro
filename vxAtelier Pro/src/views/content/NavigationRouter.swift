import Observation
import SwiftData

@Observable
@MainActor
final class NavigationRouter {
    var selection: SidebarSelection? = nil
    private var projectPaths: [PersistentIdentifier: [ProjectRoute]] = [:]

    var activeConversationID: PersistentIdentifier? {
        switch selection {
        case .conversation(let id):
            return id
        case .project(let projectID):
            if case .conversation(let conversationID)? = projectPaths[projectID]?.last {
                return conversationID
            }
            return nil
        case .none:
            return nil
        }
    }

    func setSelection(_ newSelection: SidebarSelection?) {
        guard selection != newSelection else { return }

        if case .project(let previousID) = selection,
           case .project(let nextID)? = newSelection,
           previousID != nextID {
            projectPaths[previousID] = []
        }

        if case .project(let previousID) = selection,
           newSelection?.projectID != previousID {
            projectPaths[previousID] = []
        }

        selection = newSelection
    }

    func path(for projectID: PersistentIdentifier) -> [ProjectRoute] {
        projectPaths[projectID] ?? []
    }

    func setPath(_ path: [ProjectRoute], for projectID: PersistentIdentifier) {
        guard projectPaths[projectID] != path else { return }
        projectPaths[projectID] = path
    }

    func clearPath(for projectID: PersistentIdentifier) {
        guard projectPaths[projectID]?.isEmpty == false else { return }
        projectPaths[projectID] = []
    }

    func openConversation(_ conversationID: PersistentIdentifier, in projectID: PersistentIdentifier?) {
        if let projectID {
            setSelection(.project(projectID))
            setPath([.conversation(conversationID)], for: projectID)
        } else {
            setSelection(.conversation(conversationID))
        }
    }
}
