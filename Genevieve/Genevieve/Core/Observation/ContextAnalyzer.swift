import Foundation
import AppKit

/// AI-powered context analyzer for understanding document type and writing context
@MainActor
final class ContextAnalyzer: ObservableObject {
    // MARK: - Published State

    @Published private(set) var currentAnalysis: DocumentAnalysis?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var lastAnalysisTime: Date?

    // MARK: - Types

    struct DocumentAnalysis: Equatable {
        let documentType: DocumentType
        let section: DocumentSection?
        let tone: WritingTone
        let confidence: Double
        let extractedContext: ExtractedContext
        let timestamp: Date

        /// Check if analysis is still fresh
        var isFresh: Bool {
            Date().timeIntervalSince(timestamp) < 30 // 30 seconds
        }
    }

    struct ExtractedContext: Equatable {
        let mainTopic: String?
        let keyEntities: [String]
        let legalConcepts: [String]
        let citations: [String]
        let argumentStructure: ArgumentStructure?
    }

    struct ArgumentStructure: Equatable {
        let premise: String?
        let reasoning: String?
        let conclusion: String?
        let counterarguments: [String]
    }

    enum DocumentType: String, CaseIterable, Codable {
        case brief
        case motion
        case contract
        case memo
        case email
        case letter
        case pleading
        case discovery
        case research
        case notes
        case code
        case unknown

        var displayName: String {
            switch self {
            case .brief: return "Brief"
            case .motion: return "Motion"
            case .contract: return "Contract"
            case .memo: return "Memo"
            case .email: return "Email"
            case .letter: return "Letter"
            case .pleading: return "Pleading"
            case .discovery: return "Discovery"
            case .research: return "Research"
            case .notes: return "Notes"
            case .code: return "Code"
            case .unknown: return "Document"
            }
        }

        var suggestionsStyle: SuggestionStyle {
            switch self {
            case .brief, .motion, .pleading:
                return .formal
            case .contract:
                return .precise
            case .memo:
                return .professional
            case .email, .letter:
                return .conversational
            case .discovery:
                return .technical
            case .research, .notes:
                return .analytical
            case .code:
                return .technical
            case .unknown:
                return .neutral
            }
        }
    }

    enum DocumentSection: String, Codable {
        case introduction
        case facts
        case argument
        case analysis
        case conclusion
        case signature
        case header
        case definitions
        case terms
        case unknown

        var displayName: String {
            switch self {
            case .introduction: return "Introduction"
            case .facts: return "Statement of Facts"
            case .argument: return "Argument"
            case .analysis: return "Analysis"
            case .conclusion: return "Conclusion"
            case .signature: return "Signature Block"
            case .header: return "Header"
            case .definitions: return "Definitions"
            case .terms: return "Terms & Conditions"
            case .unknown: return "Body"
            }
        }
    }

    enum WritingTone: String, Codable {
        case formal
        case persuasive
        case analytical
        case conversational
        case neutral

        var displayName: String {
            rawValue.capitalized
        }
    }

    enum SuggestionStyle {
        case formal
        case precise
        case professional
        case conversational
        case technical
        case analytical
        case neutral
    }

    // MARK: - Dependencies

    private let aiService: AIProviderService
    private var analysisCache: [String: DocumentAnalysis] = [:]

    // MARK: - Configuration

    private let minTextLength = 50
    private let analysisDebounceInterval: TimeInterval = 2.0
    private var pendingAnalysisTask: Task<Void, Never>?

    // MARK: - Initialization

    init(aiService: AIProviderService) {
        self.aiService = aiService
    }

    // MARK: - Analysis

    /// Analyze the current writing context
    func analyze(context: FocusedElementDetector.WritingContext) async -> DocumentAnalysis? {
        // Check cache first
        let cacheKey = generateCacheKey(for: context)
        if let cached = analysisCache[cacheKey], cached.isFresh {
            return cached
        }

        // Get text for analysis
        guard let text = context.selectedText ?? context.surroundingText,
              text.count >= minTextLength else {
            return inferBasicAnalysis(from: context)
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let analysis = try await performAIAnalysis(text: text, context: context)
            analysisCache[cacheKey] = analysis
            currentAnalysis = analysis
            lastAnalysisTime = Date()
            return analysis
        } catch {
            // Fallback to heuristic analysis
            return inferBasicAnalysis(from: context)
        }
    }

