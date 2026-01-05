import Foundation
import SwiftData

/// Represents a writing session - a continuous period of writing activity
@Model
final class WritingSession {
    // MARK: - Properties

    var id: UUID
    var startTime: Date
    var endTime: Date?
    var matterID: UUID?

    // Document context
    var documentType: String?
    var documentTitle: String?
    var appBundleID: String?
    var appName: String?

    // Metrics
    var totalCharactersTyped: Int
    var totalWordsWritten: Int
    var suggestionsShown: Int
    var suggestionsAccepted: Int
    var suggestionsRejected: Int

    // Activity tracking
    var appSwitchCount: Int
    var distractionCount: Int
    var pauseCount: Int
    var totalPauseDuration: TimeInterval

    // Focus metrics
    var focusScore: Double?
    var productivityScore: Double?

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \DraftSuggestion.session)
    var suggestions: [DraftSuggestion]?

    @Relationship(inverse: \Matter.sessions)
    var matter: Matter?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        documentType: String? = nil,
        documentTitle: String? = nil,
        appBundleID: String? = nil,
        appName: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.documentType = documentType
        self.documentTitle = documentTitle
        self.appBundleID = appBundleID
        self.appName = appName

        self.totalCharactersTyped = 0
        self.totalWordsWritten = 0
        self.suggestionsShown = 0
        self.suggestionsAccepted = 0
        self.suggestionsRejected = 0
        self.appSwitchCount = 0
        self.distractionCount = 0
        self.pauseCount = 0
        self.totalPauseDuration = 0
    }

    // MARK: - Computed Properties

    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    var isActive: Bool {
        endTime == nil
    }

    var acceptanceRate: Double {
        guard suggestionsShown > 0 else { return 0 }
        return Double(suggestionsAccepted) / Double(suggestionsShown)
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    // MARK: - Methods

    func end() {
        endTime = Date()
        calculateScores()
    }

    func recordSuggestionShown() {
        suggestionsShown += 1
    }

    func recordSuggestionAccepted() {
        suggestionsAccepted += 1
    }

    func recordSuggestionRejected() {
        suggestionsRejected += 1
    }

    func recordAppSwitch() {
        appSwitchCount += 1
    }

    func recordDistraction() {
        distractionCount += 1
    }

    func recordPause(duration: TimeInterval) {
        pauseCount += 1
        totalPauseDuration += duration
    }

    func addCharacters(_ count: Int) {
        totalCharactersTyped += count
    }

    func addWords(_ count: Int) {
        totalWordsWritten += count
    }

    private func calculateScores() {
        // Focus score: based on distraction and pause patterns
        let distractionPenalty = min(Double(distractionCount) * 0.1, 0.5)
        let pausePenalty = min(totalPauseDuration / duration * 0.3, 0.3)
        focusScore = max(0, 1.0 - distractionPenalty - pausePenalty)

        // Productivity score: based on output and acceptance
        let outputScore = min(Double(totalWordsWritten) / max(duration / 60, 1) / 20, 1.0) // 20 wpm baseline
        let acceptanceBonus = acceptanceRate * 0.2
        productivityScore = min(outputScore + acceptanceBonus, 1.0)
    }
}

// MARK: - Session State

extension WritingSession {
    enum SessionState: String, Codable {
        case active
        case paused
        case ended

        var displayName: String {
            rawValue.capitalized
        }
    }
}
