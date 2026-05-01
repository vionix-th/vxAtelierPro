import Foundation
import SwiftData

@Model
final class ResponseRunItem {
    var providerID: String
    var endpointFamily: String
    var requestedModelID: String
    var actualModelID: String?
    var requestID: String?
    var statusRaw: String
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
    var statusCode: Int?
    var retryAfter: String?
    var responseMetadataJSON: String?
    var errorMessage: String?
    var startedAt: Date
    var completedAt: Date?

    @Relationship(deleteRule: .nullify) var turn: ConversationTurn?

    init(
        providerID: LLMProviderID,
        endpointFamily: LLMEndpointFamily,
        requestedModelID: String,
        actualModelID: String? = nil,
        requestID: String? = nil,
        status: LLMRunStatus = .pending,
        usage: LLMUsage? = nil,
        metadata: LLMResponseMetadata? = nil,
        errorMessage: String? = nil,
        turn: ConversationTurn? = nil
    ) {
        self.providerID = providerID.rawValue
        self.endpointFamily = endpointFamily.rawValue
        self.requestedModelID = requestedModelID
        self.actualModelID = actualModelID
        self.requestID = requestID
        self.statusRaw = status.rawValue
        self.inputTokens = usage?.inputTokens
        self.outputTokens = usage?.outputTokens
        self.totalTokens = usage?.totalTokens
        self.statusCode = metadata?.statusCode
        self.retryAfter = metadata?.retryAfter
        self.responseMetadataJSON = metadata.flatMap(Self.metadataJSON(from:))
        self.errorMessage = errorMessage
        self.startedAt = Date()
        self.turn = turn
    }

    var status: LLMRunStatus {
        get { LLMRunStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    func transition(to newStatus: LLMRunStatus) throws {
        guard Self.canTransition(from: status, to: newStatus) else {
            throw LLMProviderError.invalidConfiguration("Invalid response run transition \(status.rawValue) -> \(newStatus.rawValue).")
        }
        status = newStatus
    }

    func applyUsage(_ usage: LLMUsage) {
        inputTokens = usage.inputTokens
        outputTokens = usage.outputTokens
        totalTokens = usage.totalTokens
    }

    func applyMetadata(_ metadata: LLMResponseMetadata) {
        requestID = metadata.requestID ?? requestID
        statusCode = metadata.statusCode
        retryAfter = metadata.retryAfter
        responseMetadataJSON = Self.metadataJSON(from: metadata)
    }

    private static func metadataJSON(from metadata: LLMResponseMetadata) -> String? {
        guard let data = try? JSONEncoder().encode(metadata) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func canTransition(from current: LLMRunStatus, to next: LLMRunStatus) -> Bool {
        if current == next { return true }
        switch (current, next) {
        case (.pending, .streaming),
             (.streaming, .awaitingTools),
             (.streaming, .completed),
             (.streaming, .failed),
             (.streaming, .cancelled),
             (.awaitingTools, .completed),
             (.awaitingTools, .failed),
             (.awaitingTools, .cancelled):
            return true
        default:
            return false
        }
    }
}
