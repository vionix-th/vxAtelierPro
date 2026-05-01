import Foundation

struct NetworkRequestOptions {
    var requestTimeout: TimeInterval
    var streamIdleTimeout: TimeInterval
    var maxResponseBodyBytes: Int
    var maxSSEEventBytes: Int

    init(
        requestTimeout: TimeInterval = 60,
        streamIdleTimeout: TimeInterval = 120,
        maxResponseBodyBytes: Int = 10 * 1024 * 1024,
        maxSSEEventBytes: Int = 1024 * 1024
    ) {
        self.requestTimeout = requestTimeout
        self.streamIdleTimeout = streamIdleTimeout
        self.maxResponseBodyBytes = maxResponseBodyBytes
        self.maxSSEEventBytes = maxSSEEventBytes
    }
}

struct NetworkResponseMetadata: Equatable {
    var statusCode: Int?
    var headers: [String: String]
}

enum NetworkError: LocalizedError {
    case invalidURL(String)
    case networkFailure(URLError)
    case invalidResponse
    case serverError(statusCode: Int, message: String, metadata: NetworkResponseMetadata)
    case decodingError(DecodingError)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .networkFailure(let error):
            return error.localizedDescription
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let statusCode, let message, _):
            return "Server error (\(statusCode)): \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

private final class NetworkCertificateDelegate: NSObject, URLSessionDelegate {
    weak var client: NetworkClient?

    init(client: NetworkClient) {
        self.client = client
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let client,
              client.allowSelfSignedCertificates,
              client.isHostAllowedByWhitelist(host: challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

final class NetworkClient {
    static let shared = NetworkClient()

    struct Result<T> {
        var value: T
        var metadata: NetworkResponseMetadata
    }

    enum StreamEvent {
        case metadata(NetworkResponseMetadata)
        case event(String)
    }

    var allowSelfSignedCertificates: Bool {
        UserDefaults.standard.bool(forKey: AppSettings.Keys.allowSelfSignedCertificates)
    }

    private var session: URLSession

    private init() {
        session = URLSession.shared
        configureSession()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    func getRequest<T: Decodable>(
        url: String,
        headers: [String: String],
        responseType: T.Type
    ) async throws -> T {
        try await getJSONWithMetadata(
            url: url,
            headers: headers,
            responseType: responseType
        ).value
    }

    func getJSONWithMetadata<T: Decodable>(
        url: String,
        headers: [String: String],
        options: NetworkRequestOptions = NetworkRequestOptions(),
        responseType: T.Type
    ) async throws -> Result<T> {
        guard let url = URL(string: url) else {
            await vxAtelierPro.log.error("Invalid URL for GET request: \(url)")
            throw NetworkError.invalidURL(url)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await executeJSON(request, options: options, responseType: responseType)
    }

    func postJSONWithMetadata<T: Decodable, Body: Encodable>(
        url: String,
        headers: [String: String],
        body: Body,
        options: NetworkRequestOptions = NetworkRequestOptions(),
        responseType: T.Type
    ) async throws -> Result<T> {
        guard let url = URL(string: url) else {
            await vxAtelierPro.log.error("Invalid URL for POST request: \(url)")
            throw NetworkError.invalidURL(url)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await executeJSON(request, options: options, responseType: responseType)
    }

    func executeJSON<T: Decodable>(
        _ request: URLRequest,
        options: NetworkRequestOptions = NetworkRequestOptions(),
        responseType: T.Type
    ) async throws -> Result<T> {
        var request = request
        request.timeoutInterval = options.requestTimeout
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw NetworkError.networkFailure(error)
        } catch {
            throw error
        }
        try validate(response: response, data: data, options: options)
        do {
            return Result(
                value: try JSONDecoder().decode(responseType, from: data),
                metadata: metadata(from: response)
            )
        } catch let error as DecodingError {
            throw NetworkError.decodingError(error)
        }
    }

    func streamSSE(
        _ request: URLRequest,
        options: NetworkRequestOptions = NetworkRequestOptions()
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = request
                    request.timeoutInterval = options.streamIdleTimeout
                    let (bytes, response) = try await session.bytes(for: request)
                    let responseMetadata = metadata(from: response)
                    continuation.yield(.metadata(responseMetadata))
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw NetworkError.serverError(
                            statusCode: http.statusCode,
                            message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                            metadata: responseMetadata
                        )
                    }

                    var eventData = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            throw URLError(.cancelled)
                        }
                        if line.isEmpty {
                            if !eventData.isEmpty {
                                continuation.yield(.event(eventData))
                                eventData.removeAll(keepingCapacity: true)
                            }
                            continue
                        }
                        if line.hasPrefix("data:") {
                            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            if !eventData.isEmpty && (payload.hasPrefix("{") || payload == "[DONE]") {
                                continuation.yield(.event(eventData))
                                eventData.removeAll(keepingCapacity: true)
                            }
                            eventData += payload
                            if eventData.utf8.count > options.maxSSEEventBytes {
                                throw NetworkError.serverError(
                                    statusCode: responseMetadata.statusCode ?? 0,
                                    message: "SSE event exceeded configured size limit.",
                                    metadata: responseMetadata
                                )
                            }
                        }
                    }

                    if !eventData.isEmpty {
                        continuation.yield(.event(eventData))
                    }
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: NetworkError.networkFailure(error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func isHostAllowedByWhitelist(host: String) -> Bool {
        guard let json = UserDefaults.standard.string(forKey: AppSettings.Keys.selfSignedCertWhitelist),
              let data = json.data(using: .utf8),
              let patterns = try? JSONDecoder().decode([String].self, from: data) else {
            return false
        }
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return false
            }
            let range = NSRange(location: 0, length: host.utf16.count)
            return regex.firstMatch(in: host, options: [], range: range) != nil
        }
    }

    private func configureSession() {
        guard allowSelfSignedCertificates else {
            session = .shared
            return
        }
        session = URLSession(
            configuration: .default,
            delegate: NetworkCertificateDelegate(client: self),
            delegateQueue: nil
        )
    }

    private func validate(response: URLResponse, data: Data, options: NetworkRequestOptions) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            var message = "HTTP Error"
            if let text = String(data: data.prefix(options.maxResponseBodyBytes), encoding: .utf8), !text.isEmpty {
                message += ": \(text.prefix(4_000))"
            }
            throw NetworkError.serverError(
                statusCode: httpResponse.statusCode,
                message: message,
                metadata: metadata(from: response)
            )
        }
        guard data.count <= options.maxResponseBodyBytes else {
            throw NetworkError.serverError(
                statusCode: httpResponse.statusCode,
                message: "Response exceeded configured size limit.",
                metadata: metadata(from: response)
            )
        }
    }

    func metadata(from response: URLResponse) -> NetworkResponseMetadata {
        guard let http = response as? HTTPURLResponse else {
            return NetworkResponseMetadata(statusCode: nil, headers: [:])
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }
        return NetworkResponseMetadata(statusCode: http.statusCode, headers: headers)
    }

    @objc private func userDefaultsDidChange(_ notification: Notification) {
        configureSession()
    }
}
