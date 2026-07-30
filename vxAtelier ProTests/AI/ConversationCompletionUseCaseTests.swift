import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ConversationCompletionUseCaseTests: LLMTestCase {
    func testStreamModeDisabledUsesNonStreamingWhenModelDoesNotSupportStreaming() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { request in
            let data = request.httpBodyStream.flatMap { stream -> Data? in
                stream.open()
                defer { stream.close() }
                var data = Data()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let count = stream.read(buffer, maxLength: 4096)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
                return data
            } ?? request.httpBody ?? Data()
            let body = try JSONDecoder().decode(JSONValue.self, from: data)
            XCTAssertEqual(body.objectValue?.bool("stream"), false)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_nonstream"]
            )!
            return (response, Data("{\"id\":\"resp\",\"model\":\"gpt-test\",\"output_text\":\"Done\"}".utf8))
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config)
        options.selectedModelID = "gpt-test"
        options.streamMode = .disabled
        let conversation = ConversationItem("Auto stream", options: options)
        let model = ModelItem(modelID: "gpt-test", apiConfiguration: config)
        model.providerSupportedCapabilitiesRaw = [LLMModelCapability.text.rawValue, LLMModelCapability.usage.rawValue]
        env.modelContext.insert(config)
        env.modelContext.insert(model)
        env.modelContext.insert(conversation)

        try await ConversationCompletionUseCase.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        )

        let run = try XCTUnwrap(conversation.turns.first?.responseRuns.first)
        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.requestID, "req_nonstream")
    }

    func testStreamModeEnabledReachesProviderWhenModelReportsStreamingUnsupported() async throws {
        let responseData = Data("""
        data: {"type":"response.created","response":{"id":"resp_stream","model":"gpt-test"}}

        data: {"type":"response.output_text.delta","delta":"Done"}

        data: {"type":"response.completed","response":{"id":"resp_stream","model":"gpt-test"}}

        """.utf8)
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        var requestCount = 0
        MockLLMURLProtocol.requestHandler = { request in
            requestCount += 1
            let data = request.httpBodyStream.flatMap { stream -> Data? in
                stream.open()
                defer { stream.close() }
                var data = Data()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let count = stream.read(buffer, maxLength: 4096)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
                return data
            } ?? request.httpBody ?? Data()
            let body = try JSONDecoder().decode(JSONValue.self, from: data)
            XCTAssertEqual(body.objectValue?.bool("stream"), true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["content-type": "text/event-stream"]
            )!
            return (response, responseData)
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config)
        options.selectedModelID = "gpt-test"
        options.streamMode = .enabled
        let conversation = ConversationItem("Stream required", options: options)
        let model = ModelItem(modelID: "gpt-test", apiConfiguration: config)
        model.providerUnsupportedCapabilitiesRaw = [LLMModelCapability.streaming.rawValue]
        env.modelContext.insert(config)
        env.modelContext.insert(model)
        env.modelContext.insert(conversation)

        try await ConversationCompletionUseCase.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        )

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(conversation.turns.first?.responseRuns.first?.status, .completed)
    }

    func testProviderFailureBeforeAssistantEventRollsBackTurn() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.host, "unit.test")
            XCTAssertEqual(request.url?.path, "/v1/responses")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_failed"]
            )!
            return (response, Data("{\"error\":\"boom\"}".utf8))
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config)
        options.selectedModelID = "gpt-test"
        options.streamMode = .disabled
        let conversation = ConversationItem("Failure", options: options)
        env.modelContext.insert(config)
        insertOpenAIModel(config: config, env: env)
        env.modelContext.insert(conversation)

        await assertThrowsAsyncError(try await ConversationCompletionUseCase.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        ))

        XCTAssertTrue(conversation.turns.isEmpty)
    }

    func testRetryPolicyRetriesTransientProviderErrorOnce() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        var requestCount = 0
        MockLLMURLProtocol.requestHandler = { request in
            requestCount += 1
            if requestCount == 1 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: ["x-request-id": "req_first"]
                )!
                return (response, Data("{\"error\":\"temporary\"}".utf8))
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_second"]
            )!
            let body = Data("""
            {"id":"resp_retry","model":"gpt-test","output_text":"Done","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}
            """.utf8)
            return (response, body)
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config)
        options.selectedModelID = "gpt-test"
        options.streamMode = .disabled
        options.retryPolicy = .oneRetryBeforeTools
        let conversation = ConversationItem("Retry", options: options)
        env.modelContext.insert(config)
        insertOpenAIModel(config: config, env: env)
        env.modelContext.insert(conversation)

        try await ConversationCompletionUseCase.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        )

        XCTAssertEqual(requestCount, 2)
        let run = try XCTUnwrap(conversation.turns.first?.responseRuns.first)
        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.requestID, "req_second")
    }

    func testRetryPolicyDoesNotRetryNonTransientProviderError() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        var requestCount = 0
        MockLLMURLProtocol.requestHandler = { request in
            requestCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_bad"]
            )!
            return (response, Data("{\"error\":\"bad request\"}".utf8))
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config)
        options.selectedModelID = "gpt-test"
        options.streamMode = .disabled
        options.retryPolicy = .oneRetryBeforeTools
        let conversation = ConversationItem("No Retry", options: options)
        env.modelContext.insert(config)
        insertOpenAIModel(config: config, env: env)
        env.modelContext.insert(conversation)

        let draftStore = ConversationDraftStore()
        await assertThrowsAsyncError(try await ConversationCompletionUseCase.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: draftStore
        )) { error in
            guard case .provider(let statusCode, let message, let metadata) = error as? LLMProviderError else {
                return XCTFail("Expected normalized provider rejection, got \(error)")
            }
            XCTAssertEqual(statusCode, 400)
            XCTAssertTrue(message.contains("bad request"))
            XCTAssertEqual(metadata?.requestID, "req_bad")
        }

        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(conversation.turns.isEmpty)
        XCTAssertEqual(draftStore.draft(for: conversation.persistentModelID).runStatus, .failed)
        XCTAssertNotNil(draftStore.draft(for: conversation.persistentModelID).errorMessage)
    }

    func testToolExecutionFailureMarksAwaitingRunFailed() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_tool"]
            )!
            let body = Data("""
            {"id":"resp_tool","model":"gpt-test","output":[{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup","arguments":"{}"}]}
            """.utf8)
            return (response, body)
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config)
        options.selectedModelID = "gpt-test"
        options.streamMode = .disabled
        let conversation = ConversationItem("Tool failure", options: options)
        env.modelContext.insert(config)
        insertOpenAIModel(config: config, env: env)
        env.modelContext.insert(conversation)

        await assertThrowsAsyncError(try await ConversationCompletionUseCase.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        ))

        let run = try XCTUnwrap(conversation.turns.first?.responseRuns.first)
        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.requestID, "req_tool")
        XCTAssertNotNil(run.completedAt)
        XCTAssertEqual(conversation.turns.first?.events.first?.message.toolCallItems.first?.status, .failed)
    }

    func testHTTPMetadataFlowsIntoSuccessfulResponseRun() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "x-request-id": "req_header",
                    "retry-after": "4",
                    "x-ratelimit-remaining-requests": "8"
                ]
            )!
            let body = Data("""
            {"id":"resp_body","model":"gpt-test","output_text":"Done","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}
            """.utf8)
            return (response, body)
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config)
        options.selectedModelID = "gpt-test"
        options.streamMode = .disabled
        let conversation = ConversationItem("Success", options: options)
        env.modelContext.insert(config)
        insertOpenAIModel(config: config, env: env)
        env.modelContext.insert(conversation)

        try await ConversationCompletionUseCase.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        )

        let run = try XCTUnwrap(conversation.turns.first?.responseRuns.first)
        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.requestID, "req_header")
        XCTAssertEqual(run.statusCode, 200)
        XCTAssertEqual(run.retryAfter, "4")
        XCTAssertNotNil(run.responseMetadataJSON)
        XCTAssertEqual(run.inputTokens, 1)
        XCTAssertEqual(run.outputTokens, 2)
        XCTAssertEqual(run.totalTokens, 3)
    }

    func testCancellationAfterRunCreationPersistsCancelledResponseRun() async throws {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { _ in
            throw URLError(.cancelled)
        }

        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            isDefault: true,
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )
        let options = ConversationOptions(apiConfiguration: config)
        options.selectedModelID = "gpt-test"
        options.streamMode = .disabled
        let conversation = ConversationItem("Cancelled", options: options)
        env.modelContext.insert(config)
        insertOpenAIModel(config: config, env: env)
        env.modelContext.insert(conversation)

        await assertThrowsAsyncError(try await ConversationCompletionUseCase.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        )) { error in
            XCTAssertEqual(error as? LLMProviderError, .cancelled)
        }

        XCTAssertTrue(conversation.turns.isEmpty)
    }

    func testPreflightModelErrorRemovesNewUserTurn() async {
        let env = TestEnvironment()
        let config = APIConfigurationItem(
            name: "Custom",
            apiKey: "",
            baseURL: "https://unit.test/v1",
            providerID: .custom
        )
        let options = ConversationOptions(apiConfiguration: config)
        let conversation = ConversationItem("Preflight", options: options)
        env.modelContext.insert(config)
        env.modelContext.insert(conversation)

        await assertThrowsAsyncError(try await ConversationCompletionUseCase.shared.complete(
            conversation: conversation,
            message: "Hello",
            draftStore: ConversationDraftStore()
        ))

        XCTAssertTrue(conversation.turns.isEmpty)
    }

    private func insertOpenAIModel(
        modelID: String = "gpt-test",
        config: APIConfigurationItem,
        env: TestEnvironment
    ) {
        let model = ModelItem(modelID: modelID, apiConfiguration: config)
        model.providerSupportedCapabilitiesRaw = [
            LLMModelCapability.text.rawValue,
            LLMModelCapability.streaming.rawValue,
            LLMModelCapability.usage.rawValue,
            LLMModelCapability.tools.rawValue
        ]
        env.modelContext.insert(model)
    }
}
