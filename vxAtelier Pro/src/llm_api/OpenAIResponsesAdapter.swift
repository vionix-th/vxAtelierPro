import Foundation

/// Adapter for OpenAI Responses requests and events.
struct OpenAIResponsesAdapter: LLMProviderAdapter {
    private static let generationPath = "/responses"

    let profile: LLMProviderProfile
    private let httpClient = LLMHTTPClient()

    /// Creates an adapter for a provider profile that supports Responses.
    init(profile: LLMProviderProfile) {
        self.profile = profile
    }

    /// Executes a Responses request through the shared adapter run loop.
    func stream(_ request: LLMRequest, configuration: LLMProviderConfiguration) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        return LLMAdapterRunLoop.stream(
            request: request,
            configuration: configuration,
            profile: profile,
            httpClient: httpClient,
            endpoint: Self.generationPath,
            completionPolicy: .requireExplicitEvent { event in
                event.string("type") == "response.completed"
            },
            makeBody: { stream in
                try makeBody(for: request, stream: stream)
            },
            emitNonStreaming: { response, continuation in
                emitNonStreamingResponse(response, continuation: continuation)
            },
            handleStreamingEvent: { event, assembler, continuation in
                handleResponsesStreamEvent(event, assembler: &assembler, continuation: continuation)
            }
        )
    }

    /// Reuses Chat Completions model listing for Responses-capable configurations.
    func fetchModels(configuration: LLMProviderConfiguration) async throws -> [LLMModelDescriptor] {
        let chatFallback = OpenAIChatCompletionsAdapter(profile: profile)
        return try await chatFallback.fetchModels(configuration: configuration)
    }

    /// Encodes a provider-neutral request into a Responses JSON body.
    func makeBody(for request: LLMRequest, stream: Bool) throws -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "model": .string(request.modelID),
            "input": .array(try responsesInput(from: request)),
            "stream": .boolean(stream)
        ]
        if !request.options.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["instructions"] = .string(request.options.systemPrompt)
        }
        let mappings = LLMParameterMappingResolver.resolve(
            adapterID: request.adapterID,
            mappings: request.parameterMappings
        )
        try OpenAICompatibleEncoding.applyMappedOptions(
            request.options,
            to: &body,
            mappings: mappings,
            reservedProviderExtraKeys: OpenAICompatibleEncoding.responsesReservedProviderExtraKeys
        )
        if !request.tools.isEmpty {
            body["tools"] = .array(OpenAICompatibleEncoding.responsesTools(from: request.tools))
        }
        return body
    }

    /// Converts conversation messages into Responses input items, including tool replay.
    func responsesInput(from request: LLMRequest) throws -> [JSONValue] {
        try request.messages.flatMap { message -> [JSONValue] in
            if message.role == "tool", let toolCallID = message.toolCallID {
                return [.object([
                    "type": .string("function_call_output"),
                    "call_id": .string(toolCallID),
                    "output": .string(message.displayText)
                ])]
            }

            var items: [JSONValue] = []
            if hasProviderContent(message) {
                items.append(.object([
                    "role": .string(message.role),
                    "content": try OpenAICompatibleEncoding.responsesContent(from: message)
                ]))
            }
            if message.role == "assistant" {
                items.append(contentsOf: message.toolCalls.sorted { $0.index < $1.index }.map { call in
                    .object([
                        "type": .string("function_call"),
                        "id": .string(call.id),
                        "call_id": .string(call.callID ?? call.id),
                        "name": .string(call.name),
                        "arguments": .string(call.argumentsJSON)
                    ])
                })
            }
            return items
        }
    }

    /// Returns whether a message has content that should become a Responses input message.
    private func hasProviderContent(_ message: LLMMessage) -> Bool {
        if !message.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return message.content.contains { part in
            switch part.kind {
            case .image, .audio, .file:
                return true
            case .text, .reasoning, .toolResult:
                return false
            }
        }
    }

    /// Converts one Responses SSE payload into normalized stream events.
    private func handleResponsesStreamEvent(
        _ event: [String: JSONValue],
        assembler: inout LLMToolCallAssembler,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) {
        switch event.string("type") {
        case "response.created", "response.in_progress":
            continuation.yield(.runStarted(requestID: event.object("response")?.string("id")))
        case "response.output_text.delta":
            if let delta = event.string("delta") { continuation.yield(.textDelta(delta)) }
        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
            if let delta = event.string("delta") { continuation.yield(.reasoningDelta(delta)) }
        case "response.function_call_arguments.delta":
            let index = event.int("output_index") ?? event.int("item_index") ?? 0
            let delta = LLMToolCall(
                id: event.string("item_id") ?? "tool-\(index)",
                callID: event.string("call_id"),
                index: index,
                name: event.string("name") ?? "",
                argumentsJSON: event.string("delta") ?? ""
            )
            continuation.yield(.toolCallDelta(assembler.merge(delta)))
        case "response.output_item.done":
            if let item = event.object("item"),
               item.string("type") == "function_call" {
                let index = event.int("output_index") ?? 0
                let call = LLMToolCall(
                    id: item.string("id") ?? item.string("call_id") ?? "tool-\(index)",
                    callID: item.string("call_id"),
                    index: index,
                    name: item.string("name") ?? "",
                    argumentsJSON: item.string("arguments") ?? ""
                )
                _ = assembler.replace(with: call)
            }
        case "response.completed":
            let response = event.object("response")
            if let usage = response?.object("usage") {
                continuation.yield(.usage(OpenAICompatibleEncoding.usage(from: usage, inputKey: "input_tokens", outputKey: "output_tokens")))
            }
            continuation.yield(.runCompleted(responseID: response?.string("id"), modelID: response?.string("model")))
        default:
            break
        }
    }

    /// Emits normalized events from a complete Responses JSON response.
    private func emitNonStreamingResponse(
        _ response: JSONValue,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) {
        guard let object = response.objectValue else {
            continuation.yield(.runCompleted(responseID: nil, modelID: nil))
            return
        }
        if let outputText = object.string("output_text"), !outputText.isEmpty {
            continuation.yield(.textDelta(outputText))
        }
        if let output = object.array("output") {
            for (index, value) in output.enumerated() {
                guard let item = value.objectValue else { continue }
                if item.string("type") == "message",
                   let content = item.array("content") {
                    for part in content {
                        if let text = part.objectValue?.string("text"), !text.isEmpty {
                            continuation.yield(.textDelta(text))
                        }
                    }
                } else if item.string("type") == "function_call" {
                    continuation.yield(.toolCallCompleted(LLMToolCall(
                        id: item.string("id") ?? item.string("call_id") ?? "tool-\(index)",
                        callID: item.string("call_id"),
                        index: index,
                        name: item.string("name") ?? "",
                        argumentsJSON: item.string("arguments") ?? ""
                    )))
                }
            }
        }
        if let usage = object.object("usage") {
            continuation.yield(.usage(OpenAICompatibleEncoding.usage(from: usage, inputKey: "input_tokens", outputKey: "output_tokens")))
        }
        continuation.yield(.runCompleted(responseID: object.string("id"), modelID: object.string("model")))
    }
}
