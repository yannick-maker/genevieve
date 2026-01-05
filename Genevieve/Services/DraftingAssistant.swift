import Foundation
import Combine

/// AI-powered drafting assistant that generates alternative phrasings and suggestions
@MainActor
final class DraftingAssistant: ObservableObject {
    // MARK: - Published State

    @Published private(set) var currentSuggestions: [DraftSuggestionData] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: Error?

    // MARK: - Types

    struct DraftSuggestionData: Identifiable, Equatable {
        let id: UUID
        let originalText: String
        let suggestedText: String
        let explanation: String
        let improvementAreas: [ImprovementArea]
        let confidence: Double
        let generatedAt: Date

        enum ImprovementArea: String, CaseIterable {
            case clarity = "Clearer"
            case precision = "More Precise"
            case persuasiveness = "More Persuasive"
            case conciseness = "More Concise"
            case formality = "More Formal"
            case flow = "Better Flow"
            case legalStandard = "Legal Standard"
        }

        var confidenceLevel: ConfidenceLevel {
            switch confidence {
            case 0.8...1.0: return .high
            case 0.5..<0.8: return .medium
            default: return .low
            }
        }

        enum ConfidenceLevel: String {
            case high
            case medium
            case low
        }
    }

    struct GenerationContext {
        let text: String
        let selectedText: String?
        let documentType: ContextAnalyzer.DocumentType
        let section: ContextAnalyzer.DocumentSection
        let tone: ContextAnalyzer.WritingTone
        let triggerReason: TriggerReason

        enum TriggerReason {
            case proactive
            case userRequest
            case stuckDetected
            case editingLoop
        }
    }

    // MARK: - Dependencies

    private let aiService: AIProviderService
    private var generationTask: Task<Void, Never>?

    // MARK: - Configuration

    private let maxSuggestions = 3
    private let minTextLength = 20
    private let suggestionCooldown: TimeInterval = 5.0
    private var lastGenerationTime: Date?

    // MARK: - Initialization

    init(aiService: AIProviderService) {
        self.aiService = aiService
    }

    // MARK: - Suggestion Generation

    /// Generate draft suggestions for the given context
    func generateSuggestions(for context: GenerationContext) async -> [DraftSuggestionData] {
        // Check cooldown
        if let lastTime = lastGenerationTime,
           Date().timeIntervalSince(lastTime) < suggestionCooldown {
            return currentSuggestions
        }

        // Validate text length
        let textToAnalyze = context.selectedText ?? context.text
        guard textToAnalyze.count >= minTextLength else {
            return []
        }

        // Cancel any existing generation
        generationTask?.cancel()

        isGenerating = true
        lastError = nil

        do {
            let prompt = buildPrompt(for: context)
            let systemPrompt = DraftingPrompts.systemPrompt(
                documentType: context.documentType,
                section: context.section,
                tone: context.tone
            )

            let response = try await aiService.generate(
                prompt: prompt,
                systemPrompt: systemPrompt,
                images: nil,
                task: .draftSuggestion
            )

            let suggestions = parseSuggestions(
                from: response.content,
                originalText: textToAnalyze
            )

            currentSuggestions = suggestions
            lastGenerationTime = Date()
            isGenerating = false

            return suggestions
        } catch {
            lastError = error
            isGenerating = false
            return []
        }
    }

    /// Generate suggestions in the background
    func generateSuggestionsAsync(for context: GenerationContext) {
        generationTask = Task {
            _ = await generateSuggestions(for: context)
        }
    }

    /// Clear current suggestions
    func clearSuggestions() {
        currentSuggestions = []
    }

    // MARK: - Prompt Building

    private func buildPrompt(for context: GenerationContext) -> String {
        let textToAnalyze = context.selectedText ?? context.text

        return """
        Analyze this legal text and provide \(maxSuggestions) alternative phrasings:

        Original text:
        ---
        \(textToAnalyze)
        ---

        Document type: \(context.documentType.displayName)
        Section: \(context.section.displayName)
        Desired tone: \(context.tone.displayName)

        For each suggestion, provide:
        1. The improved text
        2. A brief explanation of why this is stronger (1-2 sentences)
        3. What aspects were improved (clarity, precision, persuasiveness, conciseness, formality, flow, legal_standard)
        4. Confidence score (0.0-1.0)

        Respond in JSON format:
        {
            "suggestions": [
                {
                    "text": "improved text here",
                    "explanation": "This is stronger because...",
                    "improvements": ["clarity", "precision"],
                    "confidence": 0.85
                }
            ]
        }

        Focus on legal writing best practices. Be specific about improvements.
        """
    }

