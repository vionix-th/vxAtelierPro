import Foundation

struct AnthropicMessagesAdapter: LLMProviderAdapter {
    let profile: LLMProviderProfile
    private let httpClient = LLMHTTPClient()

    func stream(_ request: LLMRequest, configuration: APIConfigurationItem) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let endpoint = configuration.endpointPath(for: .anthropicMessages) ?? profile.endpointPaths[.anthropicMessages] ?? "/v1/messages"
        return LLMAdapterRunLoop.stream(
            request: request,
            configuration: configuration,
            profile: profile,
            httpClient: httpClient,
            endpoint: endpoint,
            completionPolicy: .requireExplicitEvent { event in
                event.string("type") == "message_stop"
            },
            makeBody: { stream in
                try makeBody(for: request, stream: stream)
            },
            emitNonStreaming: { response, continuation in
                emitResponse(response, continuation: continuation)
            },
            handleStreamingEvent: { event, assembler, continuation in
                handleStreamEvent(event, assembler: &assembler, continuation: continuation)
            }
        )
    }

    func fetchModels(configuration: APIConfigurationItem) async throws -> [LLMModelDescriptor] {
        let endpoint = configuration.endpointPath(for: .models) ?? profile.endpointPaths[.models] ?? "/v1/models"
        let response: JSONValue = try await httpClient.getJSON(
            path: endpoint,
            configuration: httpClient.makeConfiguration(for: configuration, profile: profile),
            responseType: JSONValue.self
        )
        guard let data = response.objectValue?.array("data") else { return [] }
        return LLMModelMetadataDecoder.anthropicDescriptors(from: data, profile: profile)
    }

    func makeBody(for request: LLMRequest, stream: Bool) throws -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "model": .string(request.modelID),
            "messages": .array(try anthropicMessages(from: request)),
            "stream": .boolean(stream)
        ]
        if !request.options.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["system"] = .string(request.options.systemPrompt)
        }
        let mappings = LLMParameterMappingResolver.resolve(
            providerID: request.providerID,
            endpointFamily: request.endpointFamily,
            modelID: request.modelID,
            modelDescriptor: request.modelDescriptor
        )
        try LLMParameterRequestEncoder.applyScalarOptions(request.options, to: &body, mappings: mappings)
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map { tool in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "input_schema": tool.parameters
                ])
            })
            body["tool_choice"] = .object(["type": .string("auto")])
        }
        return body
    }

    func anthropicMessages(from request: LLMRequest) throws -> [JSONValue] {
        var messages: [JSONValue] = []
        var index = request.messages.startIndex
        while index < request.messages.endIndex {
            let message = request.messages[index]
            if message.role == "system" {
                index = request.messages.index(after: index)
                continue
            }

            if message.role == "tool" {
                var content: [JSONValue] = []
                while index < request.messages.endIndex {
                    let toolMessage = request.messages[index]
                    guard toolMessage.role == "tool" else { break }
                    guard let toolCallID = toolMessage.toolCallID, !toolCallID.isEmpty else {
                        throw LLMProviderError.unsupportedParameter("Anthropic tool_result requires toolCallID.")
                    }
                    content.append(.object([
                        "type": .string("tool_result"),
                        "tool_use_id": .string(toolCallID),
                        "content": .string(toolMessage.displayText)
                    ]))
                    index = request.messages.index(after: index)
                }
                messages.append(.object([
                    "role": .string("user"),
                    "content": .array(content)
                ]))
                continue
            }

            var content = try anthropicContent(from: message)
            if !message.toolCalls.isEmpty {
                content.append(contentsOf: message.toolCalls.sorted { $0.index < $1.index }.map { call in
                    .object([
                        "type": .string("tool_use"),
                        "id": .string(call.callID ?? call.id),
                        "name": .string(call.name),
                        "input": jsonFromString(call.argumentsJSON)
                    ])
                })
            }
            if !content.isEmpty {
                messages.append(.object([
                    "role": .string(message.role == "assistant" ? "assistant" : "user"),
                    "content": .array(content)
                ]))
            }
            index = request.messages.index(after: index)
        }
        return messages
    }

    private func anthropicContent(from message: LLMMessage) throws -> [JSONValue] {
        try message.content.compactMap { part in
            switch part.kind {
            case .text, .reasoning, .toolResult:
                guard let text = part.text, !text.isEmpty else { return nil }
                return .object(["type": .string("text"), "text": .string(text)])
            case .image:
                if let sourceURL = part.sourceURL, !sourceURL.isEmpty {
                    return .object([
                        "type": .string("image"),
                        "source": .object([
                            "type": .string("url"),
                            "url": .string(sourceURL)
                        ])
                    ])
                }
                guard let data = part.dataBase64, !data.isEmpty else {
                    throw LLMProviderError.unsupportedParameter("Anthropic image content requires sourceURL or dataBase64.")
                }
                let mediaType = try anthropicImageMediaType(part.mimeType)
                return .object([
                    "type": .string("image"),
                    "source": .object([
                        "type": .string("base64"),
                        "media_type": .string(mediaType),
                        "data": .string(data)
                    ])
                ])
            case .audio:
                throw LLMProviderError.unsupportedParameter("Anthropic audio content is not supported by this adapter.")
            case .file:
                throw LLMProviderError.unsupportedParameter("Anthropic file content is not supported by this adapter.")
            }
        }
    }

    private func anthropicImageMediaType(_ mimeType: String?) throws -> String {
        let mediaType = mimeType ?? "image/png"
        let supported = ["image/jpeg", "image/png", "image/gif", "image/webp"]
        guard supported.contains(mediaType) else {
            throw LLMProviderError.unsupportedParameter("Anthropic image content does not support \(mediaType).")
        }
        return mediaType
    }

    private func handleStreamEvent(
        _ event: [String: JSONValue],
        assembler: inout LLMToolCallAssembler,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) {
        switch event.string("type") {
        case "message_start":
            continuation.yield(.runStarted(requestID: event.object("message")?.string("id")))
        case "content_block_delta":
            guard let delta = event.object("delta") else { return }
            if let text = delta.string("text") {
                continuation.yield(.textDelta(text))
            } else if let partial = delta.string("partial_json") {
                let index = event.int("index") ?? 0
                let call = LLMToolCall(id: "tool-\(index)", index: index, name: "", argumentsJSON: partial)
                continuation.yield(.toolCallDelta(assembler.merge(call)))
            } else if let thinking = delta.string("thinking") {
                continuation.yield(.reasoningDelta(thinking))
            }
        case "content_block_start":
            guard let block = event.object("content_block"),
                  block.string("type") == "tool_use" else { return }
            let index = event.int("index") ?? 0
            let call = LLMToolCall(
                id: block.string("id") ?? "tool-\(index)",
                callID: block.string("id"),
                index: index,
                name: block.string("name") ?? "",
                argumentsJSON: ""
            )
            continuation.yield(.toolCallDelta(assembler.merge(call)))
        case "message_delta":
            if let usage = event.object("usage") {
                continuation.yield(.usage(LLMUsage(inputTokens: usage.int("input_tokens"), outputTokens: usage.int("output_tokens"), totalTokens: nil)))
            }
        case "message_stop":
            continuation.yield(.runCompleted(responseID: nil, modelID: nil))
        default:
            break
        }
    }

    private func emitResponse(
        _ response: JSONValue,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) {
        guard let object = response.objectValue else { return }
        if let content = object.array("content") {
            for (index, part) in content.enumerated() {
                guard let item = part.objectValue else { continue }
                if item.string("type") == "text", let text = item.string("text") {
                    continuation.yield(.textDelta(text))
                } else if item.string("type") == "tool_use" {
                    continuation.yield(.toolCallCompleted(LLMToolCall(
                        id: item.string("id") ?? "tool-\(index)",
                        callID: item.string("id"),
                        index: index,
                        name: item.string("name") ?? "",
                    argumentsJSON: LLMModelMetadataDecoder.rawJSONString(from: item.object("input").map { .object($0) } ?? .object([:])) ?? "{}"
                )))
            }
        }
        }
        if let usage = object.object("usage") {
            continuation.yield(.usage(LLMUsage(inputTokens: usage.int("input_tokens"), outputTokens: usage.int("output_tokens"))))
        }
        continuation.yield(.runCompleted(responseID: object.string("id"), modelID: object.string("model")))
    }

    private func jsonFromString(_ string: String) -> JSONValue {
        guard let data = string.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .object([:])
        }
        return value
    }

}
