import Foundation
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

final class ConversationFactory: BaseTestFactory<ConversationItem>, TestDataFactory {
    typealias Model = ConversationItem
    
    private let turnFactory: ConversationTurnFactory
    private let optionsFactory: ConversationOptionsFactory
    
    init(turnFactory: ConversationTurnFactory = ConversationTurnFactory(),
         optionsFactory: ConversationOptionsFactory = ConversationOptionsFactory()) {
        self.turnFactory = turnFactory
        self.optionsFactory = optionsFactory
    }
    
    func create() -> ConversationItem {
        let options = optionsFactory.create()
        let conversation = ConversationItem(
            timestamp: recentTimestamp(),
            title: "Test Conversation \(uniqueIdentifier())",
            options: options
        )
        return conversation
    }
    
    func create(overrides: (inout ConversationItem) -> Void) -> ConversationItem {
        var conversation = create()
        overrides(&conversation)
        return conversation
    }
    
    // Helper methods for common test scenarios
    
    func createWithTurns(count: Int = 1) -> ConversationItem {
        let conversation = create()
        for i in 0..<count {
            let turn = turnFactory.create(conversation: conversation) { turn in
                turn.sequenceNumber = i
            }
            conversation.turns.append(turn)
        }
        return conversation
    }
    
    func createWithProject(_ project: ProjectItem? = nil) -> ConversationItem {
        create { conversation in
            conversation.project = project
        }
    }
    
    func createArchived() -> ConversationItem {
        create { conversation in
            conversation.status = .archived
        }
    }
    
    func createTrashed() -> ConversationItem {
        create { conversation in
            conversation.status = .trashed
        }
    }
    
    func createSystem() -> ConversationItem {
        create { conversation in
            conversation.purpose = .system
        }
    }
}
