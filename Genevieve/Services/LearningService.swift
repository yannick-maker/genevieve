import Foundation
import SwiftData
import Combine

/// Service for learning user preferences and writing style over time
@MainActor
final class LearningService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var userProfile: UserWritingProfile
    @Published private(set) var recentFeedback: [SuggestionFeedback] = []
    @Published private(set) var assumptions: [Assumption] = []

    // MARK: - Types

    struct UserWritingProfile: Codable {
        var preferredTone: TonePreference
        var verbosityLevel: VerbosityLevel
        var formalityLevel: FormalityLevel
        var preferredPatterns: [String: Int] // pattern -> acceptance count
        var avoidedPatterns: [String: Int]   // pattern -> rejection count
        var vocabularyPreferences: [String: Int]
        var lastUpdated: Date

        static var `default`: UserWritingProfile {
            UserWritingProfile(
                preferredTone: .neutral,
                verbosityLevel: .moderate,
                formalityLevel: .formal,
                preferredPatterns: [:],
                avoidedPatterns: [:],
                vocabularyPreferences: [:],
                lastUpdated: Date()
            )
        }
    }

    enum TonePreference: String, Codable, CaseIterable {
        case formal
        case persuasive
        case analytical
        case conversational
        case neutral

        var displayName: String { rawValue.capitalized }
    }

    enum VerbosityLevel: String, Codable, CaseIterable {
        case concise
        case moderate
        case detailed

        var displayName: String { rawValue.capitalized }
    }

    enum FormalityLevel: String, Codable, CaseIterable {
        case casual
        case professional
        case formal
        case veryFormal = "very_formal"

        var displayName: String {
            switch self {
            case .casual: return "Casual"
            case .professional: return "Professional"
            case .formal: return "Formal"
            case .veryFormal: return "Very Formal"
            }
        }
    }

    struct SuggestionFeedback: Identifiable, Codable {
        let id: UUID
        let suggestionID: UUID
        let originalText: String
        let suggestedText: String
        let action: FeedbackAction
        let reason: FeedbackReason?
        let timestamp: Date

        enum FeedbackAction: String, Codable {
            case accepted
            case rejected
            case modified
            case copied
        }

        enum FeedbackReason: String, Codable, CaseIterable {
            case notRelevant = "not_relevant"
            case wrongTone = "wrong_tone"
            case tooVerbose = "too_verbose"
            case tooConcise = "too_concise"
            case incorrectLegal = "incorrect_legal"
            case preferOriginal = "prefer_original"
            case other

            var displayName: String {
                switch self {
                case .notRelevant: return "Not relevant"
                case .wrongTone: return "Wrong tone"
                case .tooVerbose: return "Too verbose"
                case .tooConcise: return "Too concise"
                case .incorrectLegal: return "Incorrect legal standard"
                case .preferOriginal: return "Prefer my original"
                case .other: return "Other"
                }
            }
        }
    }

    struct Assumption: Identifiable {
        let id: UUID
        let content: String
        let category: AssumptionCategory
        let confidence: Double
        var isConfirmed: Bool?
        let createdAt: Date

        enum AssumptionCategory: String {
            case documentType
            case jurisdiction
            case audience
            case tone
            case legalStandard
        }
    }

    // MARK: - Storage

    private let profileKey = "userWritingProfile"
    private let feedbackKey = "recentFeedback"
    private var modelContext: ModelContext?

    // MARK: - Configuration

    private let maxRecentFeedback = 100
    private let learningThreshold = 5 // Min feedback count to learn pattern

    // MARK: - Initialization

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        self.userProfile = Self.loadProfile() ?? .default
        self.recentFeedback = Self.loadFeedback()
    }

    // MARK: - Feedback Recording

    /// Record feedback for a suggestion
    func recordFeedback(
        suggestionID: UUID,
        originalText: String,
        suggestedText: String,
        action: SuggestionFeedback.FeedbackAction,
        reason: SuggestionFeedback.FeedbackReason? = nil
    ) {
        let feedback = SuggestionFeedback(
            id: UUID(),
            suggestionID: suggestionID,
            originalText: originalText,
            suggestedText: suggestedText,
            action: action,
            reason: reason,
            timestamp: Date()
        )

        recentFeedback.insert(feedback, at: 0)

        // Trim old feedback
        if recentFeedback.count > maxRecentFeedback {
            recentFeedback = Array(recentFeedback.prefix(maxRecentFeedback))
        }

        // Learn from feedback
        learnFromFeedback(feedback)

        // Persist
        saveFeedback()
        saveProfile()
    }

    /// Record quick feedback (thumbs up/down)
    func recordQuickFeedback(
        suggestionID: UUID,
        originalText: String,
        suggestedText: String,
        wasHelpful: Bool
    ) {
        recordFeedback(
            suggestionID: suggestionID,
            originalText: originalText,
            suggestedText: suggestedText,
            action: wasHelpful ? .accepted : .rejected,
            reason: wasHelpful ? nil : .preferOriginal
        )
    }

    // MARK: - Learning

    private func learnFromFeedback(_ feedback: SuggestionFeedback) {
        switch feedback.action {
        case .accepted:
            learnAcceptedPatterns(from: feedback.suggestedText)
            updateTonePreference(from: feedback.suggestedText, accepted: true)

        case .rejected:
            learnRejectedPatterns(from: feedback.suggestedText, reason: feedback.reason)

        case .modified:
            // User liked the direction but wanted changes
            // Could compare original vs modified to learn
            break

        case .copied:
            // Soft signal of interest
            break
        }

        userProfile.lastUpdated = Date()
    }

    private func learnAcceptedPatterns(from text: String) {
        let patterns = extractPatterns(from: text)

        for pattern in patterns {
            userProfile.preferredPatterns[pattern, default: 0] += 1
        }

        // Update verbosity preference
        let wordCount = text.split(separator: " ").count
        if wordCount < 20 {
            adjustVerbosityPreference(toward: .concise)
        } else if wordCount > 50 {
            adjustVerbosityPreference(toward: .detailed)
        }
    }

    private func learnRejectedPatterns(
        from text: String,
        reason: SuggestionFeedback.FeedbackReason?
    ) {
        let patterns = extractPatterns(from: text)

        for pattern in patterns {
            userProfile.avoidedPatterns[pattern, default: 0] += 1
        }

        // Learn from specific reasons
        switch reason {
        case .wrongTone:
            // User doesn't like this tone - track for future
            break
        case .tooVerbose:
            adjustVerbosityPreference(toward: .concise)
        case .tooConcise:
            adjustVerbosityPreference(toward: .detailed)
        case .incorrectLegal:
            // Flag this pattern as legally problematic
            break
        default:
            break
        }
    }

    private func extractPatterns(from text: String) -> [String] {
        var patterns: [String] = []

        // Extract sentence starters
        let sentences = text.components(separatedBy: ". ")
        for sentence in sentences.prefix(3) {
            let words = sentence.split(separator: " ").prefix(3)
            if words.count >= 2 {
                patterns.append(words.joined(separator: " ").lowercased())
            }
        }

        // Extract legal phrases
        let legalPhrases = [
            "pursuant to", "in accordance with", "notwithstanding",
            "hereby", "whereas", "therefore", "accordingly",
            "it is undisputed", "the court held", "under the standard"
        ]

        let lowercased = text.lowercased()
        for phrase in legalPhrases {
            if lowercased.contains(phrase) {
                patterns.append(phrase)
            }
        }

        return patterns
    }

    private func adjustVerbosityPreference(toward level: VerbosityLevel) {
        // Gradual adjustment based on feedback
        let levels: [VerbosityLevel] = [.concise, .moderate, .detailed]
        guard let currentIndex = levels.firstIndex(of: userProfile.verbosityLevel),
              let targetIndex = levels.firstIndex(of: level) else { return }

        // Move one step toward target
        if targetIndex > currentIndex && currentIndex < levels.count - 1 {
            userProfile.verbosityLevel = levels[currentIndex + 1]
        } else if targetIndex < currentIndex && currentIndex > 0 {
            userProfile.verbosityLevel = levels[currentIndex - 1]
        }
    }

    private func updateTonePreference(from text: String, accepted: Bool) {
        // Detect tone from accepted text
        let lowercased = text.lowercased()

        if lowercased.contains("respectfully") || lowercased.contains("hereby") {
            if accepted {
                userProfile.preferredTone = .formal
            }
        } else if lowercased.contains("clearly") || lowercased.contains("must") {
            if accepted {
                userProfile.preferredTone = .persuasive
            }
        }
    }

    // MARK: - Assumptions

    /// Surface an assumption for user confirmation
    func surfaceAssumption(
        content: String,
        category: Assumption.AssumptionCategory,
        confidence: Double
    ) -> Assumption {
        let assumption = Assumption(
            id: UUID(),
            content: content,
            category: category,
            confidence: confidence,
            isConfirmed: nil,
            createdAt: Date()
        )

        assumptions.append(assumption)
        return assumption
    }

    /// Confirm or reject an assumption
    func resolveAssumption(_ id: UUID, confirmed: Bool) {
        if let index = assumptions.firstIndex(where: { $0.id == id }) {
            assumptions[index].isConfirmed = confirmed

            // Learn from assumption resolution
            if confirmed {
                // Assumption was correct - reinforce this pattern
            } else {
                // Assumption was wrong - adjust
            }
        }
    }

    /// Clear resolved assumptions
    func clearResolvedAssumptions() {
        assumptions.removeAll { $0.isConfirmed != nil }
    }

    // MARK: - Preference Queries

    /// Check if user prefers a particular pattern
    func prefersPattern(_ pattern: String) -> Bool {
        let preferred = userProfile.preferredPatterns[pattern.lowercased()] ?? 0
        let avoided = userProfile.avoidedPatterns[pattern.lowercased()] ?? 0
        return preferred > avoided && preferred >= learningThreshold
    }

    /// Check if user avoids a particular pattern
    func avoidsPattern(_ pattern: String) -> Bool {
        let avoided = userProfile.avoidedPatterns[pattern.lowercased()] ?? 0
        return avoided >= learningThreshold
    }

    /// Get prompt modifier based on learned preferences
    func getPromptModifier() -> String {
        var modifiers: [String] = []

        // Tone
        modifiers.append("Use a \(userProfile.preferredTone.displayName.lowercased()) tone.")

        // Verbosity
        switch userProfile.verbosityLevel {
        case .concise:
            modifiers.append("Be concise and direct.")
        case .moderate:
            modifiers.append("Use moderate detail.")
        case .detailed:
            modifiers.append("Provide thorough explanations.")
        }

        // Formality
        switch userProfile.formalityLevel {
        case .casual:
            modifiers.append("Use casual language.")
        case .professional:
            modifiers.append("Maintain professional language.")
        case .formal:
            modifiers.append("Use formal legal language.")
        case .veryFormal:
            modifiers.append("Use very formal, traditional legal language.")
        }

        // Patterns to include
        let topPreferred = userProfile.preferredPatterns
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }

        if !topPreferred.isEmpty {
            modifiers.append("The user prefers phrases like: \(topPreferred.joined(separator: ", "))")
        }

        // Patterns to avoid
        let topAvoided = userProfile.avoidedPatterns
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }

        if !topAvoided.isEmpty {
            modifiers.append("Avoid phrases like: \(topAvoided.joined(separator: ", "))")
        }

        return modifiers.joined(separator: " ")
    }

    // MARK: - Statistics

    var acceptanceRate: Double {
        let accepted = recentFeedback.filter { $0.action == .accepted }.count
        guard !recentFeedback.isEmpty else { return 0 }
        return Double(accepted) / Double(recentFeedback.count)
    }

    var topRejectionReasons: [(reason: SuggestionFeedback.FeedbackReason, count: Int)] {
        var counts: [SuggestionFeedback.FeedbackReason: Int] = [:]

        for feedback in recentFeedback where feedback.action == .rejected {
            if let reason = feedback.reason {
                counts[reason, default: 0] += 1
            }
        }

        return counts
            .map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: - Persistence

    private static func loadProfile() -> UserWritingProfile? {
        guard let data = UserDefaults.standard.data(forKey: "userWritingProfile"),
              let profile = try? JSONDecoder().decode(UserWritingProfile.self, from: data) else {
            return nil
        }
        return profile
    }

    private func saveProfile() {
        guard let data = try? JSONEncoder().encode(userProfile) else { return }
        UserDefaults.standard.set(data, forKey: profileKey)
    }

    private static func loadFeedback() -> [SuggestionFeedback] {
        guard let data = UserDefaults.standard.data(forKey: "recentFeedback"),
              let feedback = try? JSONDecoder().decode([SuggestionFeedback].self, from: data) else {
            return []
        }
        return feedback
    }

    private func saveFeedback() {
        guard let data = try? JSONEncoder().encode(recentFeedback) else { return }
        UserDefaults.standard.set(data, forKey: feedbackKey)
    }

    /// Reset all learned preferences
    func resetProfile() {
        userProfile = .default
        recentFeedback = []
        assumptions = []
        saveProfile()
        saveFeedback()
    }
}
