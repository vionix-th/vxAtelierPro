import Foundation

/// Shared adapter loop that validates requests and normalizes streaming/non-streaming HTTP execution.
enum LLMAdapterRunLoop {
    typealias Continuation = AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    typealias BodyBuilder = (Bool) throws -> [String: JSONValue]
    typealias NonStreamingEmitter = (JSONValue, Continuation) -> Void
    typealias StreamingEventHandler = ([String: JSONValue], inout LLMToolCallAssembler, Continuation) -> Void

    /// Executes one provider request and delegates provider-specific encoding and event interpretation to closures.
    static func stream(
        request: LLMRequest,
        configuration: LLMProviderConfiguration,
        profile: LLMProviderProfile,
        httpClient: LLMHTTPClient,
        endpoint: String,
        completionPolicy: LLMStreamCompletionPolicy,
        makeBody: @escaping BodyBuilder,
        emitNonStreaming: @escaping NonStreamingEmitter,
        handleStreamingEvent: @escaping StreamingEventHandler
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try LLMCapabilityValidator.validate(request, profile: profile)
                    let streamEnabled = LLMCapabilityValidator.streamEnabled(for: request)
                    let body = try makeBody(streamEnabled)
                    let httpConfig = httpClient.makeConfiguration(for: configuration)
                    continuation.yield(.runStarted(requestID: nil))

                    if streamEnabled {
                        try await collectStream(
                            endpoint: endpoint,
                            httpConfig: httpConfig,
                            body: body,
                            httpClient: httpClient,
                            completionPolicy: completionPolicy,
                            continuation: continuation,
                            handleStreamingEvent: handleStreamingEvent
                        )
                    } else {
                        let result: LLMHTTPClient.Result<JSONValue> = try await httpClient.jsonRequestWithMetadata(
                            path: endpoint,
                            configuration: httpConfig,
                            body: body,
                            responseType: JSONValue.self
                        )
                        continuation.yield(.responseMetadata(result.metadata))
                        emitNonStreaming(result.value, continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Collects SSE events, emits completed tool calls, and enforces provider completion semantics.
    private static func collectStream(
        endpoint: String,
        httpConfig: LLMHTTPClient.Configuration,
        body: [String: JSONValue],
        httpClient: LLMHTTPClient,
        completionPolicy: LLMStreamCompletionPolicy,
        continuation: Continuation,
        handleStreamingEvent: StreamingEventHandler
    ) async throws {
        var assembler = LLMToolCallAssembler()
        var sawRunCompleted = false
        for try await streamEvent in httpClient.streamSSEWithMetadata(
            path: endpoint,
            configuration: httpConfig,
            body: body
        ) {
            switch streamEvent {
            case .metadata(let metadata):
                continuation.yield(.responseMetadata(metadata))
            case .event(let event):
                handleStreamingEvent(event, &assembler, continuation)
                if completionPolicy.didComplete(event) {
                    sawRunCompleted = true
                }
            }
        }
        for call in assembler.assembled {
            continuation.yield(.toolCallCompleted(call))
        }
        if !completionPolicy.requiresExplicitCompletionEvent {
            continuation.yield(.runCompleted(responseID: nil, modelID: nil))
        } else if !sawRunCompleted {
            throw LLMProviderError.decoding("Provider stream ended before completion event.")
        }
    }
}
