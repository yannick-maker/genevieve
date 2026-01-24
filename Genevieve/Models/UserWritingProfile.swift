import Foundation
import SwiftData

/// Persistent profile tracking the user's writing patterns, strengths, and growth over time
/// Used by Genevieve to provide personalized, context-aware commentary
@Model
final class UserWritingProfile {
    // MARK: - Properties

    var id: UUID
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Writing Patterns

    /// Common patterns observed in user's writing (JSON array)
    var commonPatternsJSON: Data?

    /// Areas where user excels (JSON array)
    var strengthAreasJSON: Data?

    /// Areas for improvement (JSON array)
    var growthAreasJSON: Data?

    /// User's preferred writing tone
    var preferredTone: String?

    /// Typical document types worked on
    var frequentDocumentTypes: [String]?

    // MARK: - Aggregate Metrics

    var totalSessions: Int
    var totalTimeWriting: TimeInterval
    var totalWordsWritten: Int
    var totalSuggestionsShown: Int
    var totalSuggestionsAccepted: Int
    var totalCommentaryEntries: Int
    var totalDialogueMessages: Int

    // MARK: - Writing Speed

    var averageWordsPerMinute: Double?
    var peakWordsPerMinute: Double?
    var typicalSessionDuration: TimeInterval?

    // MARK: - Improvement Tracking

    /// Scores by category over time (JSON dictionary)
    var improvementScoresJSON: Data?

    /// Milestones achieved (JSON array)
    var milestonesJSON: Data?

    // MARK: - Narrative Summary

    /// AI-generated narrative summary of user's writing journey
    var profileSummary: String?
    var profileSummaryGeneratedAt: Date?

    /// Key insights for quick reference
    var keyInsights: [String]?

    // MARK: - Preferences

    /// User's preferred feedback directness level (1-5, 5 being most direct)
    var feedbackDirectness: Int

    /// Whether to include teaching moments in commentary
    var includeTeachingMoments: Bool

    /// Whether to reference past observations
    var useNarrativeMemory: Bool

    // MARK: - Initialization

    init(id: UUID = UUID()) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()

        self.totalSessions = 0
        self.totalTimeWriting = 0
        self.totalWordsWritten = 0
        self.totalSuggestionsShown = 0
        self.totalSuggestionsAccepted = 0
        self.totalCommentaryEntries = 0
        self.totalDialogueMessages = 0

