import Foundation

/// HTTP and SSE transport wrapper for provider adapters.
struct LLMHTTPClient {
    /// Resolved HTTP settings for one provider request.
    struct Configuration {
        var baseURL: String
        var headers: [String: String]
        var requestTimeout: TimeInterval = 60
        var streamIdleTimeout: TimeInterval = 120
        var maxResponseBodyBytes: Int = 10 * 1024 * 1024
        var maxSSEEventBytes: Int = 1024 * 1024
    }

    /// Decoded response value paired with redacted provider metadata.
    struct Result<T> {
        var value: T
        var metadata: LLMResponseMetadata
    }

    /// Event stream item carrying either response metadata or one decoded SSE payload.
    enum StreamEvent {
        case metadata(LLMResponseMetadata)
        case event([String: JSONValue])
    }

    let networkClient: NetworkClient

    /// Creates a transport wrapper around the shared network client by default.
    init(networkClient: NetworkClient = .shared) {
        self.networkClient = networkClient
    }

    /// Sends a JSON POST and returns only the decoded body.
    func jsonRequest<T: Decodable, Body: Encodable>(
        path: String,
        configuration: Configuration,
        body: Body,
        responseType: T.Type
    ) async throws -> T {
        try await jsonRequestWithMetadata(
            path: path,
            configuration: configuration,
            body: body,
            responseType: responseType
        ).value
    }

    /// Sends a JSON POST and returns the decoded body plus redacted response metadata.
    func jsonRequestWithMetadata<T: Decodable, Body: Encodable>(
        path: String,
        configuration: Configuration,
        body: Body,
        responseType: T.Type
    ) async throws -> Result<T> {
        var request = try makeRequest(
            path: path,
            configuration: configuration,
            timeout: configuration.requestTimeout
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let result: NetworkClient.Result<T> = try await networkClient.executeJSON(
                request,
                options: networkOptions(from: configuration),
                responseType: responseType
            )
            return Result(value: result.value, metadata: metadata(from: result.metadata))
        } catch {
            throw normalize(error)
        }
    }

    /// Sends a JSON GET and returns only the decoded body.
    func getJSON<T: Decodable>(
        path: String,
        configuration: Configuration,
        responseType: T.Type
    ) async throws -> T {
        try await getJSONWithMetadata(path: path, configuration: configuration, responseType: responseType).value
    }

    /// Sends a JSON GET and returns the decoded body plus redacted response metadata.
    func getJSONWithMetadata<T: Decodable>(
        path: String,
        configuration: Configuration,
        responseType: T.Type
    ) async throws -> Result<T> {
        var request = try makeRequest(
            path: path,
            configuration: configuration,
            timeout: configuration.requestTimeout
        )
        request.httpMethod = "GET"
        do {
            let result: NetworkClient.Result<T> = try await networkClient.executeJSON(
                request,
                options: networkOptions(from: configuration),
                responseType: responseType
            )
            return Result(value: result.value, metadata: metadata(from: result.metadata))
        } catch {
            throw normalize(error)
        }
    }

