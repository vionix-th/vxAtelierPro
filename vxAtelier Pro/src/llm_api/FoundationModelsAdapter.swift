import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Adapter for Apple Foundation Models / Apple Intelligence local generation.
@available(macOS 26.0, iOS 26.0, *)
struct FoundationModelsAdapter: LLMProviderAdapter {
    let profile: LLMProviderProfile
    private let backend: any LLMLocalModelBackend

    init(profile: LLMProviderProfile, backend: any LLMLocalModelBackend = FoundationModelsBackend()) {
        self.profile = profile
        self.backend = backend
    }

    func generateEvents(
        _ request: LLMGenerationRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMGenerationEvent, Error> {
        backend.generateEvents(
            request: request,
            configuration: configuration,
            toolExecutor: toolExecutor
        )
    }

    func fetchModelObservations(configuration: LLMProviderConfiguration) async throws -> [LLMProviderModelObservation] {
        backend.modelObservations(configuration: configuration)
    }
}

/// Foundation Models-backed local provider implementation.
@available(macOS 26.0, iOS 26.0, *)
struct FoundationModelsBackend: LLMLocalModelBackend {
    let profile: LLMProviderProfile = LLMProviderRegistry.shared.profile(for: .appleIntelligence)
    private let makeSession: FoundationModelsSessionFactory

    init(
        makeSession: @escaping FoundationModelsSessionFactory = { tools, transcript in
            FoundationModelsLiveSession(
                session: LanguageModelSession(model: .default, tools: tools, transcript: transcript)
            )
        }
    ) {
        self.makeSession = makeSession
    }

    func availability() -> LLMLocalModelAvailability {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("Apple Intelligence unavailable on this device.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence is not enabled.")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple Intelligence model not ready.")
        case .unavailable:
            return .unavailable("Apple Intelligence unavailable.")
        @unknown default:
            return .unavailable("Apple Intelligence unavailable.")
        }
        #else
        return .unavailable("Foundation Models framework unavailable in this build.")
        #endif
    }

    func modelObservations(configuration: LLMProviderConfiguration) -> [LLMProviderModelObservation] {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        let availability = availability()
        let contextSize = model.contextSize
        return [
            LLMProviderModelObservation(
                id: "apple-intelligence-default",
                displayName: "Apple Intelligence",
                providerID: .appleIntelligence,
                contextSize: contextSize,
                capabilityClaims: [.text, .tools, .streaming].map {
                    LLMCapabilityClaim(capability: $0, state: .supported)
                },
                rawMetadataJSON: Self.modelMetadataJSON(
                    availability: availability,
                    contextSize: contextSize
                )
            )
        ]
        #else
        return [
            LLMProviderModelObservation(
                id: "apple-intelligence-default",
                displayName: "Apple Intelligence",
                providerID: .appleIntelligence,
                contextSize: 4096,
                capabilityClaims: [.text, .tools, .streaming].map {
                    LLMCapabilityClaim(capability: $0, state: .supported)
                },
                rawMetadataJSON: Self.modelMetadataJSON(
                    availability: availability(),
                    contextSize: 4096
                )
            )
        ]
        #endif
    }

