import Foundation
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

final class ConversationTurnFactory: BaseTestFactory<ConversationTurn>, TestDataFactory {
    typealias Model = ConversationTurn
    
    private let messageFactory: MessageItemFactory
    
    init(messageFactory: MessageItemFactory = MessageItemFactory()) {
        self.messageFactory = messageFactory
    }
    
    func create(conversation: ConversationItem) -> ConversationTurn {
        let userMessage = messageFactory.createUserMessage()
        return ConversationTurn(
            sequenceNumber: 0,
            timestamp: recentTimestamp(),
            userMessage: userMessage,
            conversation: conversation
        )
    }
    
    func create() -> ConversationTurn {
        fatalError("ConversationTurnFactory.create() requires a ConversationItem. Use create(conversation:) instead.")
    }

    func create(overrides: (inout ConversationTurn) -> Void) -> ConversationTurn {
        fatalError("ConversationTurnFactory.create(overrides:) requires a ConversationItem. Use create(conversation:overrides:) instead.")
    }

    func create(conversation: ConversationItem, overrides: (inout ConversationTurn) -> Void) -> ConversationTurn {
        var turn = create(conversation: conversation)
        overrides(&turn)
        return turn
    }
    
    // Helper methods for common test scenarios
    
    func createWithEvents(count: Int = 1) -> ConversationTurn {
        create { turn in
            for _ in 0..<count {
                let event = messageFactory.createAssistantMessage()
                turn.events.append(TurnEvent(type: .assistant, timestamp: event.timestamp, message: event, turn: turn))
            }
        }
    }
    
    func createWithToolCalls() -> ConversationTurn {
        create { turn in
            let toolCallMessage = messageFactory.createToolCallMessage()
            let toolResultMessage = messageFactory.createToolResultMessage()
            turn.events.append(TurnEvent(type: .toolCall, timestamp: toolCallMessage.timestamp, message: toolCallMessage, turn: turn))
            turn.events.append(TurnEvent(type: .toolResult, timestamp: toolResultMessage.timestamp, message: toolResultMessage, turn: turn))
        }
    }
}
