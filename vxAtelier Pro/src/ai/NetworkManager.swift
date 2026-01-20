import Foundation

/// Represents errors that can occur during network operations
enum NetworkError: LocalizedError {
    case invalidURL(String)
    case networkFailure(URLError)  // Underlying connection/DNS/etc errors
    case invalidResponse  // Non-HTTP response
    case serverError(statusCode: Int, message: String)  // HTTP errors with response
    case decodingError(DecodingError)  // JSON parsing errors
    case jsonParsingError  // Error parsing JSON from streaming response
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .networkFailure(let error):
            return error.localizedDescription
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .jsonParsingError:
            return "Failed to parse JSON from stream data"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .invalidURL:
            return "The URL string could not be converted to a valid URL"
        case .networkFailure(let error):
            switch error.code {
            case .notConnectedToInternet:
                return "No internet connection is available"
            case .timedOut:
                return "The request timed out"
            case .cannotFindHost:
                return "The server host could not be found"
            case .networkConnectionLost:
                return "The network connection was interrupted"
            default:
                return error.localizedDescription
            }
        case .invalidResponse:
            return "The server response was not in the expected HTTP format"
        case .serverError(let statusCode, _):
            return "The server returned an error status code \(statusCode)"
        case .decodingError(let error):
            switch error {
            case .typeMismatch(_, let context):
                return "Type mismatch at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
            case .valueNotFound(_, let context):
                return "Missing value at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
            case .keyNotFound(let key, _):
                return "Missing key: \(key.stringValue)"
            case .dataCorrupted(let context):
                return context.debugDescription
            @unknown default:
                return error.localizedDescription
            }
        case .jsonParsingError:
            return "The stream data could not be parsed as valid JSON"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return "Check that the URL is properly formatted and encoded"
        case .networkFailure(let error):
            switch error.code {
            case .notConnectedToInternet:
                return "Check your internet connection and try again"
            case .timedOut:
                return "The request timed out. Try again or check your connection speed"
            case .cannotFindHost:
                return "The server could not be found. Verify the host name is correct"
            case .networkConnectionLost:
                return "The network connection was lost. Please try again"
            default:
                return "Check your network connection and try again"
            }
        case .invalidResponse:
            return "Contact support if the problem persists"
        case .serverError(let statusCode, _):
            switch statusCode {
            case 401:
                return "Check your authentication credentials"
            case 403:
                return "You don't have permission to access this resource"
            case 404:
                return "The requested resource could not be found"
            case 429:
                return "Too many requests. Please wait and try again later"
            case 500...599:
                return "This is a server error. Please try again later or contact support if the problem persists"
            default:
                return "Check the error message and try again"
            }
        case .decodingError:
            return "The server response was not in the expected format. Contact support if the problem persists"
        case .jsonParsingError:
            return "The streaming data format may have changed. Please contact support if the problem persists"
        }
    }
}

/// Added SelfSignedCertificateDelegate to allow self-signed certificates when configured
class SelfSignedCertificateDelegate: NSObject, URLSessionDelegate {
    weak var networkManager: NetworkManager?
    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let host = challenge.protectionSpace.host
            if let manager = networkManager,
               manager.allowSelfSignedCertificates,
               manager.isHostAllowedByWhitelist(host: host) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

/// NetworkManager handles all HTTP network requests in the application
/// It provides a centralized way to make API calls with proper error handling and logging
class NetworkManager {
    // MARK: - Singleton Instance
    
    /// NEW: Allow self-signed certificates if set to true (default is false), stored in UserDefaults
    var allowSelfSignedCertificates: Bool {
        get { UserDefaults.standard.bool(forKey: AppSettings.Keys.allowSelfSignedCertificates) }
        set {
            let oldValue = UserDefaults.standard.bool(forKey: AppSettings.Keys.allowSelfSignedCertificates)
            if oldValue != newValue {
                UserDefaults.standard.set(newValue, forKey: AppSettings.Keys.allowSelfSignedCertificates)
                configureSession()
            }
        }
    }
    /// Whitelist of regex patterns for allowed hosts (from UserDefaults)
    var selfSignedCertWhitelist: [String] {
        guard let json = UserDefaults.standard.string(forKey: AppSettings.Keys.selfSignedCertWhitelist),
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }
    /// Helper: Check if a host matches any whitelist regex
    func isHostAllowedByWhitelist(host: String) -> Bool {
        for pattern in selfSignedCertWhitelist {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(location: 0, length: host.utf16.count)
                if regex.firstMatch(in: host, options: [], range: range) != nil {
                    return true
                }
            }
        }
        return false
    }
    private var session: URLSession = URLSession.shared

