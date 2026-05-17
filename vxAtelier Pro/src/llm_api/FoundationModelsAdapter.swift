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

    func stream(
        _ request: LLMRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        backend.stream(
            request: request,
            configuration: configuration,
            toolExecutor: toolExecutor
        )
    }

    func fetchModels(configuration: LLMProviderConfiguration) async throws -> [LLMModelDescriptor] {
        backend.modelCandidates(configuration: configuration)
    }
}

/// Foundation Models-backed local provider implementation.
@available(macOS 26.0, iOS 26.0, *)
struct FoundationModelsBackend: LLMLocalModelBackend {
    let profile: LLMProviderProfile = LLMProviderRegistry.shared.profile(for: .appleIntelligence)

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

    func modelCandidates(configuration: LLMProviderConfiguration) -> [LLMModelDescriptor] {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        let availability = availability()
        let contextSize = model.contextSize
        return [
            LLMModelDescriptor(
                id: "apple-intelligence-default",
                displayName: "Apple Intelligence",
                providerID: .appleIntelligence,
                contextSize: contextSize,
                capabilities: [.text, .tools, .streaming],
                rawMetadataJSON: Self.modelMetadataJSON(
                    availability: availability,
                    contextSize: contextSize
                )
            )
        ]
        #else
        return [
            LLMModelDescriptor(
                id: "apple-intelligence-default",
                displayName: "Apple Intelligence",
                providerID: .appleIntelligence,
                contextSize: 4096,
                capabilities: [.text, .tools, .streaming],
                rawMetadataJSON: Self.modelMetadataJSON(
                    availability: availability(),
                    contextSize: 4096
                )
            )
        ]
        #endif
    }

    func stream(
        request: LLMRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
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
        request: LLMRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        let availability = availability()
        guard availability.isAvailable else {
            throw LLMProviderError.authUnavailable(availability.statusText)
        }

        continuation.yield(.runStarted(requestID: nil))

        #if canImport(FoundationModels)
        let transcript = buildTranscript(from: request)
        let promptText = currentPromptText(for: request)
        let options = generationOptions(from: request.options)
        let toolRecorder = NativeToolExecutionRecorder()
        let bridgedTools = try buildTools(
            from: request.tools,
            toolExecutor: toolExecutor,
            recorder: toolRecorder
        )
        let session = LanguageModelSession(model: .default, tools: bridgedTools, transcript: transcript)
        let stream = session.streamResponse(options: options) {
            Prompt(promptText)
        }

        var emittedText = ""
        for try await snapshot in stream {
            let currentText = snapshot.content
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

        let records = await toolRecorder.snapshot()
        for record in records.sorted(by: { $0.index < $1.index }) {
            let call = LLMToolCall(
                id: record.id,
                callID: record.id,
                index: record.index,
                name: record.toolName,
                argumentsJSON: record.argumentsJSON
            )
            continuation.yield(.toolCallCompleted(call))
            continuation.yield(
                .toolOutputCompleted(
                    LLMToolOutput(
                        id: record.id,
                        callID: record.id,
                        index: record.index,
                        name: record.toolName,
                        output: record.output
                    )
                )
            )
        }

        continuation.yield(.runCompleted(responseID: nil, modelID: request.modelID))
        #else
        throw LLMProviderError.authUnavailable("Foundation Models framework unavailable in this build.")
        #endif
    }

    #if canImport(FoundationModels)
    private func buildTranscript(from request: LLMRequest) -> Transcript {
        var entries: [Transcript.Entry] = []
        var toolNamesByID: [String: String] = [:]

        if !request.options.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entries.append(
                .instructions(
                    Transcript.Instructions(
                        id: "system",
                        segments: [
                            .text(Transcript.TextSegment(content: request.options.systemPrompt))
                        ],
                        toolDefinitions: []
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
                                .text(Transcript.TextSegment(content: message.displayText))
                            ]
                        )
                    )
                )
            case "assistant":
                if !message.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    entries.append(
                        .response(
                            Transcript.Response(
                                assetIDs: [],
                                segments: [
                                    .text(Transcript.TextSegment(content: message.displayText))
                                ]
                            )
                        )
                    )
                }

