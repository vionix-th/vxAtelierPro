import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
class LLMTestCase: XCTestCase {
    func installFixtureHandler(name: String, fileExtension ext: String) throws {
        let data = try fixtureData(name: name, fileExtension: ext)
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        MockLLMURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "x-request-id": "req_fixture",
                    "content-type": ext == "sse" ? "text/event-stream" : "application/json"
                ]
            )!
            return (response, data)
        }
    }

    func fixtureData(name: String, fileExtension ext: String) throws -> Data {
        let url = try XCTUnwrap(fixtureURL(name: name, fileExtension: ext))
        return try Data(contentsOf: url)
    }

    func fixtureURL(name: String, fileExtension ext: String) -> URL? {
        let bundle = Bundle(for: LLMTestCase.self)
        return bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "AI/Fixtures")
    }

    func fixtureJSON(name: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: fixtureData(name: name, fileExtension: "json"))
    }

    func collectEvents(
        _ stream: AsyncThrowingStream<LLMStreamEvent, Error>
    ) async throws -> [LLMStreamEvent] {
        var events: [LLMStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    func makeToolExecutionFixture(
        toolName: String
    ) -> (environment: TestEnvironment, conversation: ConversationItem, turn: ConversationTurn, toolCall: ToolCallItem) {
        let env = TestEnvironment()
        let conversation = ConversationItem("Tool Test", options: ConversationOptions(shouldSetupParameters: false))
        let userMessage = MessageItem(role: "user", text: "Run tool")
        let turn = ConversationTurn(sequenceNumber: 0, userMessage: userMessage, conversation: conversation)
        let toolCall = ToolCallItem(
            callID: "call_1",
            providerCallID: "provider_call_1",
            index: 0,
            name: toolName,
            argumentsJSON: "{\"value\":\"ok\"}"
        )
        conversation.turns.append(turn)
        env.modelContext.insert(conversation)
        return (env, conversation, turn, toolCall)
    }
}

struct UnitEchoTool: ExecutableLLMTool {
    static let toolName = "unit_echo_tool"

    let name = UnitEchoTool.toolName
    let description = "Echoes typed tool execution fields for unit tests."
    var parameters: any LLMToolParameters { GenericLLMToolParameters(properties: [:]) }

    func execute(_ call: LLMToolExecutionCall) async throws -> String {
        "id=\(call.id) name=\(call.name) args=\(call.argumentsJSON) config=\(call.configuration.count) title=\(call.context.conversation.title) turn=\(call.context.turn.sequenceNumber)"
    }
}

struct UnitFailingTool: ExecutableLLMTool {
    static let toolName = "unit_failing_tool"

    let name = UnitFailingTool.toolName
    let description = "Fails execution for unit tests."
    var parameters: any LLMToolParameters { GenericLLMToolParameters(properties: [:]) }

    func execute(_ call: LLMToolExecutionCall) async throws -> String {
        throw LLMToolExecutionError.executionFailed("unit failure")
    }
}

struct UnitSchemaOnlyTool: LLMTool {
    static let toolName = "unit_schema_only_tool"

    let name = UnitSchemaOnlyTool.toolName
    let description = "Schema-only unit test tool."
    var parameters: any LLMToolParameters { GenericLLMToolParameters(properties: [:]) }
}

struct StaticLLMToolCatalog: LLMToolCatalog {
    private let toolsByName: [String: LLMTool]

    init(_ tools: [LLMTool]) {
        self.toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    func allTools() -> [LLMTool] {
        Array(toolsByName.values)
    }

    func tool(named name: String) -> LLMTool? {
        toolsByName[name]
    }
}

@MainActor
final class RecordingDraftSink: ConversationDraftSink {
    private(set) var text = ""
    private(set) var toolCalls: [LLMToolCall] = []
    private(set) var startCount = 0
    private(set) var resetCount = 0
    private(set) var completed = false
    private(set) var failedError: Error?

    func start(conversationID: PersistentIdentifier) {
        startCount += 1
    }

    func reset(conversationID: PersistentIdentifier) {
        resetCount += 1
        text = ""
        toolCalls = []
    }

    func appendContent(_ content: String, conversationID: PersistentIdentifier) {
        text += content
    }

    func updateToolCalls(_ toolCalls: [LLMToolCall], conversationID: PersistentIdentifier) {
        self.toolCalls = toolCalls
    }

    func complete(conversationID: PersistentIdentifier) {
        completed = true
    }

    func fail(_ error: Error, conversationID: PersistentIdentifier) {
        failedError = error
    }
}

final class MockLLMURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "unit.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