    // MARK: - Response Parsing

    private func parseSuggestions(
        from response: String,
        originalText: String
    ) -> [DraftSuggestionData] {
        // Try to extract JSON from response
        guard let jsonData = extractJSON(from: response),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let suggestionsArray = json["suggestions"] as? [[String: Any]] else {
            return []
        }

        return suggestionsArray.compactMap { dict -> DraftSuggestionData? in
            guard let text = dict["text"] as? String,
                  let explanation = dict["explanation"] as? String else {
                return nil
            }

            let improvements = (dict["improvements"] as? [String] ?? []).compactMap {
                DraftSuggestionData.ImprovementArea(rawValue: $0)
            }

            let confidence = dict["confidence"] as? Double ?? 0.5

            return DraftSuggestionData(
                id: UUID(),
                originalText: originalText,
                suggestedText: text,
                explanation: explanation,
                improvementAreas: improvements,
                confidence: confidence,
                generatedAt: Date()
            )
        }
    }

    private func extractJSON(from text: String) -> Data? {
        // Try to find JSON in the response
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            let jsonString = String(text[start...end])
            return jsonString.data(using: .utf8)
        }
        return text.data(using: .utf8)
    }

    // MARK: - Suggestion Application

    /// Accept a suggestion and return the text to insert
    func acceptSuggestion(_ suggestion: DraftSuggestionData) -> String {
        // Remove from current suggestions
        currentSuggestions.removeAll { $0.id == suggestion.id }
        return suggestion.suggestedText
    }

    /// Reject a suggestion
    func rejectSuggestion(_ suggestion: DraftSuggestionData) {
        currentSuggestions.removeAll { $0.id == suggestion.id }
    }
}

// MARK: - Drafting Prompts

enum DraftingPrompts {
    static func systemPrompt(
        documentType: ContextAnalyzer.DocumentType,
        section: ContextAnalyzer.DocumentSection,
        tone: ContextAnalyzer.WritingTone
    ) -> String {
        """
        You are an expert legal writing assistant. Your role is to improve legal drafts by:

        1. Enhancing clarity and precision
        2. Strengthening persuasive elements
        3. Ensuring proper legal terminology
        4. Improving sentence structure and flow
        5. Maintaining appropriate formality

        Current context:
        - Document type: \(documentType.displayName)
        - Section: \(section.displayName)
        - Tone: \(tone.displayName)

        Guidelines:
        - Preserve the original meaning and intent
        - Use active voice where appropriate
        - Be specific rather than vague
        - Cite legal standards when relevant
        - Keep suggestions concise but impactful

        For briefs and motions, prioritize persuasive language.
        For contracts, prioritize precision and clarity.
        For emails, balance professionalism with readability.

        Always explain WHY a suggestion is an improvement - this helps the attorney learn.
        """
    }

    static let briefImprovements = """
    For briefs, focus on:
    - Strong topic sentences
    - Clear legal standards
    - Specific factual support
    - Persuasive conclusions
    - Proper citation format
    """

    static let contractImprovements = """
    For contracts, focus on:
    - Precise definitions
    - Clear obligations
    - Unambiguous conditions
    - Appropriate remedies
    - Risk allocation
    """

    static let memoImprovements = """
    For memos, focus on:
    - Clear issue statements
    - Balanced analysis
    - Practical recommendations
    - Supporting authority
    - Executive summaries
    """
}

// MARK: - Quick Suggestions

extension DraftingAssistant {
    /// Generate a quick single suggestion (faster, lower quality)
    func generateQuickSuggestion(for text: String) async -> DraftSuggestionData? {
        guard text.count >= minTextLength else { return nil }

        do {
            let prompt = """
            Improve this legal text with one better alternative:

            "\(text)"

            Respond in JSON: {"text": "improved", "explanation": "why", "confidence": 0.8}
            """

            let response = try await aiService.generate(
                prompt: prompt,
                systemPrompt: "You are a legal writing expert. Improve the text concisely.",
                images: nil,
                task: .quickEdit
            )

            if let jsonData = extractJSON(from: response.content),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let improvedText = json["text"] as? String,
               let explanation = json["explanation"] as? String {

                return DraftSuggestionData(
                    id: UUID(),
                    originalText: text,
                    suggestedText: improvedText,
                    explanation: explanation,
                    improvementAreas: [],
                    confidence: json["confidence"] as? Double ?? 0.5,
                    generatedAt: Date()
                )
            }
        } catch {
            lastError = error
        }

        return nil
    }
}
