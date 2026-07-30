import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class LLMLocalProviderTests: XCTestCase {
    func testFoundationModelsAdapterDelegatesLocalBackend() async throws {
        let candidate = LLMProviderModelMetadata(
            id: "apple-intelligence-default",
            displayName: "Apple Intelligence",
            providerID: .appleIntelligence,
            contextSize: 4096,
            capabilityClaims: [.text, .tools, .streaming].map {
                LLMCapabilityClaim(capability: $0, state: .supported)
            }
        )
        let backend = MockLocalModelBackend(
            availabilityResult: .available,
            statusTextResult: "On-device model available",
            candidatesResult: [candidate],
            streamFactory: { continuation in
                continuation.yield(.generationStarted(requestID: "apple-request"))
                continuation.yield(.textDelta("Hello"))
                continuation.yield(.toolCallCompleted(LLMToolCall(
                    id: "tool-1",
                    callID: "tool-1",
                    index: 0,
                    name: "lookup",
                    argumentsJSON: "{\"q\":\"test\"}"
                )))
                continuation.yield(.generationCompleted(responseID: "apple-response", modelID: "apple-intelligence-default"))
                continuation.finish()
            }
        )
        let adapter = FoundationModelsAdapter(backend: backend)
        let configuration = LLMProviderConfiguration(providerID: .appleIntelligence, baseURL: "", credential: .none)

        let fetchedModels = backend.modelMetadata(configuration: configuration)
        XCTAssertEqual(fetchedModels, [candidate])

        let request = LLMGenerationRequest(
            providerID: .appleIntelligence,
            adapterID: .foundationModels,
            modelID: candidate.id,
            messages: [
                LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])
            ],
            tools: [
                LLMToolDefinition(
                    name: "lookup",
                    description: "Lookup tool",
                    parameters: .object([:])
                )
            ],
            options: LLMGenerationOptions(streamMode: .enabled)
        )

        let events = try await collectEvents(adapter.generateEvents(
            request,
            configuration: configuration,
            toolExecutor: nil
        ))
        XCTAssertEqual(events, [
            .generationStarted(requestID: "apple-request"),
            .textDelta("Hello"),
            .toolCallCompleted(LLMToolCall(
                id: "tool-1",
                callID: "tool-1",
                index: 0,
                name: "lookup",
                argumentsJSON: "{\"q\":\"test\"}"
            )),
            .generationCompleted(responseID: "apple-response", modelID: "apple-intelligence-default")
        ])
    }

    func testFoundationModelsAdapterSurfacesLocalBackendAvailabilityFailure() async throws {
        let backend = MockLocalModelBackend(
            availabilityResult: .unavailable("Apple Intelligence unavailable."),
            statusTextResult: "Apple Intelligence unavailable.",
            candidatesResult: []
        )
        let adapter = FoundationModelsAdapter(backend: backend)
        let configuration = LLMProviderConfiguration(providerID: .appleIntelligence, baseURL: "", credential: .none)

        let request = LLMGenerationRequest(
            providerID: .appleIntelligence,
            adapterID: .foundationModels,
            modelID: "apple-intelligence-default",
            messages: [
                LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])
            ]
        )

        do {
            _ = try await collectEvents(adapter.generateEvents(
                request,
                configuration: configuration,
                toolExecutor: nil
            ))
            XCTFail("Expected adapter to fail when backend is unavailable.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .localModelUnavailable("Apple Intelligence unavailable."))
        }
    }

    private func collectEvents(_ stream: AsyncThrowingStream<LLMGenerationEvent, Error>) async throws -> [LLMGenerationEvent] {
        var events: [LLMGenerationEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

private final class MockLocalModelBackend: LLMLocalModelBackend {
    let profile = LLMProviderRegistry.shared.profile(for: .appleIntelligence)
    let availabilityResult: LLMLocalModelAvailability
    let statusTextResult: String
    let candidatesResult: [LLMProviderModelMetadata]
    let streamFactory: (AsyncThrowingStream<LLMGenerationEvent, Error>.Continuation) -> Void

    init(
        availabilityResult: LLMLocalModelAvailability,
        statusTextResult: String,
        candidatesResult: [LLMProviderModelMetadata],
        streamFactory: @escaping (AsyncThrowingStream<LLMGenerationEvent, Error>.Continuation) -> Void = { $0.finish() }
    ) {
        self.availabilityResult = availabilityResult
        self.statusTextResult = statusTextResult
        self.candidatesResult = candidatesResult
        self.streamFactory = streamFactory
    }

    func availability() -> LLMLocalModelAvailability {
        availabilityResult
    }

    func statusText() -> String {
        statusTextResult
    }

    func modelMetadata(configuration: LLMProviderConfiguration) -> [LLMProviderModelMetadata] {
        candidatesResult
    }

    func generateEvents(
        request: LLMGenerationRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMGenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            streamFactory(continuation)
        }
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
@MainActor
final class FoundationModelsBackendTests: XCTestCase {
    func testGeneratedContentThrowsOnInvalidJSON() {
        XCTAssertThrowsError(try FoundationModelsBackend.generatedContent(from: "{invalid")) { error in
            guard case .invalidConversationState(let message) = error as? LLMProviderError else {
                return XCTFail("Expected invalid conversation state, got \(error)")
            }
            XCTAssertTrue(message.contains("Invalid persisted tool-call arguments for Foundation Models"))
        }
    }

    func testFoundationModelsBackendUsesRespondForNonStreamingRuns() async throws {
        let session = MockFoundationModelsSession(
            responseText: "Final answer",
            streamText: ["Final answer"],
            generatedEntries: [
                .toolCalls(
                    Transcript.ToolCalls([
                        Transcript.ToolCall(
                            id: "call-1",
                            toolName: "lookup",
                            arguments: try FoundationModelsBackend.generatedContent(from: "{\"q\":\"test\"}")
                        )
                    ])
                ),
                .toolOutput(
                    Transcript.ToolOutput(
                        id: "call-1",
                        toolName: "lookup",
                        segments: [
                            .text(Transcript.TextSegment(content: "result"))
                        ]
                    )
                )
            ]
        )
        let backend = FoundationModelsBackend { _, transcript in
            session.transcript = transcript
            return session
        }
        let request = makeAppleRequest(streamMode: .disabled)

        let events = try await collectEvents(backend.generateEvents(
            request: request,
            configuration: .init(providerID: .appleIntelligence, baseURL: "", credential: .none),
            toolExecutor: { _, _ in "result" }
        ))

        XCTAssertTrue(session.respondCalled)
        XCTAssertFalse(session.streamCalled)
        XCTAssertEqual(events, [
            .generationStarted(requestID: nil),
            .textDelta("Final answer"),
            .toolCallCompleted(LLMToolCall(
                id: "call-1",
                callID: "call-1",
                index: 0,
                name: "lookup",
                argumentsJSON: "{\"q\":\"test\"}"
            )),
            .toolOutputCompleted(LLMToolOutput(
                id: "call-1",
                callID: "call-1",
                index: 0,
                name: "lookup",
                output: "result"
            )),
            .generationCompleted(responseID: nil, modelID: "apple-intelligence-default")
        ])
    }

    func testFoundationModelsBackendUsesStreamForStreamingRuns() async throws {
        let session = MockFoundationModelsSession(
            responseText: "Final answer",
            streamText: ["Fin", "Final answer"],
            generatedEntries: [
                .toolCalls(
                    Transcript.ToolCalls([
                        Transcript.ToolCall(
                            id: "call-1",
                            toolName: "lookup",
                            arguments: try FoundationModelsBackend.generatedContent(from: "{\"q\":\"test\"}")
                        )
                    ])
                ),
                .toolOutput(
                    Transcript.ToolOutput(
                        id: "call-1",
                        toolName: "lookup",
                        segments: [
                            .text(Transcript.TextSegment(content: "result"))
                        ]
                    )
                )
            ]
        )
        let backend = FoundationModelsBackend { _, transcript in
            session.transcript = transcript
            return session
        }
        let request = makeAppleRequest(streamMode: .enabled)

        let events = try await collectEvents(backend.generateEvents(
            request: request,
            configuration: .init(providerID: .appleIntelligence, baseURL: "", credential: .none),
            toolExecutor: { _, _ in "result" }
        ))

        XCTAssertTrue(session.streamCalled)
        XCTAssertFalse(session.respondCalled)
        XCTAssertEqual(events, [
            .generationStarted(requestID: nil),
            .textDelta("Fin"),
            .textDelta("al answer"),
            .toolCallCompleted(LLMToolCall(
                id: "call-1",
                callID: "call-1",
                index: 0,
                name: "lookup",
                argumentsJSON: "{\"q\":\"test\"}"
            )),
            .toolOutputCompleted(LLMToolOutput(
                id: "call-1",
                callID: "call-1",
                index: 0,
                name: "lookup",
                output: "result"
            )),
            .generationCompleted(responseID: nil, modelID: "apple-intelligence-default")
        ])
    }

    private func makeAppleRequest(streamMode: LLMGenerationOptions.StreamMode) -> LLMGenerationRequest {
        let candidate = LLMProviderModelMetadata(
            id: "apple-intelligence-default",
            displayName: "Apple Intelligence",
            providerID: .appleIntelligence,
            contextSize: 4096,
            capabilityClaims: [.text, .tools, .streaming].map {
                LLMCapabilityClaim(capability: $0, state: .supported)
            }
        )

        return LLMGenerationRequest(
            providerID: .appleIntelligence,
            adapterID: .foundationModels,
            modelID: candidate.id,
            messages: [
                LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])
            ],
            tools: [
                LLMToolDefinition(
                    name: "lookup",
                    description: "Lookup tool",
                    parameters: .object([:])
                )
            ],
            options: LLMGenerationOptions(streamMode: streamMode)
        )
    }

    private func collectEvents(_ stream: AsyncThrowingStream<LLMGenerationEvent, Error>) async throws -> [LLMGenerationEvent] {
        var events: [LLMGenerationEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

private final class MockFoundationModelsSession: @unchecked Sendable, FoundationModelsSessioning {
    var transcript: Transcript
    let responseText: String
    let streamText: [String]
    let generatedEntries: [Transcript.Entry]
    private(set) var respondCalled = false
    private(set) var streamCalled = false

    init(
        transcript: Transcript = Transcript(entries: [
            .prompt(
                Transcript.Prompt(
                    segments: [
                        .text(Transcript.TextSegment(content: "Hello"))
                    ]
                )
            )
        ]),
        responseText: String,
        streamText: [String],
        generatedEntries: [Transcript.Entry]
    ) {
        self.transcript = transcript
        self.responseText = responseText
        self.streamText = streamText
        self.generatedEntries = generatedEntries
    }

    func respond(options: GenerationOptions, prompt: Prompt) async throws -> String {
        respondCalled = true
        transcript = Transcript(entries: Array(transcript) + generatedEntries + [
            .response(
                Transcript.Response(
                    assetIDs: [],
                    segments: [
                        .text(Transcript.TextSegment(content: responseText))
                    ]
                )
            )
        ])
        return responseText
    }

    func streamResponse(options: GenerationOptions, prompt: Prompt) -> AsyncThrowingStream<String, Error> {
        streamCalled = true
        return AsyncThrowingStream { continuation in
            let task = Task {
                for text in streamText {
                    continuation.yield(text)
                }
                transcript = Transcript(entries: Array(transcript) + generatedEntries + [
                    .response(
                        Transcript.Response(
                            assetIDs: [],
                            segments: [
                                .text(Transcript.TextSegment(content: responseText))
                            ]
                        )
                    )
                ])
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
#endif
