import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMLocalProviderTests: XCTestCase {
    func testFoundationModelsAdapterDelegatesLocalBackend() async throws {
        let candidate = LLMModelDescriptor(
            id: "apple-intelligence-default",
            displayName: "Apple Intelligence",
            providerID: .appleIntelligence,
            contextSize: 4096,
            capabilities: [.text, .tools, .streaming]
        )
        let backend = MockLocalModelBackend(
            availabilityResult: .available,
            statusTextResult: "On-device model available",
            candidatesResult: [candidate],
            streamFactory: { continuation in
                continuation.yield(.runStarted(requestID: "apple-request"))
                continuation.yield(.textDelta("Hello"))
                continuation.yield(.toolCallCompleted(LLMToolCall(
                    id: "tool-1",
                    callID: "tool-1",
                    index: 0,
                    name: "lookup",
                    argumentsJSON: "{\"q\":\"test\"}"
                )))
                continuation.yield(.runCompleted(responseID: "apple-response", modelID: "apple-intelligence-default"))
                continuation.finish()
            }
        )
        let adapter = FoundationModelsAdapter(profile: LLMProviderRegistry.shared.profile(for: .appleIntelligence), backend: backend)
        let configuration = LLMProviderConfiguration(providerID: .appleIntelligence, baseURL: "", credential: .none)

        let fetchedModels = try await adapter.fetchModels(configuration: configuration)
        XCTAssertEqual(fetchedModels, [candidate])

        let request = LLMRequest(
            providerID: .appleIntelligence,
            adapterID: .foundationModels,
            modelID: candidate.id,
            modelCapabilities: candidate.capabilities,
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

        let events = try await collectEvents(adapter.stream(request, configuration: configuration))
        XCTAssertEqual(events, [
            .runStarted(requestID: "apple-request"),
            .textDelta("Hello"),
            .toolCallCompleted(LLMToolCall(
                id: "tool-1",
                callID: "tool-1",
                index: 0,
                name: "lookup",
                argumentsJSON: "{\"q\":\"test\"}"
            )),
            .runCompleted(responseID: "apple-response", modelID: "apple-intelligence-default")
        ])
    }

    func testFoundationModelsAdapterSurfacesLocalBackendAvailabilityFailure() async throws {
        let backend = MockLocalModelBackend(
            availabilityResult: .unavailable("Apple Intelligence unavailable."),
            statusTextResult: "Apple Intelligence unavailable.",
            candidatesResult: []
        )
        let adapter = FoundationModelsAdapter(profile: LLMProviderRegistry.shared.profile(for: .appleIntelligence), backend: backend)
        let configuration = LLMProviderConfiguration(providerID: .appleIntelligence, baseURL: "", credential: .none)

        let request = LLMRequest(
            providerID: .appleIntelligence,
            adapterID: .foundationModels,
            modelID: "apple-intelligence-default",
            messages: [
                LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])
            ]
        )

        do {
            _ = try await collectEvents(adapter.stream(request, configuration: configuration))
            XCTFail("Expected adapter to fail when backend is unavailable.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .authUnavailable("Apple Intelligence unavailable."))
        }
    }

    private func collectEvents(_ stream: AsyncThrowingStream<LLMStreamEvent, Error>) async throws -> [LLMStreamEvent] {
        var events: [LLMStreamEvent] = []
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
    let candidatesResult: [LLMModelDescriptor]
    let streamFactory: (AsyncThrowingStream<LLMStreamEvent, Error>.Continuation) -> Void

    init(
        availabilityResult: LLMLocalModelAvailability,
        statusTextResult: String,
        candidatesResult: [LLMModelDescriptor],
        streamFactory: @escaping (AsyncThrowingStream<LLMStreamEvent, Error>.Continuation) -> Void = { $0.finish() }
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

    func modelCandidates(configuration: LLMProviderConfiguration) -> [LLMModelDescriptor] {
        candidatesResult
    }

    func stream(
        request: LLMRequest,
        configuration: LLMProviderConfiguration
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            streamFactory(continuation)
        }
    }
}

