import Foundation

extension APIConfigurationItem {
    func llmProviderConfiguration(
        profile: LLMProviderProfile? = nil
    ) -> LLMProviderConfiguration {
        let resolvedProfile = profile ?? LLMProviderRegistry.shared.profile(for: providerIDEnum)
        var headers = decodedHeaders
        switch authKindEnum {
        case .bearerToken:
            if !apiKey.isEmpty {
                headers["Authorization"] = "Bearer \(apiKey)"
            }
        case .xAPIKey:
            if !apiKey.isEmpty {
                headers["x-api-key"] = apiKey
            }
            headers["anthropic-version"] = headers["anthropic-version"] ?? "2023-06-01"
        case .none, .customHeaders:
            break
        case .chatGPTOAuth, .chatGPTDeviceCode, .chatGPTCodexToken:
            break
        }

        let options = decodedOptions
        return LLMProviderConfiguration(
            baseURL: baseURL.isEmpty ? resolvedProfile.defaultBaseURL : baseURL,
            headers: headers,
            endpointPaths: resolvedProfile.endpointPaths,
            requestTimeout: Self.secondsOption("request_timeout_seconds", in: options, defaultValue: 60),
            streamIdleTimeout: Self.secondsOption("sse_idle_timeout_seconds", in: options, defaultValue: 120),
            maxResponseBodyBytes: Self.intOption("max_response_body_bytes", in: options, defaultValue: 10 * 1024 * 1024),
            maxSSEEventBytes: Self.intOption("max_sse_event_bytes", in: options, defaultValue: 1024 * 1024)
        )
    }

    private static func secondsOption(
        _ key: String,
        in options: [String: String],
        defaultValue: TimeInterval
    ) -> TimeInterval {
        guard let rawValue = options[key],
              let value = TimeInterval(rawValue),
              value > 0 else {
            return defaultValue
        }
        return value
    }

    private static func intOption(_ key: String, in options: [String: String], defaultValue: Int) -> Int {
        guard let rawValue = options[key],
              let value = Int(rawValue),
              value > 0 else {
            return defaultValue
        }
        return value
    }
}
