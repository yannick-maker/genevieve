import Foundation

/// Google Gemini API provider implementation
@MainActor
final class GeminiProvider: AIProvider, StreamingAIProvider, ObservableObject {
    let providerType: AIProviderType = .gemini

    @Published private(set) var isConfigured = false

    var availableModels: [AIModel] {
        [.gemini3Pro, .gemini3Flash]
    }

    // MARK: - Private Properties

    private let baseURLTemplate = "https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent"
    private let streamURLTemplate = "https://generativelanguage.googleapis.com/v1beta/models/%@:streamGenerateContent"
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
        apiKey = try? keychainManager.retrieve(for: .geminiAPIKey)
        isConfigured = apiKey != nil
    }

    // MARK: - AIProvider Protocol

    func configure(apiKey: String) async throws {
        try keychainManager.save(apiKey, for: .geminiAPIKey)
        self.apiKey = apiKey
        isConfigured = true
    }

    func validateAPIKey(_ key: String) async throws -> Bool {
        let originalKey = apiKey
        apiKey = key
        defer { apiKey = originalKey }

        let testRequest = AIRequest(
            prompt: "Say 'ok'",
            maxTokens: 100  // Gemini 3 needs more tokens due to thinking
        )

        do {
            _ = try await generate(request: testRequest, model: .gemini3Flash)
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

        guard model.provider == .gemini else {
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

                    let httpRequest = try buildStreamRequest(request: request, model: model, apiKey: apiKey)

                    let (bytes, response) = try await urlSession.bytes(for: httpRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIProviderError.invalidResponse("Not an HTTP response")
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw AIProviderError.invalidResponse("HTTP \(httpResponse.statusCode)")
                    }

                    // Gemini streams JSON objects separated by newlines
                    var buffer = ""
                    for try await line in bytes.lines {
                        buffer += line

                        // Try to parse accumulated buffer as JSON
                        if let data = buffer.data(using: .utf8) {
                            // Gemini returns array of responses for streaming
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                                for item in json {
                                    if let text = extractTextFromStreamChunk(item) {
                                        continuation.yield(text)
                                    }
                                }
                                buffer = ""
                            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                // Single object
                                if let text = extractTextFromStreamChunk(json) {
                                    continuation.yield(text)
                                }
                                buffer = ""
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

    private func extractTextFromStreamChunk(_ json: [String: Any]) -> String? {
        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return nil
        }

        // Find text parts (skip thinking parts if present)
        for part in parts {
            if let text = part["text"] as? String {
                return text
            }
        }
        return nil
    }

    private func buildStreamRequest(
        request: AIRequest,
        model: AIModel,
        apiKey: String
    ) throws -> URLRequest {
        let modelName = model.rawValue
        let urlString = String(format: streamURLTemplate, modelName) + "?key=\(apiKey)&alt=sse"

        guard let url = URL(string: urlString) else {
            throw AIProviderError.invalidResponse("Invalid URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        // Build parts array
        var parts: [[String: Any]] = []

        // Add images if present
        if let images = request.images {
            for imageData in images {
                parts.append([
                    "inline_data": [
                        "mime_type": "image/jpeg",
                        "data": imageData.base64EncodedString()
                    ]
                ])
            }
        }

        // Add text prompt
        parts.append(["text": request.prompt])

        var requestBody: [String: Any] = [
            "contents": [
                ["parts": parts]
            ],
            "generationConfig": [
                "temperature": request.temperature,
                "maxOutputTokens": request.maxTokens
            ]
        ]

        // Add system instruction if present
        if let systemPrompt = request.systemPrompt {
            requestBody["systemInstruction"] = [
                "parts": [["text": systemPrompt]]
            ]
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        return urlRequest
    }

    // MARK: - Private Helpers

    private func buildRequest(
        request: AIRequest,
        model: AIModel,
        apiKey: String
    ) throws -> URLRequest {
        let modelName = model.rawValue
        let urlString = String(format: baseURLTemplate, modelName) + "?key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw AIProviderError.invalidResponse("Invalid URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build parts array
        var parts: [[String: Any]] = []

        // Add images if present
        if let images = request.images {
            for imageData in images {
                parts.append([
                    "inline_data": [
                        "mime_type": "image/jpeg",
                        "data": imageData.base64EncodedString()
                    ]
                ])
            }
        }

        // Add text prompt
        parts.append(["text": request.prompt])

        var requestBody: [String: Any] = [
            "contents": [
                ["parts": parts]
            ],
            "generationConfig": [
                "temperature": request.temperature,
                "maxOutputTokens": request.maxTokens
            ]
        ]

        // Add system instruction if present
        if let systemPrompt = request.systemPrompt {
            requestBody["systemInstruction"] = [
                "parts": [["text": systemPrompt]]
            ]
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

        case 400:
            if let errorMessage = extractErrorMessage(from: data) {
                if errorMessage.contains("API_KEY") {
                    throw AIProviderError.invalidAPIKey
                }
                throw AIProviderError.invalidResponse(errorMessage)
            }
            throw AIProviderError.invalidResponse("Bad request")

        case 429:
            throw AIProviderError.rateLimited(retryAfter: 60)

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

        // Check for error in response
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw AIProviderError.invalidResponse(message)
        }

        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first else {
            let jsonStr = String(data: data, encoding: .utf8) ?? "no data"
            throw AIProviderError.invalidResponse("No candidates in response: \(jsonStr.prefix(300))")
        }

        // Check finish reason first
        if let finishReason = firstCandidate["finishReason"] as? String,
           finishReason == "MAX_TOKENS" {
            // Model ran out of tokens (possibly due to thinking)
            throw AIProviderError.invalidResponse("Model ran out of tokens - try increasing maxTokens")
        }

        guard let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw AIProviderError.invalidResponse("No content in response")
        }

        // Find the text part (skip thinking parts if present)
        var text: String?
        for part in parts {
            if let partText = part["text"] as? String {
                text = partText
                break
            }
        }

        guard let extractedText = text else {
            throw AIProviderError.invalidResponse("No text found in response parts")
        }

        // Clean potential markdown artifacts
        let cleanedText = extractedText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse usage
        var usage: AIResponse.TokenUsage?
        if let usageMetadata = json["usageMetadata"] as? [String: Any],
           let promptTokens = usageMetadata["promptTokenCount"] as? Int,
           let candidateTokens = usageMetadata["candidatesTokenCount"] as? Int {
            usage = AIResponse.TokenUsage(inputTokens: promptTokens, outputTokens: candidateTokens)
        }

        // Parse finish reason
        let finishReasonString = firstCandidate["finishReason"] as? String
        let finishReason: AIResponse.FinishReason
        switch finishReasonString {
        case "STOP":
            finishReason = .complete
        case "MAX_TOKENS":
            finishReason = .maxTokens
        case "SAFETY":
            finishReason = .contentFilter
        default:
            finishReason = .complete
        }

        return AIResponse(
            content: cleanedText,
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
