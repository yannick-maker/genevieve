import Foundation

/// Claude API provider implementation using Anthropic's Messages API
@MainActor
final class ClaudeProvider: AIProvider, StreamingAIProvider, ObservableObject {
    let providerType: AIProviderType = .claude

    @Published private(set) var isConfigured = false

    var availableModels: [AIModel] {
        [.claude4Sonnet, .claude4Opus]
    }

    // MARK: - Private Properties

    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"
    private var apiKey: String?
    private let keychainManager: KeychainManager
    private let urlSession: URLSession

    // MARK: - Initialization

    nonisolated init(keychainManager: KeychainManager = .shared) {
        self.keychainManager = keychainManager

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)
    }

    func loadAPIKey() async {
        apiKey = try? keychainManager.retrieve(for: .claudeAPIKey)
        isConfigured = apiKey != nil
    }

    // MARK: - AIProvider Protocol

    func configure(apiKey: String) async throws {
        try keychainManager.save(apiKey, for: .claudeAPIKey)
        self.apiKey = apiKey
        isConfigured = true
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        let originalKey = apiKey
        apiKey = key
        defer { apiKey = originalKey }

        let testRequest = AIRequest(
            prompt: "Say 'ok'",
            maxTokens: 10
        )

        do {
            _ = try await generate(request: testRequest, model: .claude4Sonnet)
            return true
        } catch AIProviderError.invalidAPIKey {
            return false
        } catch {
            // Other errors (network, etc.) - key might still be valid
            throw error
        }
    }

    func generate(request: AIRequest, model: AIModel) async throws -> AIResponse {
        guard let apiKey = apiKey else {
            throw AIProviderError.notConfigured
        }

        guard model.provider == .claude else {
            throw AIProviderError.modelUnavailable(model)
        }

        let httpRequest = try buildRequest(request: request, model: model, apiKey: apiKey)

        let (data, response) = try await urlSession.data(for: httpRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse("Not an HTTP response")
        }

        return try handleResponse(data: data, httpResponse: httpResponse, model: model)
    }

    func generateStream(
        request: AIRequest,
        model: AIModel
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = apiKey else {
                        throw AIProviderError.notConfigured
                    }

                    var httpRequest = try buildRequest(request: request, model: model, apiKey: apiKey, stream: true)
                    httpRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await urlSession.bytes(for: httpRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIProviderError.invalidResponse("Not an HTTP response")
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw AIProviderError.invalidResponse("HTTP \(httpResponse.statusCode)")
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" {
                                break
                            }

                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let delta = json["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func buildRequest(
        request: AIRequest,
        model: AIModel,
        apiKey: String,
        stream: Bool = false
    ) throws -> URLRequest {
        var urlRequest = URLRequest(url: URL(string: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        // Build content array
        var contentParts: [[String: Any]] = []

        // Add images if present
        if let images = request.images {
            for imageData in images {
                contentParts.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": imageData.base64EncodedString()
                    ]
                ])
            }
        }

        // Add text prompt
        contentParts.append([
            "type": "text",
            "text": request.prompt
        ])

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": contentParts
            ]
        ]

        var requestBody: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": request.maxTokens,
            "messages": messages,
            "temperature": request.temperature
        ]

        if let systemPrompt = request.systemPrompt {
            requestBody["system"] = systemPrompt
        }

        if stream {
            requestBody["stream"] = true
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        return urlRequest
    }

    private func handleResponse(
        data: Data,
        httpResponse: HTTPURLResponse,
        model: AIModel
    ) throws -> AIResponse {
        switch httpResponse.statusCode {
        case 200:
            return try parseSuccessResponse(data: data, model: model)

        case 401:
            throw AIProviderError.invalidAPIKey

        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                .flatMap { Double($0) }
            throw AIProviderError.rateLimited(retryAfter: retryAfter)

        case 400:
            if let errorMessage = extractErrorMessage(from: data) {
                throw AIProviderError.invalidResponse(errorMessage)
            }
            throw AIProviderError.invalidResponse("Bad request")

        case 500, 502, 503:
            throw AIProviderError.modelUnavailable(model)

        default:
            if let errorMessage = extractErrorMessage(from: data) {
                throw AIProviderError.invalidResponse(errorMessage)
            }
            throw AIProviderError.invalidResponse("HTTP \(httpResponse.statusCode)")
        }
    }

    private func parseSuccessResponse(data: Data, model: AIModel) throws -> AIResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse("Could not parse JSON")
        }

        guard let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIProviderError.invalidResponse("Could not extract text from response")
        }

        // Parse usage
        var usage: AIResponse.TokenUsage?
        if let usageJson = json["usage"] as? [String: Any],
           let input = usageJson["input_tokens"] as? Int,
           let output = usageJson["output_tokens"] as? Int {
            usage = AIResponse.TokenUsage(inputTokens: input, outputTokens: output)
        }

        // Parse finish reason
        let stopReason = json["stop_reason"] as? String
        let finishReason: AIResponse.FinishReason
        switch stopReason {
        case "end_turn":
            finishReason = .complete
        case "max_tokens":
            finishReason = .maxTokens
        case "content_filter":
            finishReason = .contentFilter
        default:
            finishReason = .complete
        }

        return AIResponse(
            content: text,
            model: model,
            usage: usage,
            finishReason: finishReason
        )
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}
