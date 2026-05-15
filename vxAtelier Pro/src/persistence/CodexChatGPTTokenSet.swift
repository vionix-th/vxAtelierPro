import Foundation

/// Stored OAuth credential for the Codex ChatGPT subscription backend route.
struct CodexChatGPTTokenSet: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var expiresAt: Date
    var accountID: String?
    var email: String?
    var planType: String?
    var issuer: String
    var clientID: String
    var authMethod: LLMAuthKind

    var needsRefresh: Bool {
        expiresAt <= Date().addingTimeInterval(60)
    }

    static func decoded(from json: String) -> CodexChatGPTTokenSet? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CodexChatGPTTokenSet.self, from: data)
    }

    func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    func withClaimsFromTokens() -> CodexChatGPTTokenSet {
        let idClaims = Self.jwtClaims(from: idToken) ?? [:]
        let accessClaims = Self.jwtClaims(from: accessToken) ?? [:]
        var copy = self
        copy.email = email ?? idClaims.string("email") ?? idClaims.object("profile")?.string("email")
        copy.accountID = accountID
            ?? idClaims.string("chatgpt_account_id")
            ?? idClaims.object("https://api.openai.com/auth")?.string("chatgpt_account_id")
            ?? accessClaims.string("chatgpt_account_id")
            ?? accessClaims.object("https://api.openai.com/auth")?.string("chatgpt_account_id")
            ?? idClaims.array("organizations")?.first?.objectValue?.string("id")
        copy.planType = planType
            ?? idClaims.string("chatgpt_plan_type")
            ?? idClaims.object("https://api.openai.com/auth")?.string("chatgpt_plan_type")
            ?? accessClaims.string("chatgpt_plan_type")
            ?? accessClaims.object("https://api.openai.com/auth")?.string("chatgpt_plan_type")
        return copy
    }

    private static func jwtClaims(from token: String) -> [String: JSONValue]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return nil
        }
        return value.objectValue
    }
}
