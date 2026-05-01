import Foundation
import SwiftData

@Model
final class ToolCallItem {
    var callID: String
    var providerCallID: String?
    var index: Int
    var name: String
    var argumentsJSON: String
    var statusRaw: String
    var errorMessage: String?
    var createdAt: Date
    var completedAt: Date?

    @Relationship(deleteRule: .nullify) var assistantMessage: MessageItem?
    @Relationship(deleteRule: .nullify) var resultMessage: MessageItem?

    init(
        callID: String,
        providerCallID: String? = nil,
        index: Int,
        name: String,
        argumentsJSON: String,
        status: LLMToolCallStatus = .readyToExecute,
        assistantMessage: MessageItem? = nil,
        resultMessage: MessageItem? = nil
    ) {
        self.callID = callID
        self.providerCallID = providerCallID
        self.index = index
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.statusRaw = status.rawValue
        self.createdAt = Date()
        self.assistantMessage = assistantMessage
        self.resultMessage = resultMessage
    }

    var status: LLMToolCallStatus {
        get { LLMToolCallStatus(rawValue: statusRaw) ?? .readyToExecute }
        set { statusRaw = newValue.rawValue }
    }

    func asDomainToolCall() -> LLMToolCall {
        LLMToolCall(id: callID, callID: providerCallID, index: index, name: name, argumentsJSON: argumentsJSON)
    }

    func asGenericToolCall(configuration: [String: Any]? = nil, context: Any? = nil) -> GenericToolCall {
        GenericToolCall(id: callID, name: name, arguments: argumentsJSON, configuration: configuration, context: context)
    }
}