    static let shared = NetworkManager()
    private init() {
        configureSession()
        NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange(_:)), name: UserDefaults.didChangeNotification, object: nil)
    }
    
    // MARK: - Network Operations
    
    /// Configure the URLSession to always use the delegate, which enforces both the toggle and the whitelist
    private func configureSession() {
        session = URLSession(configuration: .default,
                             delegate: SelfSignedCertificateDelegate(networkManager: self),
                             delegateQueue: nil)
    }
    
    /// Performs a POST request with JSON body and custom headers
    /// - Parameters:
    ///   - url: The target URL string
    ///   - body: The request body as a dictionary
    ///   - responseType: The expected response type
    ///   - headers: HTTP headers to include in the request
    /// - Returns: Decoded response of type T
    /// - Throws: NetworkError describing what went wrong
    func postRequest<T: Decodable>(
        url: String, 
        body: [String: Any], 
        responseType: T.Type, 
        headers: [String: String]
    ) async throws -> T {
        guard let url = URL(string: url) else {
            let message = "Invalid URL for POST request: \(url)"
            await vxAtelierPro.log.error("🔴 \(message)")
            throw NetworkError.invalidURL(url)
        }
        
        await vxAtelierPro.log.debug("📤 Preparing POST request to \(url.absoluteString)")
        await logHeaders(headers, label: "📤 Request")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Apply all headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let json = try JSONSerialization.data(withJSONObject: body, options: [])
        request.httpBody = json
        
        await logBody(body, label: "📤 Request")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let message = "Invalid response type"
                await vxAtelierPro.log.error("🔴 \(message)")
                throw NetworkError.invalidResponse
            }
            
            await logHeaders(httpResponse.allHeaderFields, label: "📥 Response")
            
            await logData(data, label: "📥 Response")
            
            if !(200..<300).contains(httpResponse.statusCode) {
                var errorMessage = "Request failed with status code \(httpResponse.statusCode)"                            
                
                await logData(data, label: "🔴 \(errorMessage):")                

                if let errorText = String(data: data, encoding: .utf8) {
                    errorMessage += ": \(errorText.prefix(200))"
                }
                throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
            await vxAtelierPro.log.debug("📥 Received successful response (\(data.count) bytes)")
            return try JSONDecoder().decode(T.self, from: data)
            
        } catch let error as DecodingError {
            await vxAtelierPro.log.error("🔴 Response decoding error - \(error.localizedDescription)")
            throw NetworkError.decodingError(error)
        } catch let error as URLError {
            await vxAtelierPro.log.error("🔴 Network error - \(error.localizedDescription)")
            throw NetworkError.networkFailure(error)
        } catch let error as NetworkError {            
            throw error
        } catch {
            await vxAtelierPro.log.error("🔴 Unexpected error - \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Performs a POST request with JSON body and authorization using Bearer token
    /// - Parameters:
    ///   - url: The target URL string
    ///   - body: The request body as a dictionary
    ///   - responseType: The expected response type
    ///   - apiKey: The API key for authorization
    /// - Returns: Decoded response of type T
    /// - Throws: URLError for network/request issues, DecodingError for response parsing issues
    func postRequest<T: Decodable>(url: String, body: [String: Any], responseType: T.Type, apiKey: String) async throws -> T {
        return try await postRequest(
            url: url,
            body: body,
            responseType: responseType,
            headers: ["Authorization": "Bearer \(apiKey)"]
        )
    }
    
    /// Performs a streaming request and processes the response as a stream of JSON objects
    /// - Parameters:
    ///   - url: The target URL string
    ///   - body: The request body as a dictionary
    ///   - headers: HTTP headers to include in the request
    ///   - chunkProcessor: A closure that processes each JSON chunk from the stream
    ///   - completionHandler: A closure that's called when the stream completes
    ///   - errorHandler: A closure that's called when an error occurs
    func streamRequest(
        url: String,
        body: [String: Any],
        headers: [String: String],
        chunkProcessor: @escaping ([String: Any]) async -> Void,
        completionHandler: @escaping () async -> Void,
        errorHandler: @escaping (Error) async -> Void
    ) async {
        guard let url = URL(string: url) else {
            let message = "Invalid URL for streaming request: \(url)"
            await vxAtelierPro.log.error("🔴 \(message)")
            await errorHandler(NetworkError.invalidURL(url))
            return
        }
        
        await vxAtelierPro.log.debug("📤 Preparing streaming request to \(url.absoluteString)")
        await logHeaders(headers, label: "📤 Streaming request")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Apply all headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        var fullResponse = ""
        let logFullResponse: () async -> Void = {
            if let jsonData = fullResponse.data(using: .utf8) {
                await self.logData(jsonData, label: "📥 Full streaming response")
            } else {
                await vxAtelierPro.log.debug("📥 Full streaming response body: <unavailable>")
            }
        }
        do {
            let json = try JSONSerialization.data(withJSONObject: body, options: [])
            request.httpBody = json
            
            await logBody(body, label: "📤 Streaming request")
            
            // Use custom session instead of URLSession.shared
            let (asyncBytes, response) = try await session.bytes(for: request)
            
            // Check HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                await vxAtelierPro.log.error("🔴 Invalid response type from streaming request")
                await errorHandler(NetworkError.invalidResponse)
                return
            }
            
            await logHeaders(httpResponse.allHeaderFields, label: "📥 Streaming response")
            
            if !(200..<300).contains(httpResponse.statusCode) {
                let message = "Streaming request failed with status code \(httpResponse.statusCode)"
                await vxAtelierPro.log.error("🔴 \(message)")
                await errorHandler(NetworkError.serverError(statusCode: httpResponse.statusCode, message: "HTTP Error"))
                return
            }
            
            await vxAtelierPro.log.debug("📥 Streaming response started, processing chunks...")
            
            // Process the stream chunk by chunk
            var chunkCount = 0
            for try await line in asyncBytes.lines {
                // Skip empty lines
                guard !line.isEmpty else { continue }
                
                // Skip lines that don't start with "data:" (common in SSE)
                if line.hasPrefix("data: ") {
                    let dataString = line.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Handle special case for stream end marker
                    if dataString == "[DONE]" {
                        await vxAtelierPro.log.debug("📥 Stream end marker received")
                        continue
                    }
                    
                    // Parse JSON data
                    if let jsonData = dataString.data(using: .utf8),
                       let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
                       let json = jsonObject as? [String: Any] {
                        // Process the JSON object
                        await chunkProcessor(json)
                        chunkCount += 1
                        fullResponse += dataString + "\n"
                        
                        // Log occasionally to avoid flooding logs
                        if chunkCount % 50 == 0 {
                            await vxAtelierPro.log.debug("📥 Processed \(chunkCount) JSON chunks...")
                        }
                    } else {
                        await vxAtelierPro.log.warning("⚠️ Failed to parse JSON from chunk: \(dataString)")
                        fullResponse += dataString + "\n"
                    }
                } else {
                    // Try to parse the line directly as JSON if it doesn't have the data: prefix
                    if let jsonData = line.data(using: .utf8),
                       let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
                       let json = jsonObject as? [String: Any] {
                        await chunkProcessor(json)
                        chunkCount += 1
                        fullResponse += line + "\n"
                    } else if let string = String(data: line.data(using: .utf8) ?? Data(), encoding: .utf8) {
                        await logData((string.data(using: .utf8) ?? Data()), label: "📥 Stream chunk (plain text)")
                        fullResponse += string + "\n"
                    } else {
                        let base64 = (line.data(using: .utf8) ?? Data()).base64EncodedString()
                        await logData((line.data(using: .utf8) ?? Data()), label: "📥 Stream chunk (base64)")
                        fullResponse += base64 + "\n"
                    }
                }
            }
            
            await logFullResponse()
            
            await vxAtelierPro.log.debug("📥 Stream completed, processed \(chunkCount) total JSON chunks")
            await completionHandler()
            
        } catch let error as URLError {
            await vxAtelierPro.log.error("🔴 Streaming network error - \(error.localizedDescription)")
            await logFullResponse()
            await errorHandler(NetworkError.networkFailure(error))
        } catch {
            await vxAtelierPro.log.error("🔴 Unexpected streaming error - \(error.localizedDescription)")
            await logFullResponse()
            await errorHandler(error)
        }
    }
    
    /// Performs a streaming request with Bearer token authentication
    /// - Parameters:
    ///   - url: The target URL string
    ///   - body: The request body as a dictionary
    ///   - apiKey: The API key for authorization
    ///   - chunkProcessor: A closure that processes each JSON chunk from the stream
    ///   - completionHandler: A closure that's called when the stream completes
    ///   - errorHandler: A closure that's called when an error occurs
    func streamRequest(
        url: String,
        body: [String: Any],
        apiKey: String,
        chunkProcessor: @escaping ([String: Any]) async -> Void,
        completionHandler: @escaping () async -> Void,
        errorHandler: @escaping (Error) async -> Void
    ) async {
        await streamRequest(
            url: url,
            body: body,
            headers: ["Authorization": "Bearer \(apiKey)"],
            chunkProcessor: chunkProcessor,
            completionHandler: completionHandler,
            errorHandler: errorHandler
        )
    }
    
    /// Performs a GET request with custom headers
    /// - Parameters:
    ///   - url: The target URL string
    ///   - headers: HTTP headers to include in the request
    ///   - responseType: The expected response type
    /// - Returns: Decoded response of type T
    /// - Throws: NetworkError describing what went wrong
    func getRequest<T: Decodable>(
        url: String, 
        headers: [String: String],
        responseType: T.Type
    ) async throws -> T {
        guard let url = URL(string: url) else {
            let message = "Invalid URL for GET request: \(url)"
            await vxAtelierPro.log.error("🔴 \(message)")
            throw NetworkError.invalidURL(url)
        }
        
        await vxAtelierPro.log.debug("📤 Preparing GET request to \(url.absoluteString)")
        await logHeaders(headers, label: "📤 Request")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Apply all headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let message = "Invalid response type"
                await vxAtelierPro.log.error("🔴 \(message)")
                throw NetworkError.invalidResponse
            }
            
            await logHeaders(httpResponse.allHeaderFields, label: "📥 Response")
            
            await logData(data, label: "📥 Response")
            
            if !(200..<300).contains(httpResponse.statusCode) {
                let message = "Request failed with status code \(httpResponse.statusCode)"
                await vxAtelierPro.log.error("🔴 \(message)")
                
                await vxAtelierPro.log.error("🔴 Error response:")
                await logData(data, label: "🔴 Error response")
                var errorMessage = "HTTP Error"
                if let errorText = String(data: data, encoding: .utf8) {
                    errorMessage += ": \(errorText.prefix(200))"
                }
                throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
            await vxAtelierPro.log.debug("📥 Received successful response (\(data.count) bytes)")
            return try JSONDecoder().decode(T.self, from: data)
            
        } catch let error as DecodingError {
            await vxAtelierPro.log.error("🔴 Response decoding error - \(error.localizedDescription)")
            throw NetworkError.decodingError(error)
        } catch let error as URLError {
            await vxAtelierPro.log.error("🔴 Network error - \(error.localizedDescription)")
            throw NetworkError.networkFailure(error)
        } catch {
            await vxAtelierPro.log.error("🔴 Unexpected error - \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Performs a GET request with authorization using Bearer token
    /// - Parameters:
    ///   - url: The target URL string
    ///   - apiKey: The API key for authorization
    ///   - responseType: The expected response type
    /// - Returns: Decoded response of type T
    /// - Throws: URLError for network/request issues, DecodingError for response parsing issues
    func getRequest<T: Decodable>(url: String, apiKey: String, responseType: T.Type) async throws -> T {
        return try await getRequest(
            url: url,
            headers: ["Authorization": "Bearer \(apiKey)"],
            responseType: responseType
        )
    }

    @objc private func userDefaultsDidChange(_ notification: Notification) {
        configureSession()
    }

    // MARK: - Logging Helpers

    /// Logs headers as pretty-printed JSON
    private func logHeaders(_ headers: [AnyHashable: Any], label: String, file: String = #file, function: String = #function, line: Int = #line) async {
        if let headersData = try? JSONSerialization.data(withJSONObject: headers, options: [.prettyPrinted]),
           let headersString = String(data: headersData, encoding: .utf8) {
            await vxAtelierPro.log.debug("\(label) headers:\n\(headersString)", file: file, function: function, line: line)
        } else {
            await vxAtelierPro.log.debug("\(label) headers: <unavailable>", file: file, function: function, line: line)
        }
    }

    /// Logs a request body (Any, typically [String: Any]) as JSON, plain text, or base64
    private func logBody(_ body: Any, label: String, file: String = #file, function: String = #function, line: Int = #line) async {
        if let jsonData = try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            await vxAtelierPro.log.debug("\(label) body:\n\(jsonString)", file: file, function: function, line: line)
        } else if let jsonData = try? JSONSerialization.data(withJSONObject: body),
                  let string = String(data: jsonData, encoding: .utf8) {
            await vxAtelierPro.log.debug("\(label) body (plain text):\n\(string)", file: file, function: function, line: line)
        } else if let jsonData = try? JSONSerialization.data(withJSONObject: body) {
            let base64 = jsonData.base64EncodedString()
            await vxAtelierPro.log.debug("\(label) body (base64):\n\(base64)", file: file, function: function, line: line)
        } else {
            await vxAtelierPro.log.debug("\(label) body: <unavailable>", file: file, function: function, line: line)
        }
    }

    /// Logs a Data object as JSON, plain text, or base64
    private func logData(_ data: Data, label: String, file: String = #file, function: String = #function, line: Int = #line) async {
        if let responseObject = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: responseObject, options: [.prettyPrinted]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            await vxAtelierPro.log.debug("\(label) body:\n\(prettyString)", file: file, function: function, line: line)
        } else if let responseText = String(data: data, encoding: .utf8) {
            await vxAtelierPro.log.debug("\(label) body (plain text):\n\(responseText)", file: file, function: function, line: line)
        } else {
            let base64 = data.base64EncodedString()
            await vxAtelierPro.log.debug("\(label) body (base64):\n\(base64)", file: file, function: function, line: line)
        }
    }
}