    /// Debounced analysis - call this from continuous updates
    func analyzeDebounced(context: FocusedElementDetector.WritingContext) {
        pendingAnalysisTask?.cancel()

        pendingAnalysisTask = Task {
            try? await Task.sleep(for: .seconds(analysisDebounceInterval))

            guard !Task.isCancelled else { return }

            _ = await analyze(context: context)
        }
    }

    // MARK: - AI Analysis

    private func performAIAnalysis(
        text: String,
        context: FocusedElementDetector.WritingContext
    ) async throws -> DocumentAnalysis {
        let prompt = buildAnalysisPrompt(text: text, context: context)

        let response = try await aiService.generate(
            prompt: prompt,
            systemPrompt: ContextAnalyzerPrompts.systemPrompt,
            images: nil,
            task: .contextAnalysis
        )

        return parseAnalysisResponse(response.content, context: context)
    }

    private func buildAnalysisPrompt(
        text: String,
        context: FocusedElementDetector.WritingContext
    ) -> String {
        """
        Analyze this legal writing context:

        Application: \(context.appName)
        Window: \(context.windowTitle ?? "Unknown")
        Document Type Hint: \(context.documentType?.displayName ?? "Unknown")

        Text to analyze:
        ---
        \(text.prefix(2000))
        ---

        Provide analysis in JSON format with:
        - documentType: one of [brief, motion, contract, memo, email, letter, pleading, discovery, research, notes, code, unknown]
        - section: one of [introduction, facts, argument, analysis, conclusion, signature, header, definitions, terms, unknown]
        - tone: one of [formal, persuasive, analytical, conversational, neutral]
        - confidence: 0.0-1.0
        - mainTopic: brief description
        - keyEntities: array of important names/parties
        - legalConcepts: array of legal concepts mentioned
        - citations: array of any case citations found
        - argumentStructure: { premise, reasoning, conclusion, counterarguments } if applicable
        """
    }

    private func parseAnalysisResponse(
        _ response: String,
        context: FocusedElementDetector.WritingContext
    ) -> DocumentAnalysis {
        // Try to parse JSON response
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return DocumentAnalysis(
                documentType: parseDocumentType(json["documentType"] as? String),
                section: parseSection(json["section"] as? String),
                tone: parseTone(json["tone"] as? String),
                confidence: json["confidence"] as? Double ?? 0.5,
                extractedContext: ExtractedContext(
                    mainTopic: json["mainTopic"] as? String,
                    keyEntities: json["keyEntities"] as? [String] ?? [],
                    legalConcepts: json["legalConcepts"] as? [String] ?? [],
                    citations: json["citations"] as? [String] ?? [],
                    argumentStructure: parseArgumentStructure(json["argumentStructure"] as? [String: Any])
                ),
                timestamp: Date()
            )
        }

