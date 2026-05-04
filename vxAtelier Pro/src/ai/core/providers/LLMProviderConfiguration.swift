import Foundation

struct LLMProviderConfiguration: Codable, Equatable {
    var baseURL: String
    var headers: [String: String]
    var endpointPaths: [LLMEndpointFamily: String]
    var requestTimeout: TimeInterval
    var streamIdleTimeout: TimeInterval
    var maxResponseBodyBytes: Int
    var maxSSEEventBytes: Int

    init(
        baseURL: String,
        headers: [String: String] = [:],
        endpointPaths: [LLMEndpointFamily: String] = [:],
        requestTimeout: TimeInterval = 60,
        streamIdleTimeout: TimeInterval = 120,
        maxResponseBodyBytes: Int = 10 * 1024 * 1024,
        maxSSEEventBytes: Int = 1024 * 1024
    ) {
        self.baseURL = baseURL
        self.headers = headers
        self.endpointPaths = endpointPaths
        self.requestTimeout = requestTimeout
        self.streamIdleTimeout = streamIdleTimeout
        self.maxResponseBodyBytes = maxResponseBodyBytes
        self.maxSSEEventBytes = maxSSEEventBytes
    }

    func endpointPath(for endpointFamily: LLMEndpointFamily) -> String? {
        endpointPaths[endpointFamily]
    }
}
