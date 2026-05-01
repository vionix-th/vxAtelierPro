import Foundation
import SwiftData

@Model
final class MessageContentPartItem {
    var index: Int
    var kindRaw: String
    var text: String?
    var mimeType: String?
    var dataBase64: String?
    var sourceURL: String?

    init(
        index: Int,
        kind: LLMContentPart.Kind = .text,
        text: String? = nil,
        mimeType: String? = nil,
        dataBase64: String? = nil,
        sourceURL: String? = nil
    ) {
        self.index = index
        self.kindRaw = kind.rawValue
        self.text = text
        self.mimeType = mimeType
        self.dataBase64 = dataBase64
        self.sourceURL = sourceURL
    }

    var kind: LLMContentPart.Kind {
        get { LLMContentPart.Kind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    func asDomainPart() -> LLMContentPart {
        LLMContentPart(kind: kind, text: text, mimeType: mimeType, dataBase64: dataBase64, sourceURL: sourceURL)
    }
}