    func generateEvents(
        request: LLMGenerationRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMGenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(
                        request: request,
                        configuration: configuration,
                        toolExecutor: toolExecutor,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMProviderError.cancelled)
                } catch let error as LLMProviderError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: LLMProviderError.decoding(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func run(
        request: LLMGenerationRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?,
        continuation: AsyncThrowingStream<LLMGenerationEvent, Error>.Continuation
    ) async throws {
        let availability = availability()
        guard availability.isAvailable else {
            throw LLMProviderError.localModelUnavailable(availability.statusText)
        }

        continuation.yield(.generationStarted(requestID: nil))

        #if canImport(FoundationModels)
        let transcript = try buildTranscript(from: request)
        let transcriptEntryCount = transcript.count
        let promptText = currentPromptText(for: request)
        let options = generationOptions(from: request.options)
        let bridgedTools = try buildTools(
            from: request.tools,
            toolExecutor: toolExecutor
        )
        let session = makeSession(bridgedTools, transcript)
        if request.options.streamMode == .enabled {
            let stream = session.streamResponse(options: options, prompt: Prompt(promptText))

            var emittedText = ""
            for try await currentText in stream {
                let delta: String
                if currentText.hasPrefix(emittedText) {
                    delta = String(currentText.dropFirst(emittedText.count))
                } else {
                    delta = currentText
                }
                emittedText = currentText
                if !delta.isEmpty {
                    continuation.yield(.textDelta(delta))
                }
            }
        } else {
            let response = try await session.respond(options: options, prompt: Prompt(promptText))
            let finalText = response
            if !finalText.isEmpty {
                continuation.yield(.textDelta(finalText))
            }
        }

        for event in Self.nativeToolEvents(
            from: session.transcript.dropFirst(transcriptEntryCount)
        ) {
            continuation.yield(event)
        }

        continuation.yield(.generationCompleted(responseID: nil, modelID: request.modelID))
        #else
        throw LLMProviderError.localModelUnavailable("Foundation Models framework unavailable in this build.")
        #endif
    }

    #if canImport(FoundationModels)
    private func buildTranscript(from request: LLMGenerationRequest) throws -> Transcript {
        var entries: [Transcript.Entry] = []
        var toolNamesByID: [String: String] = [:]
        let toolDefinitions = try transcriptToolDefinitions(from: request.tools)

        let systemPrompt = request.options.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !systemPrompt.isEmpty || !toolDefinitions.isEmpty {
            entries.append(
                .instructions(
                    Transcript.Instructions(
                        id: "system",
                        segments: systemPrompt.isEmpty
                            ? []
                            : [.text(Transcript.TextSegment(content: request.options.systemPrompt))],
                        toolDefinitions: toolDefinitions
                    )
                )
            )
        }

        let history = request.messages
        guard !history.isEmpty else {
            return Transcript(entries: entries)
        }

        let replayMessages: ArraySlice<LLMMessage>
        if history.last?.role == "tool" {
            replayMessages = history[...]
        } else {
            replayMessages = history.dropLast()
        }

        for message in replayMessages {
            switch message.role {
            case "user":
                entries.append(
                    .prompt(
                        Transcript.Prompt(
                            segments: [
                                .text(Transcript.TextSegment(content: message.textContent))
                            ]
                        )
                    )
                )
            case "assistant":
                if !message.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    entries.append(
                        .response(
                            Transcript.Response(
                                assetIDs: [],
                                segments: [
                                    .text(Transcript.TextSegment(content: message.textContent))
                                ]
                            )
                        )
                    )
                }

                let calls = message.toolCalls.sorted { $0.index < $1.index }
                if !calls.isEmpty {
                    let transcriptCalls = try calls.map { call -> Transcript.ToolCall in
                        let callID = call.callID ?? call.id
                        toolNamesByID[callID] = call.name
                        return Transcript.ToolCall(
                            id: callID,
                            toolName: call.name,
                            arguments: try Self.generatedContent(from: call.argumentsJSON)
                        )
                    }
                    entries.append(.toolCalls(Transcript.ToolCalls(transcriptCalls)))
                }
            case "tool":
                guard let toolCallID = message.toolCallID else { continue }
                let toolName = toolNamesByID[toolCallID] ?? (message.textContent.isEmpty ? "tool" : message.textContent)
                entries.append(
                    .toolOutput(
                        Transcript.ToolOutput(
                            id: toolCallID,
                            toolName: toolName,
                            segments: [
                                .text(Transcript.TextSegment(content: message.textContent))
                            ]
                        )
                    )
                )
            default:
                break
            }
        }

        return Transcript(entries: entries)
    }

