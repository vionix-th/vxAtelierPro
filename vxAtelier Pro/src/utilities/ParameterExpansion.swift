import SwiftUI

func expandVariables(_ inString: String, conversation: ConversationItem? = nil) -> String {
    var rval = inString
    
    let variables: [String: Any] = [
        "$conversationid": conversation.map { "\"\(StableHash.md5Hex(String(describing: $0.id)))\"" } ?? "[ERROR: NO CONVERSATION ID]",
        "$isodate": {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date())
        },
        "$day": {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: Date())
        }
    ]
    
    vxAtelierPro.log.debug("Expanding variables in string")
    var expandedCount = 0
    
    for (key, value) in variables {
        let replacement: String
        
        if let closure = value as? () -> String {
            replacement = closure()
        } else if let staticValue = value as? String {
            replacement = staticValue
        } else {
            vxAtelierPro.log.error("Invalid variable type for key '\(key)'")
            continue
        }
        
        let oldString = rval
        rval = rval.replacingOccurrences(of: key, with: replacement, options: .caseInsensitive, range: nil)
        if oldString != rval {
            expandedCount += 1
            vxAtelierPro.log.debug("Expanded '\(key)' to '\(replacement)'")
        }
    }
    
    vxAtelierPro.log.debug("Completed with \(expandedCount) replacements")
    return rval
}
