import Foundation

/// Shared Chat Completions request and event codec.
struct OpenAIChatCompletionsCodec {
    private static let generationPath = "/chat/completions"

    private let httpClient = LLMHTTPClient()
    private let openRouterEncoding: OpenRouterChatCompletionsEncoding?

    init(openRouterEncoding: OpenRouterChatCompletionsEncoding? = nil) {
        self.openRouterEncoding = openRouterEncoding
    }

    func generateEvents(
        _ request: LLMGenerationRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMGenerationEvent, Error> {
        LLMHTTPGenerationPipeline.generateEvents(
            request: request,
            configuration: configuration,
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
    }

    /// Encodes a provider-neutral request into a Chat Completions JSON body.
    func makeBody(for request: LLMGenerationRequest, stream: Bool) throws -> [String: JSONValue] {
        try request.validateActiveParameterMappings()
        var body: [String: JSONValue] = [
            "messages": .array(try openAIMessages(from: request))
        ]
        if request.usesAdapterEncoding(.model) {
            body["model"] = .string(request.modelID)
        }
        if request.usesAdapterEncoding(.stream) {
            body["stream"] = .boolean(stream)
        }
        try OpenAIEncoding.applyMappedOptions(
            request.options,
            to: &body,
            parameters: request.activeParameters,
            reservedProviderExtraKeys: OpenAIEncoding.chatReservedProviderExtraKeys,
            excludedStructuredPresets: openRouterEncoding == nil ? [] : [.openRouterReasoning]
        )
        try openRouterEncoding?.apply(request: request, to: &body)
        if !request.tools.isEmpty {
            body["tools"] = .array(OpenAIEncoding.chatTools(from: request.tools))
            body["tool_choice"] = .string("auto")
        }
        return body
    }

    /// Converts provider-neutral messages into Chat Completions message objects.
    private func openAIMessages(from request: LLMGenerationRequest) throws -> [JSONValue] {
        var messages: [JSONValue] = []
        if request.usesAdapterEncoding(.systemPrompt),
           !request.options.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(.object(["role": .string("system"), "content": .string(request.options.systemPrompt)]))
        }
        messages.append(contentsOf: try request.messages.map { message in
            var body: [String: JSONValue] = [
                "role": .string(message.role),
                "content": try OpenAIEncoding.chatContent(from: message)
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
    private func handleStreamEvent(_ event: [String: JSONValue], assembler: inout LLMToolCallAssembler) -> [LLMGenerationEvent] {
        guard let choices = event.array("choices"),
              let choice = choices.first?.objectValue,
              let delta = choice.object("delta") else {
            if let usage = event.object("usage") {
                return [.usage(OpenAIEncoding.usage(from: usage, inputKey: "prompt_tokens", outputKey: "completion_tokens"))]
            }
            return []
        }
        var events: [LLMGenerationEvent] = []
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
            events.append(.usage(OpenAIEncoding.usage(from: usage, inputKey: "prompt_tokens", outputKey: "completion_tokens")))
        }
        return events
    }

    /// Emits normalized events from a complete Chat Completions JSON response.
    private func emitNonStreamingResponse(
        _ response: JSONValue,
        continuation: AsyncThrowingStream<LLMGenerationEvent, Error>.Continuation
    ) {
        guard let object = response.objectValue else {
            continuation.yield(.generationCompleted(responseID: nil, modelID: nil))
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
            continuation.yield(.usage(OpenAIEncoding.usage(from: usage, inputKey: "prompt_tokens", outputKey: "completion_tokens")))
        }
        continuation.yield(.generationCompleted(responseID: object.string("id"), modelID: object.string("model")))
    }
}

struct OpenRouterChatCompletionsEncoding {
    func apply(
        request: LLMGenerationRequest,
        to body: inout [String: JSONValue]
    ) throws {
        guard request.activeParameters.contains(where: {
            $0.mapping.structuredPreset == .openRouterReasoning
        }), let effort = request.options.reasoning, !effort.isEmpty else {
            return
        }

        var reasoning = body["reasoning"]?.objectValue ?? [:]
        guard reasoning["effort"] == nil else {
            throw LLMProviderError.requestEncoding(
                "OpenRouter reasoning collides with request field reasoning.effort."
            )
        }
        reasoning["effort"] = .string(effort)
        body["reasoning"] = .object(reasoning)
    }
}

struct OpenAIChatCompletionsAdapter: LLMGenerationAdapter {
    let id: LLMAdapterID = .openAIChatCompletions
    private let codec = OpenAIChatCompletionsCodec()

    func generateEvents(
        _ request: LLMGenerationRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMGenerationEvent, Error> {
        codec.generateEvents(
            request,
            configuration: configuration,
            toolExecutor: toolExecutor
        )
    }

    func makeBody(
        for request: LLMGenerationRequest,
        stream: Bool
    ) throws -> [String: JSONValue] {
        try codec.makeBody(for: request, stream: stream)
    }
}

struct OpenAIChatCompletionsLegacyAdapter: LLMGenerationAdapter {
    let id: LLMAdapterID = .openAIChatCompletionsLegacy
    private let codec = OpenAIChatCompletionsCodec()

    func generateEvents(
        _ request: LLMGenerationRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMGenerationEvent, Error> {
        codec.generateEvents(
            request,
            configuration: configuration,
            toolExecutor: toolExecutor
        )
    }

    func makeBody(
        for request: LLMGenerationRequest,
        stream: Bool
    ) throws -> [String: JSONValue] {
        try codec.makeBody(for: request, stream: stream)
    }
}

struct OpenRouterChatCompletionsAdapter: LLMGenerationAdapter {
    let id: LLMAdapterID = .openRouterChatCompletions
    private let codec = OpenAIChatCompletionsCodec(
        openRouterEncoding: OpenRouterChatCompletionsEncoding()
    )

    func generateEvents(
        _ request: LLMGenerationRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMGenerationEvent, Error> {
        codec.generateEvents(
            request,
            configuration: configuration,
            toolExecutor: toolExecutor
        )
    }

    func makeBody(
        for request: LLMGenerationRequest,
        stream: Bool
    ) throws -> [String: JSONValue] {
        try codec.makeBody(for: request, stream: stream)
    }
}