    /// Streams decoded SSE JSON objects while dropping response metadata events.
    func streamSSE<Body: Encodable>(
        path: String,
        configuration: Configuration,
        body: Body
    ) -> AsyncThrowingStream<[String: JSONValue], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in streamSSEWithMetadata(path: path, configuration: configuration, body: body) {
                        if case .event(let payload) = event {
                            continuation.yield(payload)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streams SSE metadata and decoded JSON objects from a provider POST request.
    func streamSSEWithMetadata<Body: Encodable>(
        path: String,
        configuration: Configuration,
        body: Body
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest(
                        path: path,
                        configuration: configuration,
                        timeout: configuration.streamIdleTimeout
                    )
                    request.httpMethod = "POST"
                    request.httpBody = try JSONEncoder().encode(body)
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    for try await event in networkClient.streamSSE(
                        request,
                        options: networkOptions(from: configuration)
                    ) {
                        switch event {
                        case .metadata(let metadata):
                            continuation.yield(.metadata(self.metadata(from: metadata)))
                        case .event(let payload):
                            if payload == "[DONE]" { continue }
                            try emitSSEPayload(payload, continuation: continuation)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMProviderError.cancelled)
                } catch {
                    continuation.finish(throwing: normalize(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Adapts provider runtime configuration into concrete transport settings and headers.
    func makeConfiguration(for configuration: LLMProviderConfiguration) -> Configuration {
        return Configuration(
            baseURL: configuration.baseURL,
            headers: LLMProviderHeaderResolver.headers(for: configuration),
            requestTimeout: configuration.requestTimeout,
            streamIdleTimeout: configuration.streamIdleTimeout,
            maxResponseBodyBytes: configuration.maxResponseBodyBytes,
            maxSSEEventBytes: configuration.maxSSEEventBytes
        )
    }

    /// Builds an absolute URL request from a provider base URL and endpoint path.
    private func makeRequest(
        path: String,
        configuration: Configuration,
        timeout: TimeInterval
    ) throws -> URLRequest {
        guard let base = URL(string: configuration.baseURL) else {
            throw LLMProviderError.invalidURL("Invalid base URL: \(configuration.baseURL)")
        }
        let url: URL?
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            url = URL(string: path)
        } else {
            url = URLComponents(url: base, resolvingAgainstBaseURL: true)?.appendingPath(path).url
        }
        guard let url else {
            throw LLMProviderError.invalidURL("Invalid endpoint: \(path)")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        for (name, value) in configuration.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    /// Decodes an SSE payload into a provider JSON object for legacy callers.
    private func emitSSEPayload(_ payload: String, continuation: AsyncThrowingStream<[String: JSONValue], Error>.Continuation) throws {
        if payload == "[DONE]" { return }
        guard let data = payload.data(using: .utf8) else { return }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        if let object = value.objectValue {
            continuation.yield(object)
        }
    }

    /// Decodes an SSE payload into a stream event while preserving metadata support.
    private func emitSSEPayload(_ payload: String, continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) throws {
        if payload == "[DONE]" { return }
        guard let data = payload.data(using: .utf8) else { return }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        if let object = value.objectValue {
            continuation.yield(.event(object))
        }
    }

    /// Converts URL response metadata into the provider-neutral redacted shape.
    func metadata(from response: URLResponse) -> LLMResponseMetadata {
        metadata(from: networkClient.metadata(from: response))
    }

    /// Converts network metadata into the provider-neutral redacted shape.
    func metadata(from networkMetadata: NetworkResponseMetadata) -> LLMResponseMetadata {
        let headers = networkMetadata.headers
        let redactedHeaders = LLMSecretRedactor.redactedHeaders(headers)
        let requestID = redactedHeaders["x-request-id"]
            ?? redactedHeaders["x-openai-request-id"]
            ?? redactedHeaders["request-id"]
            ?? redactedHeaders["anthropic-request-id"]
        let rateLimitHeaders = redactedHeaders.filter { key, _ in key.contains("ratelimit") }
        return LLMResponseMetadata(
            statusCode: networkMetadata.statusCode,
            requestID: requestID,
            retryAfter: redactedHeaders["retry-after"],
            rateLimitHeaders: rateLimitHeaders,
            headers: redactedHeaders
        )
    }

    /// Maps lower-level transport failures onto provider-domain errors.
    private func normalize(_ error: Error) -> Error {
        if let providerError = error as? LLMProviderError { return providerError }
        if let networkError = error as? NetworkError {
            switch networkError {
            case .invalidURL(let url):
                return LLMProviderError.invalidURL(url)
            case .networkFailure(let urlError):
                if urlError.code == .cancelled { return LLMProviderError.cancelled }
                return LLMProviderError.network(urlError.localizedDescription)
            case .invalidResponse:
                return LLMProviderError.network(networkError.localizedDescription)
            case .serverError(let statusCode, let message, let metadata):
                let providerMessage: String
                switch message {
                case "Response exceeded configured size limit.":
                    providerMessage = "Provider response exceeded configured size limit."
                case "SSE event exceeded configured size limit.":
                    providerMessage = "Provider stream event exceeded configured size limit."
                default:
                    providerMessage = message
                }
                return LLMProviderError.provider(
                    statusCode: statusCode,
                    message: LLMSecretRedactor.redactAndLimit(providerMessage, maxCharacters: 4_000),
                    metadata: self.metadata(from: metadata)
                )
            case .decodingError(let decodingError):
                return LLMProviderError.decoding(decodingError.localizedDescription)
            }
        }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return LLMProviderError.cancelled }
            return LLMProviderError.network(urlError.localizedDescription)
        }
        return error
    }

    /// Applies provider-specific body and SSE size limits to the shared network client.
    private func networkOptions(from configuration: Configuration) -> NetworkRequestOptions {
        NetworkRequestOptions(
            requestTimeout: configuration.requestTimeout,
            streamIdleTimeout: configuration.streamIdleTimeout,
            maxResponseBodyBytes: configuration.maxResponseBodyBytes,
            maxSSEEventBytes: configuration.maxSSEEventBytes
        )
    }

}
