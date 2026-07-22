import Foundation
import SwiftData

enum ConversationMessageRole: String, Equatable {
    case user
    case assistant
}

struct ConversationMessageReference: Equatable {
    let conversationID: PersistentIdentifier
    let turnID: PersistentIdentifier
    let eventID: PersistentIdentifier?
    let messageID: PersistentIdentifier
}

struct ConversationToolCallSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let argumentsJSON: String
    let status: String
}

struct ConversationToolResultSnapshot: Identifiable, Equatable {
    let id: PersistentIdentifier
    let toolName: String
    let text: String

    var isLong: Bool {
        text.count > 600 || text.components(separatedBy: "\n").count > 12
    }
}

struct ConversationMessageSnapshot: Identifiable, Equatable {
    let reference: ConversationMessageReference
    let role: ConversationMessageRole
    let text: String
    let toolCalls: [ConversationToolCallSnapshot]
    let toolResults: [ConversationToolResultSnapshot]
    let pendingToolResultCount: Int
    let isBookmarked: Bool

    var id: ConversationScrollTarget {
        .message(reference.messageID)
    }
}

struct ConversationPresentationStyle: Equatable {
    let rendersMarkdown: Bool
    let avatarImageData: Data?
}

struct ConversationRunPresentation: Equatable {
    let status: ProviderRunStatus
    let errorMessage: String?
}

struct ConversationStreamPresentation: Equatable {
    let turnID: PersistentIdentifier?
    let latestRun: ConversationRunPresentation?
}

struct ConversationRunRevision: Equatable {
    let id: PersistentIdentifier
    let status: String
    let errorMessage: String?
}

struct ConversationToolCallRevision: Equatable {
    let messageID: PersistentIdentifier
    let callID: String
    let status: String
}

struct ConversationTimelineRevision: Equatable {
    let turnIDs: [PersistentIdentifier]
    let eventIDs: [PersistentIdentifier]
    let runs: [ConversationRunRevision]
    let toolCalls: [ConversationToolCallRevision]
}

struct ConversationPresentationSnapshot: Equatable {
    let conversationID: PersistentIdentifier
    let title: String
    let rows: [ConversationMessageSnapshot]
    let style: ConversationPresentationStyle
    let stream: ConversationStreamPresentation
    let revision: ConversationTimelineRevision
    let isActive: Bool
    let isUtilityConversation: Bool

    var messageIDs: Set<PersistentIdentifier> {
        Set(rows.map(\.reference.messageID))
    }
}

struct ConversationPlaylistSnapshot: Identifiable, Equatable {
    let id: PersistentIdentifier
    let name: String
}

enum ConversationMessageAction: Equatable {
    case bookmark
    case removeBookmark
    case fork
    case addToNewPlaylist
    case addToPlaylist(PersistentIdentifier)
    case select
    case copyText
    case copyJSON
    case delete
}

