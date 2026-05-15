import CryptoKit
import Foundation
import Network
import SwiftData

enum CodexChatGPTOAuthService {
    static let issuer = "https://auth.openai.com"
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let codexBackendBaseURL = "https://chatgpt.com/backend-api/codex"

    struct DeviceCodeChallenge: Equatable {
        var verificationURL: URL
        var userCode: String
        var deviceAuthID: String
        var pollingInterval: TimeInterval
    }

    enum OAuthError: LocalizedError {
        case missingToken
        case invalidResponse(String)
        case loginTimedOut
        case callbackFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingToken:
                return "Codex ChatGPT Subscription is not signed in."
            case .invalidResponse(let message):
                return message
            case .loginTimedOut:
                return "Codex ChatGPT login timed out."
            case .callbackFailed(let message):
                return "Codex ChatGPT OAuth callback failed: \(message)"
            }
        }
    }

    @MainActor
    static func resolvedProviderConfiguration(for configuration: APIConfigurationItem) async throws -> LLMProviderConfiguration {
        guard configuration.providerIDEnum == .openAICodexChatGPTSubscription else {
            return configuration.makeLLMProviderConfiguration()
        }
        var tokenSet = try await refreshedTokenIfNeeded(for: configuration)
        tokenSet = tokenSet.withClaimsFromTokens()
        configuration.codexChatGPTTokenSet = tokenSet
        return configuration.makeLLMProviderConfiguration()
    }

    @MainActor
    static func refreshedTokenIfNeeded(for configuration: APIConfigurationItem) async throws -> CodexChatGPTTokenSet {
        guard var tokenSet = configuration.codexChatGPTTokenSet else {
            throw LLMProviderError.authUnavailable(OAuthError.missingToken.localizedDescription)
        }
        guard tokenSet.needsRefresh else { return tokenSet }
        tokenSet = try await refresh(tokenSet)
        configuration.codexChatGPTTokenSet = tokenSet
        try configuration.modelContext?.save()
        return tokenSet
    }

    @MainActor
    static func save(_ tokenSet: CodexChatGPTTokenSet, to configuration: APIConfigurationItem) throws {
        configuration.providerIDEnum = .openAICodexChatGPTSubscription
        configuration.authKindEnum = tokenSet.authMethod
        configuration.baseURL = codexBackendBaseURL
        configuration.defaultAdapterIDEnum = .openAIResponses
        configuration.apiKey = ""
        configuration.codexChatGPTTokenSet = tokenSet
        try configuration.modelContext?.save()
    }

    static func signInWithBrowser(openURL: @MainActor (URL) -> Void) async throws -> CodexChatGPTTokenSet {
        let server = try await LocalOAuthCallbackServer.start(ports: [1455, 1457])
        defer { server.stop() }

        let pkce = PKCEPair()
        let state = randomBase64URL(byteCount: 32)
        let redirectURI = "http://localhost:\(server.port)/auth/callback"
        let authURL = try authorizeURL(redirectURI: redirectURI, pkce: pkce, state: state)

        await MainActor.run {
            openURL(authURL)
        }

        let callback = try await server.waitForCallback(timeout: 300)
        if let error = callback.queryItems?.first(where: { $0.name == "error" })?.value {
            let description = callback.queryItems?.first(where: { $0.name == "error_description" })?.value
            throw OAuthError.callbackFailed(description ?? error)
        }
        guard callback.queryItems?.first(where: { $0.name == "state" })?.value == state else {
            throw OAuthError.callbackFailed("Invalid state.")
        }
        guard let code = callback.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.callbackFailed("Missing authorization code.")
        }

        let response = try await exchangeAuthorizationCode(
            code: code,
            codeVerifier: pkce.verifier,
            redirectURI: redirectURI
        )
        return response.tokenSet(authMethod: .codexChatGPTOAuth)
    }

    static func startDeviceCodeLogin() async throws -> DeviceCodeChallenge {
        let request = DeviceCodeRequest(client_id: clientID)
        let response: DeviceCodeResponse = try await postJSON(
            url: URL(string: "\(issuer)/api/accounts/deviceauth/usercode")!,
            body: request
        )
        let userCode = response.user_code ?? response.usercode
        guard let userCode, !userCode.isEmpty else {
            throw OAuthError.invalidResponse("Device-code response did not include a user code.")
        }
        return DeviceCodeChallenge(
            verificationURL: URL(string: "\(issuer)/codex/device")!,
            userCode: userCode,
            deviceAuthID: response.device_auth_id,
            pollingInterval: response.intervalValue
        )
    }

    static func completeDeviceCodeLogin(_ challenge: DeviceCodeChallenge) async throws -> CodexChatGPTTokenSet {
        let started = Date()
        while Date().timeIntervalSince(started) < 15 * 60 {
            try await Task.sleep(nanoseconds: UInt64(max(challenge.pollingInterval, 1) * 1_000_000_000))

            var request = URLRequest(url: URL(string: "\(issuer)/api/accounts/deviceauth/token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(DeviceTokenRequest(
                device_auth_id: challenge.deviceAuthID,
                user_code: challenge.userCode
            ))

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OAuthError.invalidResponse("Device-code polling returned a non-HTTP response.")
            }
            if httpResponse.statusCode == 403 || httpResponse.statusCode == 404 {
                continue
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw OAuthError.invalidResponse(Self.errorMessage(data: data, statusCode: httpResponse.statusCode))
            }

            let deviceToken = try JSONDecoder().decode(DeviceTokenResponse.self, from: data)
            let tokenResponse = try await exchangeAuthorizationCode(
                code: deviceToken.authorization_code,
                codeVerifier: deviceToken.code_verifier,
                redirectURI: "\(issuer)/deviceauth/callback"
            )
            return tokenResponse.tokenSet(authMethod: .codexChatGPTDeviceCode)
        }
        throw OAuthError.loginTimedOut
    }

    static func refresh(_ tokenSet: CodexChatGPTTokenSet) async throws -> CodexChatGPTTokenSet {
        let response: TokenResponse = try await postForm(
            url: URL(string: "\(issuer)/oauth/token")!,
            body: [
                "grant_type": "refresh_token",
                "client_id": clientID,
                "refresh_token": tokenSet.refreshToken
            ]
        )
        return CodexChatGPTTokenSet(
            accessToken: response.access_token ?? tokenSet.accessToken,
            refreshToken: response.refresh_token ?? tokenSet.refreshToken,
            idToken: response.id_token ?? tokenSet.idToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in ?? 3600)),
            accountID: tokenSet.accountID,
            email: tokenSet.email,
            planType: tokenSet.planType,
            issuer: issuer,
            clientID: clientID,
            authMethod: tokenSet.authMethod
        ).withClaimsFromTokens()
    }

    private static func authorizeURL(redirectURI: String, pkce: PKCEPair, state: String) throws -> URL {
        var components = URLComponents(string: "\(issuer)/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access api.connectors.read api.connectors.invoke"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: "vxatelier_pro")
        ]
        guard let url = components?.url else {
            throw OAuthError.invalidResponse("Could not build Codex ChatGPT authorization URL.")
        }
        return url
    }

    private static func exchangeAuthorizationCode(
        code: String,
        codeVerifier: String,
        redirectURI: String
    ) async throws -> TokenResponse {
        try await postForm(
            url: URL(string: "\(issuer)/oauth/token")!,
            body: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectURI,
                "client_id": clientID,
                "code_verifier": codeVerifier
            ]
        )
    }

    private static func postJSON<RequestBody: Encodable, ResponseBody: Decodable>(
        url: URL,
        body: RequestBody
    ) async throws -> ResponseBody {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        return try await decodedResponse(for: request)
    }

    private static func postForm<ResponseBody: Decodable>(
        url: URL,
        body: [String: String]
    ) async throws -> ResponseBody {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.formURLEncoded().data(using: .utf8)
        return try await decodedResponse(for: request)
    }

    private static func decodedResponse<ResponseBody: Decodable>(for request: URLRequest) async throws -> ResponseBody {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse("Codex ChatGPT auth returned a non-HTTP response.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw OAuthError.invalidResponse(errorMessage(data: data, statusCode: httpResponse.statusCode))
        }
        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    private static func errorMessage(data: Data, statusCode: Int) -> String {
        let body = String(data: data, encoding: .utf8) ?? ""
        return body.isEmpty ? "Codex ChatGPT auth request failed with status \(statusCode)." : body
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        return Data(bytes).base64URLEncodedString()
    }
}