        self.feedbackDirectness = 5 // Very direct by default (per user preference)
        self.includeTeachingMoments = true
        self.useNarrativeMemory = true
    }

    // MARK: - Computed Properties

    var suggestionAcceptanceRate: Double {
        guard totalSuggestionsShown > 0 else { return 0 }
        return Double(totalSuggestionsAccepted) / Double(totalSuggestionsShown)
    }

    var averageSessionDuration: TimeInterval {
        guard totalSessions > 0 else { return 0 }
        return totalTimeWriting / Double(totalSessions)
    }

    var formattedTotalTime: String {
        let hours = Int(totalTimeWriting) / 3600
        let minutes = (Int(totalTimeWriting) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var experienceLevel: ExperienceLevel {
        switch totalSessions {
        case 0..<5: return .newcomer
        case 5..<20: return .developing
        case 20..<50: return .established
        case 50..<100: return .experienced
        default: return .veteran
        }
    }

    // MARK: - Pattern Arrays (Codable helpers)

    var commonPatterns: [WritingPattern] {
        get {
            guard let data = commonPatternsJSON else { return [] }
            return (try? JSONDecoder().decode([WritingPattern].self, from: data)) ?? []
        }
        set {
            commonPatternsJSON = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }

    var strengthAreas: [SkillArea] {
        get {
            guard let data = strengthAreasJSON else { return [] }
            return (try? JSONDecoder().decode([SkillArea].self, from: data)) ?? []
        }
        set {
            strengthAreasJSON = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }

    var growthAreas: [SkillArea] {
        get {
            guard let data = growthAreasJSON else { return [] }
            return (try? JSONDecoder().decode([SkillArea].self, from: data)) ?? []
        }
        set {
            growthAreasJSON = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }

    var improvementScores: [String: ImprovementScore] {
        get {
            guard let data = improvementScoresJSON else { return [:] }
            return (try? JSONDecoder().decode([String: ImprovementScore].self, from: data)) ?? [:]
        }
        set {
            improvementScoresJSON = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }

    var milestones: [Milestone] {
        get {
            guard let data = milestonesJSON else { return [] }
            return (try? JSONDecoder().decode([Milestone].self, from: data)) ?? []
        }
        set {
            milestonesJSON = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }

    // MARK: - Methods

    /// Record a completed session
    func recordSession(duration: TimeInterval, wordsWritten: Int, suggestionsShown: Int, suggestionsAccepted: Int) {
        totalSessions += 1
        totalTimeWriting += duration
        totalWordsWritten += wordsWritten
        totalSuggestionsShown += suggestionsShown
        totalSuggestionsAccepted += suggestionsAccepted

        // Update average WPM
        if duration > 60 { // Only count sessions longer than 1 minute
            let sessionWPM = Double(wordsWritten) / (duration / 60)
            if let currentAvg = averageWordsPerMinute {
                // Weighted average
                averageWordsPerMinute = (currentAvg * Double(totalSessions - 1) + sessionWPM) / Double(totalSessions)
            } else {
                averageWordsPerMinute = sessionWPM
            }

            if sessionWPM > (peakWordsPerMinute ?? 0) {
                peakWordsPerMinute = sessionWPM
            }
        }

        updatedAt = Date()
    }

    /// Record a commentary entry
    func recordCommentaryEntry(isUserMessage: Bool) {
        totalCommentaryEntries += 1
        if isUserMessage {
            totalDialogueMessages += 1
        }
        updatedAt = Date()
    }

    /// Add a strength area if not already present
    func addStrength(_ area: SkillArea) {
        var current = strengthAreas
        if !current.contains(where: { $0.name == area.name }) {
            current.append(area)
            strengthAreas = current
        }
    }

    /// Add a growth area if not already present
    func addGrowthArea(_ area: SkillArea) {
        var current = growthAreas
        if !current.contains(where: { $0.name == area.name }) {
            current.append(area)
            growthAreas = current
        }
    }

    /// Record a milestone achievement
    func recordMilestone(_ milestone: Milestone) {
        var current = milestones
        if !current.contains(where: { $0.type == milestone.type }) {
            current.append(milestone)
            milestones = current
        }
    }

    /// Update improvement score for a category
    func updateImprovementScore(category: String, newScore: Double) {
        var scores = improvementScores
        if var existing = scores[category] {
            existing.recordScore(newScore)
            scores[category] = existing
        } else {
            scores[category] = ImprovementScore(category: category, currentScore: newScore)
        }
        improvementScores = scores
    }

    /// Check if profile summary needs regeneration (older than 7 days)
    var needsSummaryUpdate: Bool {
        guard let generatedAt = profileSummaryGeneratedAt else { return true }
        return Date().timeIntervalSince(generatedAt) > 7 * 24 * 60 * 60
    }
}

// MARK: - Supporting Types

extension UserWritingProfile {
    enum ExperienceLevel: String, Codable {
        case newcomer = "Newcomer"
        case developing = "Developing"
        case established = "Established"
        case experienced = "Experienced"
        case veteran = "Veteran"

        var description: String {
            switch self {
            case .newcomer: return "Just getting started with Genevieve"
            case .developing: return "Building writing habits"
            case .established: return "Consistent writing practice"
            case .experienced: return "Skilled and productive writer"
            case .veteran: return "Writing expert"
            }
        }
    }

    struct WritingPattern: Codable, Equatable {
        let name: String
        let description: String
        let frequency: Int // How often observed
        let firstObserved: Date
        let lastObserved: Date

        var isRecent: Bool {
            Date().timeIntervalSince(lastObserved) < 7 * 24 * 60 * 60
        }
    }

    struct SkillArea: Codable, Equatable {
        let name: String
        let description: String
        var score: Double // 0-1
        let observedAt: Date

        var displayScore: String {
            let percentage = Int(score * 100)
            return "\(percentage)%"
        }
    }

    struct ImprovementScore: Codable {
        let category: String
        var currentScore: Double
        var previousScore: Double?
        var scoreHistory: [ScoreEntry]
        let startedAt: Date
        var lastUpdated: Date

        struct ScoreEntry: Codable {
            let score: Double
            let date: Date
        }

        init(category: String, currentScore: Double) {
            self.category = category
            self.currentScore = currentScore
            self.previousScore = nil
            self.scoreHistory = [ScoreEntry(score: currentScore, date: Date())]
            self.startedAt = Date()
            self.lastUpdated = Date()
        }

        var improvement: Double? {
            guard let previous = previousScore else { return nil }
            return currentScore - previous
        }

        var improvementPercentage: Double? {
            guard let previous = previousScore, previous > 0 else { return nil }
            return ((currentScore - previous) / previous) * 100
        }

        mutating func recordScore(_ score: Double) {
            previousScore = currentScore
            currentScore = score
            scoreHistory.append(ScoreEntry(score: score, date: Date()))
            lastUpdated = Date()

            // Keep only last 100 entries
            if scoreHistory.count > 100 {
                scoreHistory = Array(scoreHistory.suffix(100))
            }
        }
    }

    struct Milestone: Codable, Equatable {
        let type: MilestoneType
        let achievedAt: Date
        let description: String

        enum MilestoneType: String, Codable {
            case firstSession = "first_session"
            case tenSessions = "ten_sessions"
            case fiftySessions = "fifty_sessions"
            case hundredSessions = "hundred_sessions"
            case thousandWords = "thousand_words"
            case tenThousandWords = "ten_thousand_words"
            case hundredThousandWords = "hundred_thousand_words"
            case firstSuggestionAccepted = "first_suggestion"
            case hundredSuggestions = "hundred_suggestions"
            case weekStreak = "week_streak"
            case monthStreak = "month_streak"
        }

        static func == (lhs: Milestone, rhs: Milestone) -> Bool {
            lhs.type == rhs.type
        }
    }
}

// MARK: - Context for Commentary

extension UserWritingProfile {
    /// Generate a context summary for use in commentary prompts
    func contextSummary(maxLength: Int = 500) -> String {
        var parts: [String] = []

        // Experience level
        parts.append("Writer level: \(experienceLevel.rawValue)")

        // Key stats
        parts.append("Sessions: \(totalSessions), Words: \(totalWordsWritten)")

        // Strengths
        if !strengthAreas.isEmpty {
            let strengthNames = strengthAreas.prefix(3).map { $0.name }
            parts.append("Strengths: \(strengthNames.joined(separator: ", "))")
        }

        // Growth areas
        if !growthAreas.isEmpty {
            let growthNames = growthAreas.prefix(3).map { $0.name }
            parts.append("Growth areas: \(growthNames.joined(separator: ", "))")
        }

        // Recent patterns
        let recentPatterns = commonPatterns.filter { $0.isRecent }.prefix(2)
        if !recentPatterns.isEmpty {
            let patternNames = recentPatterns.map { $0.name }
            parts.append("Recent patterns: \(patternNames.joined(separator: ", "))")
        }

        // Key insights
        if let insights = keyInsights?.prefix(2), !insights.isEmpty {
            parts.append("Insights: \(insights.joined(separator: "; "))")
        }

        let summary = parts.joined(separator: ". ")

        if summary.count > maxLength {
            return String(summary.prefix(maxLength - 3)) + "..."
        }

        return summary
    }
}
