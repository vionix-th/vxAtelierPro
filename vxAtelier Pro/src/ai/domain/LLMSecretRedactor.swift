import Foundation

enum LLMSecretRedactor {
    private static let sensitiveHeaderFragments = [
        "authorization",
        "api-key",
        "apikey",
        "token",
        "cookie",
        "secret",
        "credential"
    ]

    private static let redactionPatterns = [
        #"(?i)bearer\s+[A-Za-z0-9._~+/=-]+"#,
        #"(?i)(sk|sk-proj|xox[baprs]?)-[A-Za-z0-9._-]{8,}"#,
        #"(?i)("?(api[_-]?key|access[_-]?token|authorization|secret)"?\s*[:=]\s*")([^"]+)(")"#
    ]

    static func redactedHeaders(_ headers: [String: String]) -> [String: String] {
        headers.mapValuesWithKeys { key, value in
            isSensitiveHeader(key) ? "[redacted]" : redact(value)
        }
    }

    static func redact(_ text: String, knownSecrets: [String] = []) -> String {
        var output = text
        for secret in knownSecrets where secret.count >= 4 {
            output = output.replacingOccurrences(of: secret, with: "[redacted]")
        }
        for pattern in redactionPatterns {
            output = replace(pattern: pattern, in: output)
        }
        return output
    }

    static func redactAndLimit(_ text: String, maxCharacters: Int) -> String {
        let redacted = redact(text)
        guard redacted.count > maxCharacters else { return redacted }
        return String(redacted.prefix(maxCharacters)) + "... [truncated]"
    }

    private static func isSensitiveHeader(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        return sensitiveHeaderFragments.contains { lowercased.contains($0) }
    }

    private static func replace(pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if pattern.contains("api[_-]?key") || pattern.contains("access[_-]?token") {
            return regex.stringByReplacingMatches(
                in: text,
                range: range,
                withTemplate: "$1[redacted]$4"
            )
        }
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "[redacted]")
    }
}

private extension Dictionary {
    func mapValuesWithKeys<T>(_ transform: (Key, Value) -> T) -> [Key: T] {
        Dictionary<Key, T>(uniqueKeysWithValues: map { key, value in
            (key, transform(key, value))
        })
    }
}
