import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum ExportUtils {
    // MARK: - Clipboard Operations
    
    static func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }
    
    static func copyToClipboard<T: Encodable>(_ item: T) {
        do {
            let jsonString = try encodeToString(item)
            copyToClipboard(jsonString)
        } catch {
            vxAtelierPro.log.error("Failed to encode item as JSON: \(error.localizedDescription)")
        }
    }
    
    // MARK: - JSON Encoding
    
    static func encodeToData<T: Encodable>(_ item: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(item)
    }
    
    static func encodeToString<T: Encodable>(_ item: T) throws -> String {
        let data = try encodeToData(item)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(item, EncodingError.Context(
                codingPath: [],
                debugDescription: "Failed to convert JSON data to string"
            ))
        }
        return string
    }
    
    // MARK: - JSON Decoding
    static func decodeFromData<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
    

} 