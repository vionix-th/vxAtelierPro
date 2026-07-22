import Observation
import Foundation
import SwiftData

struct ConversationScrollRequest: Equatable {
    let requestID: UUID
    let conversationID: PersistentIdentifier
    let messageID: PersistentIdentifier
}

@Observable
@MainActor
final class NavigationRouter {
    var selection: SidebarSelection? = nil
    private(set) var conversationScrollRequest: ConversationScrollRequest?
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

    @discardableResult
    func clearIfShowing(conversationID: PersistentIdentifier, projectID: PersistentIdentifier?) -> Bool {
        if selection == .conversation(conversationID) {
            setSelection(nil)
            return true
        }

        guard let projectID,
              selection == .project(projectID),
              activeConversationID == conversationID else {
            return false
        }

        clearPath(for: projectID)
        return true
    }

    @discardableResult
    func clearIfShowing(projectID: PersistentIdentifier) -> Bool {
        guard selection == .project(projectID) else { return false }
        setSelection(nil)
        return true
    }

    func openConversation(
        _ conversationID: PersistentIdentifier,
        in projectID: PersistentIdentifier?,
        scrollTo messageID: PersistentIdentifier? = nil
    ) {
        if let messageID {
            conversationScrollRequest = ConversationScrollRequest(
                requestID: UUID(),
                conversationID: conversationID,
                messageID: messageID
            )
        } else {
            conversationScrollRequest = nil
        }

        if let projectID {
            setSelection(.project(projectID))
            setPath([.conversation(conversationID)], for: projectID)
        } else {
            setSelection(.conversation(conversationID))
        }
    }

    func consumeConversationScrollRequest(_ requestID: UUID) {
        guard conversationScrollRequest?.requestID == requestID else { return }
        conversationScrollRequest = nil
    }
}
