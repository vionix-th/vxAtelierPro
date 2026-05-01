import Foundation
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

final class MessageItemFactory: BaseTestFactory<MessageItem>, TestDataFactory {
    typealias Model = MessageItem
    
    func create() -> MessageItem {
        return MessageItem(
            role: "user",
            text: "Test message \(uniqueIdentifier())",
            timestamp: recentTimestamp()
        )
    }
    
    func create(overrides: (inout MessageItem) -> Void) -> MessageItem {
        var message = create()
        overrides(&message)
        return message
    }
    
    // Helper methods for common test scenarios
    
    func createUserMessage(content: String? = nil) -> MessageItem {
        create { message in
            message.role = "user"
            if let content = content {
                message.setContentParts([MessageContentPartItem(index: 0, kind: .text, text: content)])
            }
        }
    }
    
    func createAssistantMessage(content: String? = nil) -> MessageItem {
        create { message in
            message.role = "assistant"
            if let content = content {
                message.setContentParts([MessageContentPartItem(index: 0, kind: .text, text: content)])
            }
        }
    }
    
    func createToolCallMessage() -> MessageItem {
        create { message in
            message.role = "assistant"
            message.toolCallId = uniqueIdentifier()
            message.setToolCalls([
                LLMToolCall(
                    id: uniqueIdentifier(),
                    index: 0,
                    name: "test_tool",
                    argumentsJSON: "{\"arg1\": \"value1\"}"
                )
            ])
        }
    }
    
    func createToolResultMessage() -> MessageItem {
        create { message in
            message.role = "tool"
            message.setContentParts([MessageContentPartItem(index: 0, kind: .toolResult, text: "Tool result \(uniqueIdentifier())")])
        }
    }
    
    func createWithMarkdown() -> MessageItem {
        create { message in
            message.setContentParts([MessageContentPartItem(index: 0, kind: .text, text: "# Heading\n\nTest markdown content")])
        }
    }
}
