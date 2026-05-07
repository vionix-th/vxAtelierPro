import Foundation

struct OpenAIChatAdapter: LLMProviderAdapter {
    let profile: LLMProviderProfile
    private let httpClient = LLMHTTPClient()

    func stream(_ request: LLMRequest, configuration: LLMProviderConfiguration) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        do {
            let endpoint = try endpointPath(for: request.endpointFamily, configuration: configuration)
            return LLMAdapterRunLoop.stream(
                request: request,
                configuration: configuration,
                profile: profile,
                httpClient: httpClient,
                endpoint: endpoint,
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

    func fetchModels(configuration: LLMProviderConfiguration) async throws -> [LLMModelDescriptor] {
        let endpoint = configuration.endpointPath(for: .models) ?? profile.endpointPaths[.models] ?? "/v1/models"
        let httpConfig = httpClient.makeConfiguration(for: configuration)
        let response: JSONValue = try await httpClient.getJSON(path: endpoint, configuration: httpConfig, responseType: JSONValue.self)
        guard let data = response.objectValue?.array("data") else { return [] }
        return LLMModelMetadataDecoder.openAICompatibleDescriptors(
            from: data,
            profile: profile,
            endpointFamilies: [.chatCompletions]
        )
    }

    private func endpointPath(for endpointFamily: LLMEndpointFamily, configuration: LLMProviderConfiguration) throws -> String {
        guard let endpoint = configuration.endpointPath(for: endpointFamily) ?? profile.endpointPaths[endpointFamily] else {
            throw LLMProviderError.unsupportedCapability("\(profile.name) does not support \(endpointFamily.rawValue).")
        }
        return endpoint
    }

    func makeBody(for request: LLMRequest, stream: Bool) throws -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "model": .string(request.modelID),
            "messages": .array(try openAIMessages(from: request)),
            "stream": .boolean(stream)
        ]
        let mappings = LLMParameterMappingResolver.resolve(
            providerID: request.providerID,
            endpointFamily: request.endpointFamily,
            modelID: request.modelID,
            modelDescriptor: request.modelDescriptor
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