    private func transcriptToolDefinitions(from definitions: [LLMToolDefinition]) throws -> [Transcript.ToolDefinition] {
        try definitions.map { definition in
            Transcript.ToolDefinition(
                name: definition.name,
                description: definition.description,
                parameters: try Self.generationSchema(
                    from: definition.parameters,
                    name: definition.name,
                    description: definition.description
                )
            )
        }
    }

    private func buildTools(
        from definitions: [LLMToolDefinition],
        toolExecutor: LLMToolExecutionHandler?
    ) throws -> [any Tool] {
        guard !definitions.isEmpty else {
            return []
        }
        guard let toolExecutor else {
            throw LLMProviderError.toolExecution("Native tool execution requires a tool executor callback.")
        }
        return try definitions.map { definition in
            try FoundationModelsToolBridge(
                definition: definition,
                toolExecutor: toolExecutor
            )
        }
    }

    private func currentPromptText(for request: LLMGenerationRequest) -> String {
        guard let lastMessage = request.messages.last else {
            return "Continue."
        }
        switch lastMessage.role {
        case "tool":
            return "Continue using the tool outputs above."
        case "assistant":
            return lastMessage.textContent.isEmpty ? "Continue." : lastMessage.textContent
        default:
            return lastMessage.textContent.isEmpty ? "Continue." : lastMessage.textContent
        }
    }

    private func generationOptions(from options: LLMGenerationOptions) -> GenerationOptions {
        let temperature = options.temperature.map { min(max($0, 0), 1) }
        return GenerationOptions(
            sampling: nil,
            temperature: temperature,
            maximumResponseTokens: options.maxOutputTokens
        )
    }

    static func generatedContent(from jsonString: String) throws -> GeneratedContent {
        do {
            return try GeneratedContent(json: jsonString)
        } catch {
            throw LLMProviderError.invalidConversationState(
                "Invalid persisted tool-call arguments for Foundation Models: \(error.localizedDescription)"
            )
        }
    }