                let calls = message.toolCalls.sorted { $0.index < $1.index }
                if !calls.isEmpty {
                    let transcriptCalls = calls.map { call -> Transcript.ToolCall in
                        let callID = call.callID ?? call.id
                        toolNamesByID[callID] = call.name
                        return Transcript.ToolCall(
                            id: callID,
                            toolName: call.name,
                            arguments: Self.generatedContent(from: call.argumentsJSON)
                        )
                    }
                    entries.append(.toolCalls(Transcript.ToolCalls(transcriptCalls)))
                }
            case "tool":
                guard let toolCallID = message.toolCallID else { continue }
                let toolName = toolNamesByID[toolCallID] ?? (message.displayText.isEmpty ? "tool" : message.displayText)
                entries.append(
                    .toolOutput(
                        Transcript.ToolOutput(
                            id: toolCallID,
                            toolName: toolName,
                            segments: [
                                .text(Transcript.TextSegment(content: message.displayText))
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

    private func buildTools(
        from definitions: [LLMToolDefinition],
        toolExecutor: LLMToolExecutionHandler?,
        recorder: NativeToolExecutionRecorder
    ) throws -> [any Tool] {
        guard !definitions.isEmpty else {
            return []
        }
        guard let toolExecutor else {
            throw LLMProviderError.invalidConfiguration("Native tool execution requires a tool executor callback.")
        }
        return try definitions.map { definition in
            try FoundationModelsToolBridge(
                definition: definition,
                toolExecutor: toolExecutor,
                recorder: recorder
            )
        }
    }

    private func currentPromptText(for request: LLMRequest) -> String {
        guard let lastMessage = request.messages.last else {
            return "Continue."
        }
        switch lastMessage.role {
        case "tool":
            return "Continue using the tool outputs above."
        case "assistant":
            return lastMessage.displayText.isEmpty ? "Continue." : lastMessage.displayText
        default:
            return lastMessage.displayText.isEmpty ? "Continue." : lastMessage.displayText
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

    private static func generatedContent(from jsonString: String) -> GeneratedContent {
        (try? GeneratedContent(json: jsonString)) ?? GeneratedContent(kind: .structure(properties: [:], orderedKeys: []))
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
    #endif
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
private actor NativeToolExecutionRecorder {
    struct Record: Sendable {
        var index: Int
        var id: String
        var toolName: String
        var argumentsJSON: String
        var output: String
    }

    private var records: [Record] = []

    func begin(toolName: String, argumentsJSON: String) -> Record {
        let record = Record(
            index: records.count,
            id: UUID().uuidString,
            toolName: toolName,
            argumentsJSON: argumentsJSON,
            output: ""
        )
        records.append(record)
        return record
    }

    func finish(id: String, output: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].output = output
    }

    func snapshot() -> [Record] {
        records
    }
}

@available(macOS 26.0, iOS 26.0, *)
private struct FoundationModelsToolBridge: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let includesSchemaInInstructions: Bool = true

    private let toolExecutor: LLMToolExecutionHandler
    private let recorder: NativeToolExecutionRecorder

    init(
        definition: LLMToolDefinition,
        toolExecutor: @escaping LLMToolExecutionHandler,
        recorder: NativeToolExecutionRecorder
    ) throws {
        self.name = definition.name
        self.description = definition.description
        self.toolExecutor = toolExecutor
        self.recorder = recorder
        self.parameters = try Self.generationSchema(from: definition.parameters, name: definition.name, description: definition.description)
    }

    func call(arguments: GeneratedContent) async throws -> String {
        let argumentsJSON = arguments.jsonString
        let record = await recorder.begin(toolName: name, argumentsJSON: argumentsJSON)
        do {
            let output = try await toolExecutor(name, argumentsJSON)
            await recorder.finish(id: record.id, output: output)
            return output
        } catch {
            throw error
        }
    }

    private static func generationSchema(
        from json: JSONValue,
        name: String,
        description: String
    ) throws -> GenerationSchema {
        try GenerationSchema(
            root: dynamicSchema(from: json, name: name, description: description),
            dependencies: []
        )
    }

    private static func dynamicSchema(
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
}
#endif
