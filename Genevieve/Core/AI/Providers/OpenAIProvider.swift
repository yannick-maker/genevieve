import Foundation

/// OpenAI API provider implementation
@MainActor
final class OpenAIProvider: AIProvider, StreamingAIProvider, ObservableObject {
    let providerType: AIProviderType = .openAI

    @Published private(set) var isConfigured = false

    var availableModels: [AIModel] {
        [.gpt52, .gpt52Pro]
    }

    // MARK: - Private Properties

    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private var apiKey: String?
    private let keychainManager: KeychainManager
    private let urlSession: URLSession

    // MARK: - Initialization

    init(keychainManager: KeychainManager = .shared) {
        self.keychainManager = keychainManager

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)
    }

    func loadAPIKey() async {
        apiKey = try? keychainManager.retrieve(for: .openAIAPIKey)
        isConfigured = apiKey != nil
    }

    // MARK: - AIProvider Protocol

    func configure(apiKey: String) async throws {
        try keychainManager.save(apiKey, for: .openAIAPIKey)
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
            _ = try await generate(request: testRequest, model: .gpt52)
            return true
        } catch AIProviderError.invalidAPIKey {
            return false
        } catch {
            throw error
        }
    }

    func generate(request: AIRequest, model: AIModel) async throws -> AIResponse {
        guard let apiKey = apiKey else {
            throw AIProviderError.notConfigured
        }

        guard model.provider == .openAI else {
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

                    var httpRequest = try buildRequest(
                        request: request,
                        model: model,
                        apiKey: apiKey,
                        stream: true
                    )
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
                               let choices = json["choices"] as? [[String: Any]],
                               let firstChoice = choices.first,
                               let delta = firstChoice["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
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
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var messages: [[String: Any]] = []

        // Add system message if present
        if let systemPrompt = request.systemPrompt {
            messages.append([
                "role": "system",
                "content": systemPrompt
            ])
        }

        // Build user message content
        var userContent: Any

        if let images = request.images, !images.isEmpty {
            // Multimodal message with images
            var contentParts: [[String: Any]] = []

            for imageData in images {
                contentParts.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"
                    ]
                ])
            }

            contentParts.append([
                "type": "text",
                "text": request.prompt
            ])

            userContent = contentParts
        } else {
            // Text-only message
            userContent = request.prompt
        }

        messages.append([
            "role": "user",
            "content": userContent
        ])

        var requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": messages,
            "temperature": request.temperature,
            "max_completion_tokens": request.maxTokens
        ]

        if stream {
            requestBody["stream"] = true
        }

        // Add JSON response format if requested
        if case .json = request.responseFormat {
            requestBody["response_format"] = ["type": "json_object"]
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

        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIProviderError.invalidResponse("Could not extract content from response")
        }

        // Parse usage
        var usage: AIResponse.TokenUsage?
        if let usageJson = json["usage"] as? [String: Any],
           let promptTokens = usageJson["prompt_tokens"] as? Int,
           let completionTokens = usageJson["completion_tokens"] as? Int {
            usage = AIResponse.TokenUsage(inputTokens: promptTokens, outputTokens: completionTokens)
        }

        // Parse finish reason
        let finishReasonString = firstChoice["finish_reason"] as? String
        let finishReason: AIResponse.FinishReason
        switch finishReasonString {
        case "stop":
            finishReason = .complete
        case "length":
            finishReason = .maxTokens
        case "content_filter":
            finishReason = .contentFilter
        default:
            finishReason = .complete
        }

        return AIResponse(
            content: content,
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