private struct PKCEPair {
    var verifier: String
    var challenge: String

    init() {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        verifier = String((0..<64).map { _ in characters.randomElement()! })
        let digest = SHA256.hash(data: Data(verifier.utf8))
        challenge = Data(digest).base64URLEncodedString()
    }
}

private struct DeviceCodeRequest: Encodable {
    var client_id: String
}

private struct DeviceCodeResponse: Decodable {
    var device_auth_id: String
    var user_code: String?
    var usercode: String?
    var interval: JSONValue?

    var intervalValue: TimeInterval {
        if let value = interval?.integerValue { return TimeInterval(value) }
        if let value = interval?.stringValue, let parsed = TimeInterval(value) { return parsed }
        return 5
    }
}

private struct DeviceTokenRequest: Encodable {
    var device_auth_id: String
    var user_code: String
}

private struct DeviceTokenResponse: Decodable {
    var authorization_code: String
    var code_verifier: String
}

private struct TokenResponse: Decodable {
    var access_token: String?
    var refresh_token: String?
    var id_token: String?
    var expires_in: Int?

    func tokenSet(authMethod: LLMAuthKind) -> CodexChatGPTTokenSet {
        CodexChatGPTTokenSet(
            accessToken: access_token ?? "",
            refreshToken: refresh_token ?? "",
            idToken: id_token ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(expires_in ?? 3600)),
            accountID: nil,
            email: nil,
            planType: nil,
            issuer: CodexChatGPTOAuthService.issuer,
            clientID: CodexChatGPTOAuthService.clientID,
            authMethod: authMethod
        ).withClaimsFromTokens()
    }
}