        // Fallback to basic analysis if JSON parsing fails
        return inferBasicAnalysis(from: context) ?? DocumentAnalysis(
            documentType: .unknown,
            section: .unknown,
            tone: .neutral,
            confidence: 0.3,
            extractedContext: ExtractedContext(
                mainTopic: nil,
                keyEntities: [],
                legalConcepts: [],
                citations: [],
                argumentStructure: nil
            ),
            timestamp: Date()
        )
    }

    // MARK: - Heuristic Analysis

    private func inferBasicAnalysis(from context: FocusedElementDetector.WritingContext) -> DocumentAnalysis? {
        let documentType = inferDocumentType(from: context)
        let section = inferSection(from: context)
        let tone = inferTone(from: documentType)

        return DocumentAnalysis(
            documentType: documentType,
            section: section,
            tone: tone,
            confidence: 0.4, // Lower confidence for heuristic analysis
            extractedContext: ExtractedContext(
                mainTopic: nil,
                keyEntities: [],
                legalConcepts: [],
                citations: extractCitations(from: context.surroundingText),
                argumentStructure: nil
            ),
            timestamp: Date()
        )
    }

    private func inferDocumentType(from context: FocusedElementDetector.WritingContext) -> DocumentType {
        let title = context.windowTitle?.lowercased() ?? ""
        let text = (context.surroundingText ?? "").lowercased()

        // Check window title patterns
        if title.contains("brief") { return .brief }
        if title.contains("motion") { return .motion }
        if title.contains("contract") || title.contains("agreement") { return .contract }
        if title.contains("memo") { return .memo }
        if title.contains("mail") || title.contains("gmail") || title.contains("outlook") { return .email }
        if title.contains("letter") { return .letter }
        if title.contains("complaint") || title.contains("petition") { return .pleading }
        if title.contains("discovery") || title.contains("interrogator") { return .discovery }

        // Check text content patterns
        if text.contains("respectfully submitted") || text.contains("in the matter of") { return .brief }
        if text.contains("hereby moves") || text.contains("motion to") { return .motion }
        if text.contains("whereas") && text.contains("agreement") { return .contract }
        if text.contains("dear ") && text.contains("sincerely") { return .letter }
        if text.contains("plaintiff") || text.contains("defendant") { return .pleading }

        // Check app-based hints
        if context.appBundleID.contains("mail") || context.appBundleID.contains("outlook") {
            return .email
        }

        return .unknown
    }

    private func inferSection(from context: FocusedElementDetector.WritingContext) -> DocumentSection {
        let text = (context.surroundingText ?? "").lowercased()

        if text.contains("introduction") || text.contains("preliminary statement") {
            return .introduction
        }
        if text.contains("statement of facts") || text.contains("factual background") {
            return .facts
        }
        if text.contains("argument") || text.contains("legal analysis") {
            return .argument
        }
        if text.contains("conclusion") || text.contains("wherefore") {
            return .conclusion
        }
        if text.contains("respectfully submitted") || text.contains("dated:") {
            return .signature
        }
        if text.contains("definitions") || text.contains("\"means\"") {
            return .definitions
        }

        return .unknown
    }

    private func inferTone(from documentType: DocumentType) -> WritingTone {
        switch documentType {
        case .brief, .motion, .pleading:
            return .persuasive
        case .contract, .discovery:
            return .formal
        case .memo, .research:
            return .analytical
        case .email, .letter:
            return .conversational
        default:
            return .neutral
        }
    }

    private func extractCitations(from text: String?) -> [String] {
        guard let text = text else { return [] }

        var citations: [String] = []

        // Case citation pattern: Name v. Name, Volume Reporter Page (Year)
        let casePattern = #"[A-Z][a-z]+ v\. [A-Z][a-z]+,? \d+ [A-Z]\.[A-Za-z\.]+ \d+"#
        if let regex = try? NSRegularExpression(pattern: casePattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    citations.append(String(text[range]))
                }
            }
        }

        // Statute citation pattern
        let statutePattern = #"\d+ U\.S\.C\. § \d+"#
        if let regex = try? NSRegularExpression(pattern: statutePattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    citations.append(String(text[range]))
                }
            }
        }

        return citations
    }

    // MARK: - Parsing Helpers

    private func parseDocumentType(_ string: String?) -> DocumentType {
        guard let string = string?.lowercased() else { return .unknown }
        return DocumentType(rawValue: string) ?? .unknown
    }

    private func parseSection(_ string: String?) -> DocumentSection {
        guard let string = string?.lowercased() else { return .unknown }
        return DocumentSection(rawValue: string) ?? .unknown
    }

    private func parseTone(_ string: String?) -> WritingTone {
        guard let string = string?.lowercased() else { return .neutral }
        return WritingTone(rawValue: string) ?? .neutral
    }

    private func parseArgumentStructure(_ dict: [String: Any]?) -> ArgumentStructure? {
        guard let dict = dict else { return nil }
        return ArgumentStructure(
            premise: dict["premise"] as? String,
            reasoning: dict["reasoning"] as? String,
            conclusion: dict["conclusion"] as? String,
            counterarguments: dict["counterarguments"] as? [String] ?? []
        )
    }

    // MARK: - Cache Management

    private func generateCacheKey(for context: FocusedElementDetector.WritingContext) -> String {
        let textHash = (context.surroundingText ?? "").prefix(500).hashValue
        return "\(context.appBundleID)-\(context.windowTitle ?? "")-\(textHash)"
    }

    func clearCache() {
        analysisCache.removeAll()
    }
}

// MARK: - Prompt Templates

enum ContextAnalyzerPrompts {
    static let systemPrompt = """
    You are a legal document analyzer. Your task is to identify:
    1. The type of legal document being written
    2. The current section of the document
    3. The writing tone being used
    4. Key entities, legal concepts, and citations

    Always respond in valid JSON format. Be concise and accurate.
    Focus on legal writing patterns and conventions.
    """
}
