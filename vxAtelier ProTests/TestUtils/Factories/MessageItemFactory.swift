import Foundation
@testable import vxAtelier_Pro_debug

final class MessageItemFactory: BaseTestFactory<MessageItem>, TestDataFactory {
    typealias Model = MessageItem
    
    func create() -> MessageItem {
        return MessageItem(
            role: "user",
            content: ContentItem("Test message \(uniqueIdentifier())"),
            timestamp: recentTimestamp(),
            toolCallId: nil,
            toolCallsData: nil
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
                message.content = ContentItem(content)
            }
        }
    }
    
    func createAssistantMessage(content: String? = nil) -> MessageItem {
        create { message in
            message.role = "assistant"
            if let content = content {
                message.content = ContentItem(content)
            }
        }
    }
    
    func createToolCallMessage() -> MessageItem {
        create { message in
            message.role = "assistant"
            message.toolCallId = uniqueIdentifier()
            let toolCall = GenericToolCall(
                id: uniqueIdentifier(),
                name: "test_tool",
                arguments: "{\"arg1\": \"value1\"}",
                configuration: nil
            )
            if let data = try? JSONEncoder().encode(toolCall) {
                message.toolCallsData = [data]
            }
        }
    }
    
    func createToolResultMessage() -> MessageItem {
        create { message in
            message.role = "tool"
            message.content = ContentItem("Tool result \(uniqueIdentifier())")
        }
    }
    
    func createWithMarkdown() -> MessageItem {
        create { message in
            message.content = ContentItem("# Heading\n\nTest markdown content")
        }
    }
}
