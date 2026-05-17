import Foundation

/// Adapter for OpenAI Platform Chat Completions requests and events.
struct OpenAIChatCompletionsAdapter: LLMProviderAdapter {
    private static let generationPath = "/chat/completions"
    private static let modelsPath = "/models"

    let profile: LLMProviderProfile
    private let adapterID: LLMAdapterID
    private let httpClient = LLMHTTPClient()

    /// Creates a Chat Completions adapter for a concrete adapter identity.
    init(profile: LLMProviderProfile, adapterID: LLMAdapterID = .openAIChatCompletions) {
        self.profile = profile
        self.adapterID = adapterID
    }

    /// Executes a Chat Completions request through the shared adapter run loop.
    func stream(
        _ request: LLMRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        do {
            try validateAdapterID(request.adapterID)
            return LLMAdapterRunLoop.stream(
                request: request,
                configuration: configuration,
                profile: profile,
                httpClient: httpClient,
                endpoint: Self.generationPath,
                completionPolicy: .synthesizeOnStreamEnd,
                makeBody: { stream in
                    try makeBody(for: request, stream: stream)
                },
                emitNonStreaming: { response, continuation in
                    emitNonStreamingResponse(response, continuation: continuation)
                },
                handleStreamingEvent: { event, assembler, continuation in
                    for emitted in handleStreamEvent(event, assembler: &assembler) {
                        continuation.yield(emitted)
                    }
                }
            )
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    /// Fetches OpenAI-compatible model metadata and maps it into candidates.
    func fetchModels(configuration: LLMProviderConfiguration) async throws -> [LLMModelDescriptor] {
        let httpConfig = httpClient.makeConfiguration(for: configuration)
        let response: JSONValue = try await httpClient.getJSON(path: Self.modelsPath, configuration: httpConfig, responseType: JSONValue.self)
        guard let data = response.objectValue?.array("data") else { return [] }
        return LLMModelMetadataDecoder.openAICompatibleCandidates(
            from: data,
            profile: profile
        )
    }

    /// Confirms the runtime request is routed through the expected chat adapter.
    private func validateAdapterID(_ requestedAdapterID: LLMAdapterID) throws {
        guard requestedAdapterID == adapterID else {
            throw LLMProviderError.unsupportedCapability("\(profile.name) does not support \(adapterID.rawValue).")
        }
    }

    /// Encodes a provider-neutral request into a Chat Completions JSON body.
    func makeBody(for request: LLMRequest, stream: Bool) throws -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "model": .string(request.modelID),
            "messages": .array(try openAIMessages(from: request)),
            "stream": .boolean(stream)
        ]
        let mappings = LLMParameterMappingResolver.resolve(
            adapterID: request.adapterID,
            mappings: request.parameterMappings
        )
        try OpenAICompatibleEncoding.applyMappedOptions(
            request.options,
            to: &body,
            mappings: mappings,
            reservedProviderExtraKeys: OpenAICompatibleEncoding.chatReservedProviderExtraKeys
        )
        if !request.tools.isEmpty {
            body["tools"] = .array(OpenAICompatibleEncoding.chatTools(from: request.tools))
            body["tool_choice"] = .string("auto")
        }
        return body
    }