enum ConversationPresentationBuilder {
    static func build(conversation: ConversationItem) -> ConversationPresentationSnapshot {
        let turns = conversation.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
        var rows: [ConversationMessageSnapshot] = []
        var eventIDs: [PersistentIdentifier] = []
        var runRevisions: [ConversationRunRevision] = []
        var toolCallRevisions: [ConversationToolCallRevision] = []

        for turn in turns {
            let userBookmarked = turn.bookmarks.contains { $0.target == nil }
            rows.append(
                ConversationMessageSnapshot(
                    reference: ConversationMessageReference(
                        conversationID: conversation.persistentModelID,
                        turnID: turn.persistentModelID,
                        eventID: nil,
                        messageID: turn.userMessage.persistentModelID
                    ),
                    role: .user,
                    text: turn.userMessage.textContent,
                    toolCalls: [],
                    toolResults: [],
                    pendingToolResultCount: 0,
                    isBookmarked: userBookmarked
                )
            )

            let indexedEvents = turn.events.enumerated().sorted {
                if $0.element.timestamp != $1.element.timestamp {
                    return $0.element.timestamp < $1.element.timestamp
                }
                return $0.offset < $1.offset
            }
            eventIDs.append(contentsOf: indexedEvents.map { $0.element.persistentModelID })

            let bookmarkedEventIDs = Set(
                turn.bookmarks.compactMap { $0.target?.persistentModelID }
            )
            for indexedEvent in indexedEvents where indexedEvent.element.type == .assistant {
                let event = indexedEvent.element
                let message = event.message
                let toolState = toolPresentation(
                    calls: message.orderedToolCallItems,
                    events: turn.events
                )
                rows.append(
                    ConversationMessageSnapshot(
                        reference: ConversationMessageReference(
                            conversationID: conversation.persistentModelID,
                            turnID: turn.persistentModelID,
                            eventID: event.persistentModelID,
                            messageID: message.persistentModelID
                        ),
                        role: .assistant,
                        text: message.textContent,
                        toolCalls: toolState.calls,
                        toolResults: toolState.results,
                        pendingToolResultCount: toolState.pendingCount,
                        isBookmarked: bookmarkedEventIDs.contains(event.persistentModelID)
                    )
                )
                toolCallRevisions.append(contentsOf: message.orderedToolCallItems.map { call in
                    ConversationToolCallRevision(
                        messageID: message.persistentModelID,
                        callID: call.callID,
                        status: call.statusRaw
                    )
                })
            }

            runRevisions.append(contentsOf: turn.responseRuns
                .sorted { $0.startedAt < $1.startedAt }
                .map { run in
                    ConversationRunRevision(
                        id: run.persistentModelID,
                        status: run.statusRaw,
                        errorMessage: run.errorMessage
                    )
                })
        }

        let latestTurn = turns.last
        let latestRun = latestTurn?.responseRuns.sorted { $0.startedAt < $1.startedAt }.last
        let projectName = conversation.project?.name
        let title = projectName.map { "\(conversation.title)@\($0)" } ?? conversation.title
        let avatarImageData = conversation.options.avatarImageData
            ?? conversation.project?.defaultOptions.avatarImageData

        return ConversationPresentationSnapshot(
            conversationID: conversation.persistentModelID,
            title: title,
            rows: rows,
            style: ConversationPresentationStyle(
                rendersMarkdown: conversation.options.isMarkdownEnabled,
                avatarImageData: avatarImageData
            ),
            stream: ConversationStreamPresentation(
                turnID: latestTurn?.persistentModelID,
                latestRun: latestRun.map {
                    ConversationRunPresentation(status: $0.status, errorMessage: $0.errorMessage)
                }
            ),
            revision: ConversationTimelineRevision(
                turnIDs: turns.map(\.persistentModelID),
                eventIDs: eventIDs,
                runs: runRevisions,
                toolCalls: toolCallRevisions
            ),
            isActive: conversation.status == .active,
            isUtilityConversation: conversation.isUtilityConversation
        )
    }

    private struct ToolPresentation {
        let calls: [ConversationToolCallSnapshot]
        let results: [ConversationToolResultSnapshot]
        let pendingCount: Int
    }

    private static func toolPresentation(
        calls: [ToolCallItem],
        events: [TurnEvent]
    ) -> ToolPresentation {
        let sortedCalls = calls.sorted { $0.index < $1.index }
        var callByResultID: [String: ToolCallItem] = [:]
        for call in sortedCalls {
            callByResultID[call.callID] = call
            if let providerCallID = call.providerCallID, !providerCallID.isEmpty {
                callByResultID[providerCallID] = call
            }
        }

        var completedCallIDs = Set<String>()
        let results = events
            .filter { $0.type == .toolResult }
            .compactMap { event -> (Date, ConversationToolResultSnapshot)? in
                guard let toolCallID = event.message.toolCallId,
                      let call = callByResultID[toolCallID] else {
                    return nil
                }
                completedCallIDs.insert(call.callID)
                return (
                    event.timestamp,
                    ConversationToolResultSnapshot(
                        id: event.persistentModelID,
                        toolName: call.name,
                        text: event.message.textContent
                    )
                )
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)

        return ToolPresentation(
            calls: sortedCalls.map {
                ConversationToolCallSnapshot(
                    id: $0.callID,
                    name: $0.name,
                    argumentsJSON: $0.argumentsJSON,
                    status: $0.statusRaw
                )
            },
            results: results,
            pendingCount: sortedCalls.reduce(0) { partial, call in
                partial + (completedCallIDs.contains(call.callID) ? 0 : 1)
            }
        )
    }
}