    private static func modelMetadataJSON(availability: LLMLocalModelAvailability, contextSize: Int) -> String? {
        let payload: [String: JSONValue] = [
            "availability": .string(availability.statusText),
            "context_size": .integer(contextSize)
        ]
        guard let data = try? JSONEncoder().encode(JSONValue.object(payload)),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private static func nativeToolEvents(from transcriptEntries: some Sequence<Transcript.Entry>) -> [LLMGenerationEvent] {
        var events: [LLMGenerationEvent] = []
        var nextIndex = 0
        var indexByCallID: [String: Int] = [:]

        for entry in transcriptEntries {
            switch entry {
            case .toolCalls(let calls):
                for call in calls {
                    let index = nextIndex
                    nextIndex += 1
                    indexByCallID[call.id] = index
                    events.append(
                        .toolCallCompleted(
                            LLMToolCall(
                                id: call.id,
                                callID: call.id,
                                index: index,
                                name: call.toolName,
                                argumentsJSON: call.arguments.jsonString
                            )
                        )
                    )
                }
            case .toolOutput(let output):
                let index = indexByCallID[output.id] ?? nextIndex
                events.append(
                    .toolOutputCompleted(
                        LLMToolOutput(
                            id: output.id,
                            callID: output.id,
                            index: index,
                            name: output.toolName,
                            output: Self.textContent(from: output.segments)
                        )
                    )
                )
            default:
                continue
            }
        }

        return events
    }

    private static func textContent(from segments: [Transcript.Segment]) -> String {
        segments
            .map { segment -> String in
                switch segment {
                case .text(let text):
                    return text.content
                case .structure(let structured):
                    return structured.content.jsonString
                @unknown default:
                    return ""
                }
            }
            .joined()
    }

    fileprivate static func generationSchema(
        from json: JSONValue,
        name: String,
        description: String
    ) throws -> GenerationSchema {
        try GenerationSchema(
            root: dynamicSchema(from: json, name: name, description: description),
            dependencies: []
        )
    }

    fileprivate static func dynamicSchema(
        from json: JSONValue,
        name: String? = nil,
        description: String? = nil
    ) throws -> DynamicGenerationSchema {
        if let object = json.objectValue {
            if let choices = object["enum"]?.arrayValue?.compactMap(\.stringValue), !choices.isEmpty {
                return DynamicGenerationSchema(
                    name: name ?? "value",
                    description: description,
                    anyOf: choices
                )
            }

            let type = object["type"]?.stringValue ?? "object"
            switch type {
            case "object":
                let required = Set(object["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
                let propertiesObject = object["properties"]?.objectValue ?? [:]
                let properties = try propertiesObject.map { propertyName, propertyValue -> DynamicGenerationSchema.Property in
                    let propertyDescription = propertyValue.objectValue?["description"]?.stringValue
                    return DynamicGenerationSchema.Property(
                        name: propertyName,
                        description: propertyDescription,
                        schema: try dynamicSchema(
                            from: propertyValue,
                            name: propertyName,
                            description: propertyDescription
                        ),
                        isOptional: !required.contains(propertyName)
                    )
                }
                return DynamicGenerationSchema(
                    name: name ?? "tool_input",
                    description: description,
                    properties: properties
                )
            case "array":
                let items = object["items"] ?? .object(["type": .string("string")])
                return DynamicGenerationSchema(
                    arrayOf: try dynamicSchema(from: items, name: name.map { "\($0)Item" }),
                    minimumElements: nil,
                    maximumElements: nil
                )
            case "integer":
                return DynamicGenerationSchema(type: Int.self)
            case "number":
                return DynamicGenerationSchema(type: Double.self)
            case "boolean":
                return DynamicGenerationSchema(type: Bool.self)
            case "string":
                return DynamicGenerationSchema(type: String.self)
            default:
                return DynamicGenerationSchema(type: String.self)
            }
        }

        if let array = json.arrayValue, !array.isEmpty {
            let choices = try array.map { try dynamicSchema(from: $0) }
            return DynamicGenerationSchema(name: name ?? "value", description: description, anyOf: choices)
        }

        if let string = json.stringValue {
            return DynamicGenerationSchema(name: name ?? "value", description: description, anyOf: [string])
        }

        return DynamicGenerationSchema(type: String.self)
    }
    #endif
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
private struct FoundationModelsToolBridge: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let includesSchemaInInstructions: Bool = false

    private let toolExecutor: LLMToolExecutionHandler

    init(
        definition: LLMToolDefinition,
        toolExecutor: @escaping LLMToolExecutionHandler
    ) throws {
        self.name = definition.name
        self.description = definition.description
        self.toolExecutor = toolExecutor
        self.parameters = try FoundationModelsBackend.generationSchema(
            from: definition.parameters,
            name: definition.name,
            description: definition.description
        )
    }

    func call(arguments: GeneratedContent) async throws -> String {
        let argumentsJSON = arguments.jsonString
        return try await toolExecutor(name, argumentsJSON)
    }
}

@available(macOS 26.0, iOS 26.0, *)
protocol FoundationModelsSessioning: Sendable {
    var transcript: Transcript { get }

    func respond(options: GenerationOptions, prompt: Prompt) async throws -> String
    func streamResponse(options: GenerationOptions, prompt: Prompt) -> AsyncThrowingStream<String, Error>
}

@available(macOS 26.0, iOS 26.0, *)
typealias FoundationModelsSessionFactory = @Sendable (_ tools: [any Tool], _ transcript: Transcript) -> any FoundationModelsSessioning

@available(macOS 26.0, iOS 26.0, *)
private struct FoundationModelsLiveSession: FoundationModelsSessioning {
    let session: LanguageModelSession

    var transcript: Transcript {
        session.transcript
    }

    func respond(options: GenerationOptions, prompt: Prompt) async throws -> String {
        try await session.respond(to: prompt, options: options).content
    }

    func streamResponse(options: GenerationOptions, prompt: Prompt) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = session.streamResponse(to: prompt, options: options)
                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

#endif