    /// Converts provider-neutral messages into Chat Completions message objects.
    private func openAIMessages(from request: LLMRequest) throws -> [JSONValue] {
        var messages: [JSONValue] = []
        if !request.options.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(.object(["role": .string("system"), "content": .string(request.options.systemPrompt)]))
        }
        messages.append(contentsOf: try request.messages.map { message in
            var body: [String: JSONValue] = [
                "role": .string(message.role),
                "content": try OpenAICompatibleEncoding.chatContent(from: message)
            ]
            if let toolCallID = message.toolCallID {
                body["tool_call_id"] = .string(toolCallID)
            }
            if !message.toolCalls.isEmpty {
                body["tool_calls"] = .array(message.toolCalls.map { call in
                    .object([
                        "id": .string(call.callID ?? call.id),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string(call.name),
                            "arguments": .string(call.argumentsJSON)
                        ])
                    ])
                })
            }
            return .object(body)
        })
        return messages
    }

    /// Converts one Chat Completions SSE payload into normalized stream events.
    private func handleStreamEvent(_ event: [String: JSONValue], assembler: inout LLMToolCallAssembler) -> [LLMStreamEvent] {
        guard let choices = event.array("choices"),
              let choice = choices.first?.objectValue,
              let delta = choice.object("delta") else {
            if let usage = event.object("usage") {
                return [.usage(OpenAICompatibleEncoding.usage(from: usage, inputKey: "prompt_tokens", outputKey: "completion_tokens"))]
            }
            return []
        }
        var events: [LLMStreamEvent] = []
        if let content = delta.string("content"), !content.isEmpty {
            events.append(.textDelta(content))
        }
        if let toolCalls = delta.array("tool_calls") {
            for value in toolCalls {
                guard let item = value.objectValue else { continue }
                let index = item.int("index") ?? 0
                let function = item.object("function") ?? [:]
                let deltaCall = LLMToolCall(
                    id: item.string("id") ?? "tool-\(index)",
                    callID: item.string("id"),
                    index: index,
                    name: function.string("name") ?? "",
                    argumentsJSON: function.string("arguments") ?? ""
                )
                events.append(.toolCallDelta(assembler.merge(deltaCall)))
            }
        }
        if let usage = event.object("usage") {
            events.append(.usage(OpenAICompatibleEncoding.usage(from: usage, inputKey: "prompt_tokens", outputKey: "completion_tokens")))
        }
        return events
    }

    /// Emits normalized events from a complete Chat Completions JSON response.
    private func emitNonStreamingResponse(
        _ response: JSONValue,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) {
        guard let object = response.objectValue else {
            continuation.yield(.runCompleted(responseID: nil, modelID: nil))
            return
        }
        if let choices = object.array("choices"),
           let message = choices.first?.objectValue?.object("message") {
            if let content = message.string("content"), !content.isEmpty {
                continuation.yield(.textDelta(content))
            }
            if let toolCalls = message.array("tool_calls") {
                for (offset, value) in toolCalls.enumerated() {
                    guard let item = value.objectValue else { continue }
                    let function = item.object("function") ?? [:]
                    let call = LLMToolCall(
                        id: item.string("id") ?? "tool-\(offset)",
                        callID: item.string("id"),
                        index: offset,
                        name: function.string("name") ?? "",
                        argumentsJSON: function.string("arguments") ?? ""
                    )
                    continuation.yield(.toolCallCompleted(call))
                }
            }
        }
        if let usage = object.object("usage") {
            continuation.yield(.usage(OpenAICompatibleEncoding.usage(from: usage, inputKey: "prompt_tokens", outputKey: "completion_tokens")))
        }
        continuation.yield(.runCompleted(responseID: object.string("id"), modelID: object.string("model")))
    }
}

/// Adapter for providers that implement the OpenAI-compatible Chat Completions shape.
struct OpenAICompatibleChatCompletionsAdapter: LLMProviderAdapter {
    let profile: LLMProviderProfile
    private let chatAdapter: OpenAIChatCompletionsAdapter

    /// Creates an OpenAI-compatible Chat Completions adapter for a provider profile.
    init(profile: LLMProviderProfile) {
        self.profile = profile
        self.chatAdapter = OpenAIChatCompletionsAdapter(
            profile: profile,
            adapterID: .openAICompatibleChatCompletions
        )
    }

    /// Executes a compatible Chat Completions request through the shared chat implementation.
    func stream(
        _ request: LLMRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        chatAdapter.stream(request, configuration: configuration, toolExecutor: toolExecutor)
    }

    /// Fetches OpenAI-compatible model metadata and maps it into candidates.
    func fetchModels(configuration: LLMProviderConfiguration) async throws -> [LLMModelDescriptor] {
        try await chatAdapter.fetchModels(configuration: configuration)
    }
}
