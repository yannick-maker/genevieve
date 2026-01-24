import Foundation
import Combine

/// AI-powered drafting assistant that generates alternative phrasings and suggestions
@MainActor
final class DraftingAssistant: ObservableObject {
    // MARK: - Published State

    @Published private(set) var currentSuggestions: [DraftSuggestionData] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: Error?

    // MARK: - Streaming State

    @Published private(set) var streamingText: String = ""
    @Published private(set) var isStreaming = false
    @Published private(set) var streamingProgress: StreamingProgress = .idle

    // MARK: - Commentary State

    @Published var commentaryModeEnabled: Bool = false {
        didSet {
            if commentaryModeEnabled {
                cancelGeneration()
            } else {
                cancelCommentary()
            }
        }
    }
    @Published private(set) var commentaryText: String = ""
    @Published private(set) var isCommentaryStreaming = false
    @Published private(set) var commentaryProgress: CommentaryProgress = .idle

    enum StreamingProgress: Equatable {
        case idle
        case starting
        case streaming(suggestionIndex: Int, totalExpected: Int)
        case parsing
        case complete
        case error(String)
    }

    enum CommentaryProgress: Equatable {
        case idle
        case starting
        case streaming
        case complete
        case error(String)
    }

    struct PartialSuggestion: Equatable {
        let index: Int
        let text: String
        let isComplete: Bool
    }

    // MARK: - Session Stats

    @Published private(set) var sessionStats = SessionStats()

    struct SessionStats {
        var suggestionsGenerated: Int = 0
        var suggestionsAccepted: Int = 0
        var suggestionsRejected: Int = 0
        var sessionStartTime: Date = Date()

        var acceptanceRate: Double {
            let total = suggestionsAccepted + suggestionsRejected
            guard total > 0 else { return 0 }
            return Double(suggestionsAccepted) / Double(total)
        }

        var sessionDuration: TimeInterval {
            Date().timeIntervalSince(sessionStartTime)
        }

        var formattedDuration: String {
            let minutes = Int(sessionDuration / 60)
            let hours = minutes / 60
            let remainingMinutes = minutes % 60

            if hours > 0 {
                return "\(hours)h \(remainingMinutes)m"
            } else {
                return "\(remainingMinutes)m"
            }
        }

        mutating func reset() {
            suggestionsGenerated = 0
            suggestionsAccepted = 0
            suggestionsRejected = 0
            sessionStartTime = Date()
        }
    }

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
    private var commentaryTask: Task<Void, Never>?

    // MARK: - Configuration

    private let maxSuggestions = 3
    private let minTextLength = 20
    private let suggestionCooldown: TimeInterval = 5.0
    private var lastGenerationTime: Date?

    private let commentaryMinTextLength = 30
    private let commentaryCooldown: TimeInterval = 8.0
    private var lastCommentaryTime: Date?
    private var lastCommentaryKey: String?

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

    // MARK: - Streaming Generation

    /// Generate suggestions with streaming - shows text progressively as it arrives
    func generateSuggestionsStreaming(
        for context: GenerationContext
    ) async {
        // Check cooldown
        if let lastTime = lastGenerationTime,
           Date().timeIntervalSince(lastTime) < suggestionCooldown {
            return
        }

        // Validate text length
        let textToAnalyze = context.selectedText ?? context.text
        guard textToAnalyze.count >= minTextLength else {
            return
        }

        // Cancel any existing generation
        generationTask?.cancel()

        isGenerating = true
        isStreaming = true
        streamingText = ""
        streamingProgress = .starting
        lastError = nil
        currentSuggestions = []

        do {
            let prompt = buildPrompt(for: context)
            let systemPrompt = DraftingPrompts.systemPrompt(
                documentType: context.documentType,
                section: context.section,
                tone: context.tone
            )

            streamingProgress = .streaming(suggestionIndex: 1, totalExpected: maxSuggestions)

            // Use streaming API
            let stream = aiService.generateStream(
                prompt: prompt,
                systemPrompt: systemPrompt,
                task: .draftSuggestion
            )

            // Accumulate streaming text
            for try await chunk in stream {
                streamingText += chunk

                // Try to parse partial suggestions as they come in
                let partialSuggestions = parsePartialSuggestions(
                    from: streamingText,
                    originalText: textToAnalyze
                )

                // Update current suggestions with any complete ones
                if !partialSuggestions.isEmpty {
                    currentSuggestions = partialSuggestions
                    streamingProgress = .streaming(
                        suggestionIndex: min(partialSuggestions.count + 1, maxSuggestions),
                        totalExpected: maxSuggestions
                    )
                }
            }

            // Final parse after stream completes
            streamingProgress = .parsing

            let finalSuggestions = parseSuggestions(
                from: streamingText,
                originalText: textToAnalyze
            )

            currentSuggestions = finalSuggestions
            sessionStats.suggestionsGenerated += finalSuggestions.count
            lastGenerationTime = Date()
            streamingProgress = .complete

        } catch {
            lastError = error
            streamingProgress = .error(error.localizedDescription)
        }

        isGenerating = false
        isStreaming = false
    }

