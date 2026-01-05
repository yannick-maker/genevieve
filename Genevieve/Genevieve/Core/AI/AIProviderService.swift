import Foundation
import Combine

/// Unified AI service that manages multiple providers and routes requests automatically
@MainActor
final class AIProviderService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var isProcessing = false
    @Published private(set) var configuredProviders: Set<AIProviderType> = []
    @Published var defaultModel: AIModel = .claude4Opus

    // MARK: - Providers

    let claudeProvider: ClaudeProvider
    let geminiProvider: GeminiProvider
    let openAIProvider: OpenAIProvider

    private var providers: [AIProviderType: any AIProvider] {
        [
            .claude: claudeProvider,
            .gemini: geminiProvider,
            .openAI: openAIProvider
        ]
    }

    // MARK: - Task-specific Model Overrides

    private var taskModelOverrides: [AITaskCategory: AIModel] = [:]

    // MARK: - Initialization

    init(
        claudeProvider: ClaudeProvider? = nil,
        geminiProvider: GeminiProvider? = nil,
        openAIProvider: OpenAIProvider? = nil
    ) {
        self.claudeProvider = claudeProvider ?? ClaudeProvider()
        self.geminiProvider = geminiProvider ?? GeminiProvider()
        self.openAIProvider = openAIProvider ?? OpenAIProvider()
    }

    /// Load API keys and update configuration state
    func initialize() async {
        await claudeProvider.loadAPIKey()
        await geminiProvider.loadAPIKey()
        await openAIProvider.loadAPIKey()

        updateConfiguredProviders()
        loadPreferences()
    }

    private func updateConfiguredProviders() {
        var configured: Set<AIProviderType> = []

        if claudeProvider.isConfigured { configured.insert(.claude) }
        if geminiProvider.isConfigured { configured.insert(.gemini) }
        if openAIProvider.isConfigured { configured.insert(.openAI) }

        configuredProviders = configured
    }

    private func loadPreferences() {
        if let modelRaw = UserDefaults.standard.string(forKey: "defaultAIModel"),
           let model = AIModel(rawValue: modelRaw) {
            defaultModel = model
        }
    }

    // MARK: - Public API

    /// Generate response using automatic model routing based on task type
    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        images: [Data]? = nil,
        task: AITaskCategory
    ) async throws -> AIResponse {
        let model = selectModel(for: task)
        return try await generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            images: images,
            model: model,
            temperature: task.defaultTemperature,
            maxTokens: task.defaultMaxTokens
        )
    }

    /// Generate response with explicit model selection
    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        images: [Data]? = nil,
        model: AIModel,
        temperature: Double = 0.7,
        maxTokens: Int = 2000
    ) async throws -> AIResponse {
        guard let provider = providers[model.provider] else {
            throw AIProviderError.modelUnavailable(model)
        }

        guard provider.isConfigured else {
            throw AIProviderError.notConfigured
        }

        isProcessing = true
        defer { isProcessing = false }

        let request = AIRequest(
            prompt: prompt,
            systemPrompt: systemPrompt,
            images: images,
            temperature: temperature,
            maxTokens: maxTokens
        )

        return try await provider.generate(request: request, model: model)
    }

    /// Generate with fallback - tries primary model, falls back to alternatives on failure
    func generateWithFallback(
        prompt: String,
        systemPrompt: String? = nil,
        images: [Data]? = nil,
        task: AITaskCategory
    ) async throws -> AIResponse {
        let primaryModel = selectModel(for: task)
        let fallbackModels = getFallbackModels(for: task, excluding: primaryModel)

        // Try primary first
        do {
            return try await generate(
                prompt: prompt,
                systemPrompt: systemPrompt,
                images: images,
                model: primaryModel,
                temperature: task.defaultTemperature,
                maxTokens: task.defaultMaxTokens
            )
        } catch {
            // Try fallbacks
            for fallbackModel in fallbackModels {
                do {
                    return try await generate(
                        prompt: prompt,
                        systemPrompt: systemPrompt,
                        images: images,
                        model: fallbackModel,
                        temperature: task.defaultTemperature,
                        maxTokens: task.defaultMaxTokens
                    )
                } catch {
                    continue
                }
            }

            // All failed, throw original error
            throw error
        }
    }

    // MARK: - Configuration

    /// Configure a provider with an API key
    func configureProvider(_ type: AIProviderType, apiKey: String) async throws {
        switch type {
        case .claude:
            try await claudeProvider.configure(apiKey: apiKey)
        case .gemini:
            try await geminiProvider.configure(apiKey: apiKey)
        case .openAI:
            try await openAIProvider.configure(apiKey: apiKey)
        }
        updateConfiguredProviders()
    }

    /// Validate an API key without saving
    func validateAPIKey(_ key: String, for type: AIProviderType) async throws -> Bool {
        switch type {
        case .claude:
            return try await claudeProvider.validateAPIKey(key)
        case .gemini:
            return try await geminiProvider.validateAPIKey(key)
        case .openAI:
            return try await openAIProvider.validateAPIKey(key)
        }
    }

    /// Set model override for a specific task type
    func setModelOverride(_ model: AIModel?, for task: AITaskCategory) {
        if let model = model {
            taskModelOverrides[task] = model
        } else {
            taskModelOverrides.removeValue(forKey: task)
        }
    }

    /// Set the default model
    func setDefaultModel(_ model: AIModel) {
        defaultModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "defaultAIModel")
    }

    // MARK: - Model Selection

    private func selectModel(for task: AITaskCategory) -> AIModel {
        // Check for explicit override
        if let override = taskModelOverrides[task] {
            if isModelAvailable(override) {
                return override
            }
        }

        // Use default if it satisfies task requirements
        if modelSatisfiesTask(defaultModel, task: task) && isModelAvailable(defaultModel) {
            return defaultModel
        }

        // Find best available model for task
        let candidates = AIModel.allCases
            .filter { modelSatisfiesTask($0, task: task) }
            .filter { isModelAvailable($0) }
            .sorted { $0.qualityTier > $1.qualityTier }

        return candidates.first ?? defaultModel
    }

    private func getFallbackModels(for task: AITaskCategory, excluding: AIModel) -> [AIModel] {
        AIModel.allCases
            .filter { $0 != excluding }
            .filter { modelSatisfiesTask($0, task: task) }
            .filter { isModelAvailable($0) }
            .sorted { $0.qualityTier > $1.qualityTier }
    }

    private func modelSatisfiesTask(_ model: AIModel, task: AITaskCategory) -> Bool {
        // Check vision requirement
        if task.requiresVision && !model.supportsVision {
            return false
        }

        // Check quality tier preference
        if task.recommendedTier == .premium && model.qualityTier < .premium {
            // Still allow standard if no premium available
            let premiumAvailable = AIModel.allCases
                .filter { $0.qualityTier >= .premium }
                .contains { isModelAvailable($0) }
            if premiumAvailable {
                return model.qualityTier >= .premium
            }
        }

        return true
    }

    private func isModelAvailable(_ model: AIModel) -> Bool {
        configuredProviders.contains(model.provider)
    }

    // MARK: - Status

    var hasAnyProvider: Bool {
        !configuredProviders.isEmpty
    }

    var availableModels: [AIModel] {
        AIModel.allCases.filter { isModelAvailable($0) }
    }
}
