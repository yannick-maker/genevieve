import Foundation
import SwiftData

/// Represents a draft suggestion offered by Genevieve
@Model
final class DraftSuggestion {
    // MARK: - Properties

    var id: UUID
    var createdAt: Date

    // Content
    var originalText: String
    var suggestedText: String
    var explanation: String?

    // Context
    var documentType: String?
    var sectionType: String?
    var triggerReason: String?

    // AI metadata
    var modelUsed: String?
    var confidence: Double
    var processingTime: TimeInterval?

    // User response
    var status: String // pending, accepted, rejected, modified, expired
    var respondedAt: Date?
    var userModification: String?

    // Quality signals
    var wasHelpful: Bool?
    var feedbackNote: String?

    // Relationships
    var session: WritingSession?
    var matter: Matter?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        originalText: String,
        suggestedText: String,
        explanation: String? = nil,
        documentType: String? = nil,
        sectionType: String? = nil,
        triggerReason: String? = nil,
        modelUsed: String? = nil,
        confidence: Double = 0.5
    ) {
        self.id = id
        self.createdAt = Date()
        self.originalText = originalText
        self.suggestedText = suggestedText
        self.explanation = explanation
        self.documentType = documentType
        self.sectionType = sectionType
        self.triggerReason = triggerReason
        self.modelUsed = modelUsed
        self.confidence = confidence
        self.status = SuggestionStatus.pending.rawValue
    }

    // MARK: - Computed Properties

    var suggestionStatus: SuggestionStatus {
        get { SuggestionStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }

    var isResolved: Bool {
        suggestionStatus != .pending
    }

    var characterDelta: Int {
        suggestedText.count - originalText.count
    }

    var wordDelta: Int {
        let originalWords = originalText.split(separator: " ").count
        let suggestedWords = suggestedText.split(separator: " ").count
        return suggestedWords - originalWords
    }

    var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case 0.8...1.0: return .high
        case 0.5..<0.8: return .medium
        default: return .low
        }
    }

    // MARK: - Methods

    func accept() {
        suggestionStatus = .accepted
        respondedAt = Date()
    }

    func reject() {
        suggestionStatus = .rejected
        respondedAt = Date()
    }

    func modify(with text: String) {
        suggestionStatus = .modified
        userModification = text
        respondedAt = Date()
    }

    func expire() {
        if suggestionStatus == .pending {
            suggestionStatus = .expired
            respondedAt = Date()
        }
    }

    func markHelpful(_ helpful: Bool, note: String? = nil) {
        wasHelpful = helpful
        feedbackNote = note
    }
}

// MARK: - Supporting Types

extension DraftSuggestion {
    enum SuggestionStatus: String, Codable, CaseIterable {
        case pending
        case accepted
        case rejected
        case modified
        case expired

        var displayName: String {
            rawValue.capitalized
        }

        var icon: String {
            switch self {
            case .pending: return "clock"
            case .accepted: return "checkmark.circle.fill"
            case .rejected: return "xmark.circle.fill"
            case .modified: return "pencil.circle.fill"
            case .expired: return "clock.badge.xmark"
            }
        }
    }

    enum ConfidenceLevel: String {
        case high
        case medium
        case low

        var displayName: String {
            rawValue.capitalized
        }

        var color: String {
            switch self {
            case .high: return "green"
            case .medium: return "orange"
            case .low: return "gray"
            }
        }
    }

    enum TriggerReason: String, Codable {
        case proactive          // AI noticed opportunity
        case userRequest        // User asked for suggestion
        case stuckDetected      // User appeared stuck
        case editingLoop        // Repeated editing detected
        case sectionChange      // New section started
        case contextChange      // Document context changed

        var displayName: String {
            switch self {
            case .proactive: return "Proactive"
            case .userRequest: return "Requested"
            case .stuckDetected: return "Stuck Detected"
            case .editingLoop: return "Editing Loop"
            case .sectionChange: return "Section Change"
            case .contextChange: return "Context Change"
            }
        }
    }
}

// MARK: - Suggestion Analysis

extension DraftSuggestion {
    /// Analysis of why the suggestion is an improvement
    struct SuggestionAnalysis {
        let improvements: [Improvement]
        let concerns: [String]
        let overallReasoning: String

        struct Improvement {
            let category: ImprovementCategory
            let description: String
        }

        enum ImprovementCategory: String {
            case clarity
            case precision
            case persuasiveness
            case conciseness
            case formality
            case flow
            case legalStandard

            var displayName: String {
                switch self {
                case .clarity: return "Clearer"
                case .precision: return "More Precise"
                case .persuasiveness: return "More Persuasive"
                case .conciseness: return "More Concise"
                case .formality: return "More Formal"
                case .flow: return "Better Flow"
                case .legalStandard: return "Legal Standard"
                }
            }
        }
    }

    /// Parse explanation into structured analysis
    func parseAnalysis() -> SuggestionAnalysis? {
        guard let explanation = explanation else { return nil }

        // Simple parsing - in practice this would be more sophisticated
        var improvements: [SuggestionAnalysis.Improvement] = []

        let lowercased = explanation.lowercased()

        if lowercased.contains("clear") {
            improvements.append(.init(category: .clarity, description: "Improves clarity"))
        }
        if lowercased.contains("precise") || lowercased.contains("specific") {
            improvements.append(.init(category: .precision, description: "More precise language"))
        }
        if lowercased.contains("persuasive") || lowercased.contains("stronger") {
            improvements.append(.init(category: .persuasiveness, description: "More persuasive"))
        }
        if lowercased.contains("concise") || lowercased.contains("shorter") {
            improvements.append(.init(category: .conciseness, description: "More concise"))
        }

        return SuggestionAnalysis(
            improvements: improvements,
            concerns: [],
            overallReasoning: explanation
        )
    }
}