private final class LocalOAuthCallbackServer: @unchecked Sendable {
    let port: UInt16
    private let listener: NWListener
    private let queue = DispatchQueue(label: "vxatelier.codex-chatgpt-oauth")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URLComponents, Error>?

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    static func start(ports: [UInt16]) async throws -> LocalOAuthCallbackServer {
        var lastError: Error?
        for port in ports {
            do {
                return try await start(port: port)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CodexChatGPTOAuthService.OAuthError.invalidResponse("Could not start OAuth callback server.")
    }

    private static func start(port: UInt16) async throws -> LocalOAuthCallbackServer {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw CodexChatGPTOAuthService.OAuthError.invalidResponse("Invalid OAuth callback port \(port).")
        }
        let listener = try NWListener(using: .tcp, on: endpointPort)
        let server = LocalOAuthCallbackServer(listener: listener, port: port)
        listener.newConnectionHandler = { [weak server] connection in
            server?.handle(connection)
        }
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: server.queue)
        }
        return server
    }

    func waitForCallback(timeout: TimeInterval) async throws -> URLComponents {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.resume(with: .failure(CodexChatGPTOAuthService.OAuthError.loginTimedOut))
            }
        }
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let components = self.callbackComponents(from: request)
            if let components {
                self.resume(with: .success(components))
                self.respond(connection, status: "200 OK", html: Self.successHTML)
            } else {
                self.respond(connection, status: "400 Bad Request", html: Self.errorHTML)
            }
        }
    }

    private func callbackComponents(from request: String) -> URLComponents? {
        guard let requestLine = request.split(separator: "\r\n").first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let path = String(parts[1])
        guard path.hasPrefix("/auth/callback") else { return nil }
        return URLComponents(string: "http://localhost:\(port)\(path)")
    }

    private func resume(with result: Result<URLComponents, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        switch result {
        case .success(let components):
            continuation?.resume(returning: components)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private func respond(_ connection: NWConnection, status: String, html: String) {
        let body = Data(html.utf8)
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static let successHTML = """
    <!doctype html><html><head><title>Codex ChatGPT Login Complete</title></head><body><h1>Login complete</h1><p>You can close this window and return to vxAtelier Pro.</p></body></html>
    """

    private static let errorHTML = """
    <!doctype html><html><head><title>Codex ChatGPT Login Failed</title></head><body><h1>Login failed</h1><p>Return to vxAtelier Pro and try again.</p></body></html>
    """
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension Dictionary where Key == String, Value == String {
    func formURLEncoded() -> String {
        map { key, value in
            "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
        }
        .joined(separator: "&")
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}

private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return allowed
    }()
}
