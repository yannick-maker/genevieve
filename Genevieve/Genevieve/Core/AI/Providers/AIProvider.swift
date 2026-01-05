import Foundation

// MARK: - Provider Types

enum AIProviderType: String, Codable, CaseIterable, Identifiable {
    case claude = "Claude"
    case gemini = "Gemini"
    case openAI = "OpenAI"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var availableModels: [AIModel] {
        switch self {
        case .claude:
            return [.claude4Sonnet, .claude4Opus]
        case .gemini:
            return [.gemini3Pro, .gemini3Flash]
        case .openAI:
            return [.gpt52, .gpt52Pro]
        }
    }
}

// MARK: - Model Types

enum AIModel: String, Codable, CaseIterable, Identifiable {
    // Claude models
    case claude4Sonnet = "claude-sonnet-4-20250514"
    case claude4Opus = "claude-opus-4-20250514"

    // Gemini models
    case gemini3Pro = "gemini-2.5-pro"
    case gemini3Flash = "gemini-2.5-flash"

    // OpenAI models
    case gpt52 = "gpt-5.2"
    case gpt52Pro = "gpt-5.2-pro"

    var id: String { rawValue }

    var provider: AIProviderType {
        switch self {
        case .claude4Sonnet, .claude4Opus:
            return .claude
        case .gemini3Pro, .gemini3Flash:
            return .gemini
        case .gpt52, .gpt52Pro:
            return .openAI
        }
    }

    var displayName: String {
        switch self {
        case .claude4Sonnet: return "Claude 4 Sonnet"
        case .claude4Opus: return "Claude 4 Opus"
        case .gemini3Pro: return "Gemini 3 Pro"
        case .gemini3Flash: return "Gemini 3 Flash"
        case .gpt52: return "GPT-5.2"
        case .gpt52Pro: return "GPT-5.2 Pro"
        }
    }

    var qualityTier: QualityTier {
        switch self {
        case .claude4Opus, .gpt52Pro, .gemini3Pro:
            return .premium
        case .claude4Sonnet, .gpt52, .gemini3Flash:
            return .standard
        }
    }

    var supportsVision: Bool {
        switch self {
        case .claude4Opus, .claude4Sonnet, .gemini3Pro, .gemini3Flash, .gpt52Pro:
            return true
        case .gpt52:
            return false
        }
    }
}

enum QualityTier: Int, Comparable, Codable {
    case standard = 1
    case premium = 2

    static func < (lhs: QualityTier, rhs: QualityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Request/Response Types

struct AIRequest {
    let prompt: String
    let systemPrompt: String?
    let images: [Data]?
    let temperature: Double
    let maxTokens: Int
    let responseFormat: ResponseFormat?

    enum ResponseFormat {
        case json(schema: String?)
        case text
    }

    init(
        prompt: String,
        systemPrompt: String? = nil,
        images: [Data]? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 2000,
        responseFormat: ResponseFormat? = nil
    ) {
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.images = images
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.responseFormat = responseFormat
    }
}

struct AIResponse {
    let content: String
    let model: AIModel
    let usage: TokenUsage?
    let finishReason: FinishReason

    struct TokenUsage {
        let inputTokens: Int
        let outputTokens: Int

        var totalTokens: Int { inputTokens + outputTokens }
    }

    enum FinishReason {
        case complete
        case maxTokens
        case contentFilter
        case error(String)
    }
}

// MARK: - Provider Errors

enum AIProviderError: LocalizedError {
    case notConfigured
    case invalidAPIKey
    case rateLimited(retryAfter: TimeInterval?)
    case networkError(Error)
    case invalidResponse(String)
    case contentBlocked
    case modelUnavailable(AIModel)
    case quotaExceeded
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI provider not configured. Please add your API key in Settings."
        case .invalidAPIKey:
            return "Invalid API key. Please check your API key in Settings."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Please try again in \(Int(seconds)) seconds."
            }
            return "Rate limited. Please try again later."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let detail):
            return "Invalid response from AI: \(detail)"
        case .contentBlocked:
            return "Content was blocked by safety filters."
        case .modelUnavailable(let model):
            return "\(model.displayName) is currently unavailable."
        case .quotaExceeded:
            return "API quota exceeded. Please check your billing."
        case .timeout:
            return "Request timed out. Please try again."
        }
    }
}

// MARK: - Provider Protocol

protocol AIProvider: AnyObject, Sendable {
    var providerType: AIProviderType { get }
    var isConfigured: Bool { get }
    var availableModels: [AIModel] { get }

    func configure(apiKey: String) async throws
    func generate(request: AIRequest, model: AIModel) async throws -> AIResponse
    func validateAPIKey(_ key: String) async throws -> Bool
}

// MARK: - Streaming Provider Protocol

protocol StreamingAIProvider: AIProvider {
    func generateStream(
        request: AIRequest,
        model: AIModel
    ) -> AsyncThrowingStream<String, Error>
}

// MARK: - Task Categories for Routing

enum AITaskCategory {
    case draftSuggestion        // Generate alternative phrasings
    case argumentRefinement     // Improve/expand arguments
    case contextAnalysis        // Analyze document context (vision)
    case stuckAssistance        // Help when user appears stuck
    case quickEdit              // Simple edits, formatting
    case documentClassification // Identify document type

    var recommendedTier: QualityTier {
        switch self {
        case .draftSuggestion, .argumentRefinement, .stuckAssistance:
            return .premium
        case .contextAnalysis:
            return .premium
        case .quickEdit, .documentClassification:
            return .standard
        }
    }

    var requiresVision: Bool {
        switch self {
        case .contextAnalysis:
            return true
        default:
            return false
        }
    }

    var defaultTemperature: Double {
        switch self {
        case .draftSuggestion:
            return 0.8  // More creative
        case .argumentRefinement:
            return 0.7
        case .contextAnalysis, .documentClassification:
            return 0.3  // More deterministic
        case .stuckAssistance:
            return 0.7
        case .quickEdit:
            return 0.4
        }
    }

    var defaultMaxTokens: Int {
        switch self {
        case .draftSuggestion:
            return 1000
        case .argumentRefinement:
            return 2000
        case .contextAnalysis:
            return 500
        case .stuckAssistance:
            return 1500
        case .quickEdit:
            return 500
        case .documentClassification:
            return 200
        }
    }
}
