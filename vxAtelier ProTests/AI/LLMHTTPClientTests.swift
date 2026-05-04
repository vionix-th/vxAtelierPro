import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMHTTPClientTests: LLMTestCase {
    func testHTTPMetadataExtractsRequestAndRateLimitHeaders() throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://unit.test/v1/responses")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "x-request-id": "req_123",
                "retry-after": "3",
                "x-ratelimit-remaining-requests": "9"
            ]
        ))

        let metadata = LLMHTTPClient().metadata(from: response)
        XCTAssertEqual(metadata.statusCode, 200)
        XCTAssertEqual(metadata.requestID, "req_123")
        XCTAssertEqual(metadata.retryAfter, "3")
        XCTAssertEqual(metadata.rateLimitHeaders["x-ratelimit-remaining-requests"], "9")
    }

    func testHTTPMetadataRedactsSensitiveHeaders() throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://unit.test/v1/responses")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "x-request-id": "req_123",
                "authorization": "Bearer sk-test-secret",
                "set-cookie": "session=secret"
            ]
        ))

        let metadata = LLMHTTPClient().metadata(from: response)
        XCTAssertEqual(metadata.requestID, "req_123")
        XCTAssertEqual(metadata.headers["authorization"], "[redacted]")
        XCTAssertEqual(metadata.headers["set-cookie"], "[redacted]")
    }

    func testProviderConfigurationResolvesAuthHeadersInCore() {
        let openAI = LLMProviderConfiguration(
            providerID: .openAIPlatform,
            baseURL: "https://unit.test",
            credential: .secret("sk-test"),
            customHeaders: ["OpenAI-Organization": "org-test"]
        )
        let openAIHTTP = LLMHTTPClient().makeConfiguration(for: openAI)
        XCTAssertEqual(openAIHTTP.headers["Authorization"], "Bearer sk-test")
        XCTAssertEqual(openAIHTTP.headers["OpenAI-Organization"], "org-test")

        let anthropic = LLMProviderConfiguration(
            providerID: .anthropic,
            baseURL: "https://unit.test",
            credential: .secret("anthropic-key")
        )
        let anthropicHTTP = LLMHTTPClient().makeConfiguration(for: anthropic)
        XCTAssertEqual(anthropicHTTP.headers["x-api-key"], "anthropic-key")
        XCTAssertEqual(anthropicHTTP.headers["anthropic-version"], "2023-06-01")
    }

    func testProviderErrorMessageIsRedactedAndLimited() async {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_secret"]
            )!
            return (response, Data("{\"error\":\"Bearer sk-test-secret should not leak\"}".utf8))
        }

        let client = LLMHTTPClient()
        let config = LLMHTTPClient.Configuration(baseURL: "https://unit.test", headers: [:])
        await assertThrowsAsyncError(try await client.getJSONWithMetadata(
            path: "/v1/models",
            configuration: config,
            responseType: JSONValue.self
        )) { error in
            guard case .provider(let statusCode, let message, let metadata) = error as? LLMProviderError else {
                XCTFail("Expected provider error")
                return
            }
            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(metadata?.requestID, "req_secret")
            XCTAssertFalse(message.contains("sk-test-secret"))
            XCTAssertTrue(message.contains("[redacted]"))
        }
    }

    func testHTTPClientAppliesTimeoutAndResponseSizeOptions() async {
        URLProtocol.registerClass(MockLLMURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }
        MockLLMURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.timeoutInterval, 7)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-request-id": "req_large"]
            )!
            return (response, Data("{\"too\":\"large\"}".utf8))
        }

        let configItem = APIConfigurationItem(
            name: "Custom",
            apiKey: "",
            baseURL: "https://unit.test",
            providerID: .customOpenAICompatible
        )
        configItem.decodedOptions = [
            "request_timeout_seconds": "7",
            "max_response_body_bytes": "4"
        ]
        let config = LLMHTTPClient().makeConfiguration(
            for: configItem.makeLLMProviderConfiguration()
        )

        await assertThrowsAsyncError(try await LLMHTTPClient().getJSONWithMetadata(
            path: "/v1/models",
            configuration: config,
            responseType: JSONValue.self
        )) { error in
            guard case .provider(let statusCode, let message, let metadata) = error as? LLMProviderError else {
                XCTFail("Expected provider error")
                return
            }
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(message, "Provider response exceeded configured size limit.")
            XCTAssertEqual(metadata?.requestID, "req_large")
        }
    }
}