    /// Generate suggestions with streaming in background
    func generateSuggestionsStreamingAsync(for context: GenerationContext) {
        generationTask = Task {
            await generateSuggestionsStreaming(for: context)
        }
    }

    // MARK: - Commentary Generation

    /// Generate stream-of-consciousness commentary about the current work
    func generateCommentaryStreaming(for context: GenerationContext) async {
        guard commentaryModeEnabled else { return }
        guard aiService.hasAnyProvider else { return }

        // Validate text length
        let textToAnalyze = context.selectedText ?? context.text
        guard textToAnalyze.count >= commentaryMinTextLength else { return }

        // Check cooldown / redundant input
        let key = commentaryKey(for: textToAnalyze)
        if let lastTime = lastCommentaryTime,
           Date().timeIntervalSince(lastTime) < commentaryCooldown {
            return
        }

        if key == lastCommentaryKey {
            return
        }

        lastCommentaryKey = key
        lastCommentaryTime = Date()

        isCommentaryStreaming = true
        commentaryProgress = .starting
        lastError = nil

        // Preserve existing commentary and append new stream
        let prefix = commentaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : commentaryText.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
        var buffer = ""
        commentaryText = prefix

        let prompt = buildCommentaryPrompt(for: context)
        let systemPrompt = DraftingPrompts.commentarySystemPrompt(
            documentType: context.documentType,
            section: context.section,
            tone: context.tone
        )

        commentaryProgress = .streaming

        do {
            let stream = aiService.generateStream(
                prompt: prompt,
                systemPrompt: systemPrompt,
                task: .commentary
            )

            for try await chunk in stream {
                guard !Task.isCancelled else { break }
                buffer += chunk
                commentaryText = prefix + buffer
            }

            commentaryProgress = .complete
        } catch {
            lastError = error
            commentaryProgress = .error(error.localizedDescription)
        }

        isCommentaryStreaming = false
    }

    /// Generate commentary with streaming in background
    func generateCommentaryStreamingAsync(for context: GenerationContext) {
        commentaryTask?.cancel()
        commentaryTask = Task {
            await generateCommentaryStreaming(for: context)
        }
    }

    /// Parse partial suggestions from incomplete JSON stream
    private func parsePartialSuggestions(
        from response: String,
        originalText: String
    ) -> [DraftSuggestionData] {
        // Try to find complete suggestion objects in the partial response
        // Look for patterns like {"text": "...", "explanation": "..."}

        var suggestions: [DraftSuggestionData] = []

        // Find all complete suggestion objects using regex-like matching
        var searchStart = response.startIndex

        while let openBrace = response[searchStart...].firstIndex(of: "{") {
            // Look for matching close brace
            var braceCount = 1
            var current = response.index(after: openBrace)

            while current < response.endIndex && braceCount > 0 {
                if response[current] == "{" {
                    braceCount += 1
                } else if response[current] == "}" {
                    braceCount -= 1
                }
                current = response.index(after: current)
            }

            // If we found a complete object
            if braceCount == 0 {
                let objectString = String(response[openBrace..<current])

                // Try to parse this object
                if let data = objectString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["text"] as? String,
                   let explanation = json["explanation"] as? String {

                    let improvements = (json["improvements"] as? [String] ?? []).compactMap {
                        DraftSuggestionData.ImprovementArea(rawValue: $0)
                    }

                    let confidence = json["confidence"] as? Double ?? 0.5

                    let suggestion = DraftSuggestionData(
                        id: UUID(),
                        originalText: originalText,
                        suggestedText: text,
                        explanation: explanation,
                        improvementAreas: improvements,
                        confidence: confidence,
                        generatedAt: Date()
                    )

                    suggestions.append(suggestion)
                }

                searchStart = current
            } else {
                // Incomplete object, stop searching
                break
            }
        }

        return suggestions
    }

    /// Clear current suggestions
    func clearSuggestions() {
        currentSuggestions = []
    }

    /// Clear commentary transcript
    func clearCommentary() {
        commentaryText = ""
        commentaryProgress = .idle
    }

    /// Cancel any ongoing generation
    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        isStreaming = false
        streamingProgress = .idle
    }

    /// Cancel any ongoing commentary generation
    func cancelCommentary() {
        commentaryTask?.cancel()
        commentaryTask = nil
        isCommentaryStreaming = false
        commentaryProgress = .idle
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

    private func buildCommentaryPrompt(for context: GenerationContext) -> String {
        let textToAnalyze = context.selectedText ?? context.text
        let trimmedText = String(textToAnalyze.prefix(800))
        let prior = commentaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let priorSnippet = prior.isEmpty ? "None" : String(prior.suffix(400))

        return """
        Provide a short, flowing stream-of-consciousness commentary about what the writer is doing right now.
        Keep it 2–4 sentences. Use present tense. Do NOT suggest edits or rewrite the text.
        Avoid lists, bullet points, or headings. Do not quote the text verbatim.

        Document type: \(context.documentType.displayName)
        Section: \(context.section.displayName)
        Tone: \(context.tone.displayName)

        Draft excerpt:
        ---
        \(trimmedText)
        ---

        Prior commentary (for continuity, if any):
        \(priorSnippet)
        """
    }

    private func commentaryKey(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(200))
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
        sessionStats.suggestionsAccepted += 1
        return suggestion.suggestedText
    }

    /// Reject a suggestion
    func rejectSuggestion(_ suggestion: DraftSuggestionData) {
        currentSuggestions.removeAll { $0.id == suggestion.id }
        sessionStats.suggestionsRejected += 1
    }

    /// Reset session stats
    func resetSessionStats() {
        sessionStats.reset()
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

    static func commentarySystemPrompt(
        documentType: ContextAnalyzer.DocumentType,
        section: ContextAnalyzer.DocumentSection,
        tone: ContextAnalyzer.WritingTone,
        matterContext: String? = nil,
        userProfile: String? = nil,
        stuckState: String? = nil
    ) -> String {
        var prompt = """
        You are a legal writing assistant providing real-time feedback on what the user is working on.

        ## Your Task
        Observe the visible content and provide useful commentary:
        - Identify what they're working on (document type, section, purpose)
        - Point out specific issues, weaknesses, or opportunities for improvement
        - Offer concrete suggestions when you see something that could be better
        - Reference relevant legal writing principles when applicable

        ## Style
        - Be direct and specific. No fluff, no roleplay, no persona.
        - Focus on actionable feedback
        - When you have a specific text suggestion, format it as: [SUGGESTION: your suggested text]
        - Don't quote large chunks of their text back at them
        - Keep it concise but substantive

        ## Current Context
        - Document type: \(documentType.displayName)
        - Section: \(section.displayName)
        - Target tone: \(tone.displayName)
        """

        if let matter = matterContext {
            prompt += "\n\n## Matter Context\n\(matter)"
        }

        if let profile = userProfile {
            prompt += "\n\n## Writer Patterns\n\(profile)"
        }

        if let stuck = stuckState {
            prompt += "\n\n## Current State\nThe writer appears to be \(stuck). Address this directly with specific guidance."
        }

        prompt += """


        ## Legal Writing Principles (reference when relevant)
        - Strong topic sentences
        - Rule synthesis before application
        - Concrete facts over abstract assertions
        - Active voice for clarity
        - One idea per paragraph
        - Address counterarguments preemptively
        - Precision in contractual language
        """

        return prompt
    }

    /// Brief commentary prompt
    static func commentarySystemPromptBrief(
        documentType: ContextAnalyzer.DocumentType,
        section: ContextAnalyzer.DocumentSection,
        tone: ContextAnalyzer.WritingTone
    ) -> String {
        """
        Provide a brief observation about the visible content (2-4 sentences).
        Be direct and specific. No roleplay or persona.

        Context: \(documentType.displayName) / \(section.displayName) / \(tone.displayName)
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
