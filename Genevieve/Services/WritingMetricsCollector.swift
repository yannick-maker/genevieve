import Foundation
import Combine

/// Collects and aggregates writing behavior metrics in real-time
@MainActor
final class WritingMetricsCollector: ObservableObject {
    // MARK: - Published Metrics

    @Published private(set) var currentMetrics = SessionMetrics()
    @Published private(set) var isCollecting = false

    // MARK: - Session Metrics

    struct SessionMetrics {
        // Timing
        var sessionStartTime: Date = Date()
        var lastActivityTime: Date = Date()
        var activeWritingTime: TimeInterval = 0
        var totalSessionTime: TimeInterval = 0

        // Writing volume
        var totalCharactersTyped: Int = 0
        var totalWordsWritten: Int = 0
        var totalDeletions: Int = 0
        var netCharacters: Int = 0

        // Speed metrics
        var wordsPerMinute: Double = 0
        var peakWordsPerMinute: Double = 0
        var charactersPerMinute: Double = 0

        // Pause metrics
        var pauseCount: Int = 0
        var totalPauseDuration: TimeInterval = 0
        var averagePauseDuration: TimeInterval = 0
        var longestPause: TimeInterval = 0

        // Revision metrics
        var revisionCount: Int = 0
        var deletionRate: Double = 0 // deletions per 100 characters
        var rewriteEvents: Int = 0 // detected rewrites of same section

        // Focus metrics
        var appSwitchCount: Int = 0
        var distractionCount: Int = 0
        var focusScore: Double = 1.0 // 0-1, calculated from distractions and pauses

        // Mood indicators (inferred from behavior)
        var estimatedMood: MoodIndicator = .focused
        var frustrationSignals: Int = 0 // rapid deletions, long pauses

        // Progress
        var estimatedDocumentProgress: Double = 0 // 0-1 if estimable

        enum MoodIndicator: String, Codable {
            case focused = "Focused"
            case flowing = "In Flow"
            case struggling = "Struggling"
            case distracted = "Distracted"
            case fatigued = "Fatigued"
        }

        // MARK: - Computed

        var formattedActiveTime: String {
            let minutes = Int(activeWritingTime / 60)
            let seconds = Int(activeWritingTime.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d", minutes, seconds)
        }

        var formattedSessionTime: String {
            let minutes = Int(totalSessionTime / 60)
            if minutes >= 60 {
                let hours = minutes / 60
                let remainingMinutes = minutes % 60
                return "\(hours)h \(remainingMinutes)m"
            }
            return "\(minutes)m"
        }

        var focusPercentage: Int {
            Int(focusScore * 100)
        }

        var isInFlowState: Bool {
            // Flow: sustained typing, minimal pauses, no recent distractions
            wordsPerMinute > 15 &&
            pauseCount < 3 &&
            distractionCount == 0 &&
            activeWritingTime > 300 // At least 5 minutes of sustained writing
        }
    }

    // MARK: - Internal State

    private var lastTextLength: Int = 0
    private var lastTypingTime: Date?
    private var currentPauseStart: Date?
    private var recentDeletions: [Date] = []
    private var typingBurstStart: Date?
    private var wordsInCurrentBurst: Int = 0

    private let pauseThreshold: TimeInterval = 3.0 // Seconds before counting as pause
    private let distractionThreshold: TimeInterval = 30.0 // Seconds away = distraction

    // MARK: - Initialization

    init() {}

    // MARK: - Collection Control

    func startCollecting() {
        isCollecting = true
        currentMetrics = SessionMetrics()
        currentMetrics.sessionStartTime = Date()
        lastTypingTime = Date()
    }

    func stopCollecting() {
        isCollecting = false
        finalizeMetrics()
    }

    func pauseCollecting() {
        // Mark pause start
        if currentPauseStart == nil {
            currentPauseStart = Date()
        }
    }

    func resumeCollecting() {
        // Calculate pause duration
        if let pauseStart = currentPauseStart {
            let duration = Date().timeIntervalSince(pauseStart)
            recordPause(duration: duration)
            currentPauseStart = nil
        }
    }

    // MARK: - Event Recording

    /// Record typing activity with current text length
    func recordTyping(currentLength: Int) {
        guard isCollecting else { return }

        let now = Date()
        let lengthDelta = currentLength - lastTextLength

        // Detect deletions vs additions
        if lengthDelta < 0 {
            currentMetrics.totalDeletions += abs(lengthDelta)
            recentDeletions.append(now)

            // Clean old deletion records
            recentDeletions = recentDeletions.filter { now.timeIntervalSince($0) < 10 }

            // Detect frustration (rapid deletions)
            if recentDeletions.count > 20 {
                currentMetrics.frustrationSignals += 1
            }
        } else if lengthDelta > 0 {
            currentMetrics.totalCharactersTyped += lengthDelta

            // Estimate words (roughly 5 chars per word)
            let estimatedWords = lengthDelta / 5
            if estimatedWords > 0 {
                currentMetrics.totalWordsWritten += estimatedWords
                wordsInCurrentBurst += estimatedWords
            }
        }

        currentMetrics.netCharacters = currentLength
        lastTextLength = currentLength

        // Handle pause detection
        if let lastTime = lastTypingTime {
            let gap = now.timeIntervalSince(lastTime)

            if gap > pauseThreshold {
                recordPause(duration: gap)
            } else {
                // Active typing - add to active time
                currentMetrics.activeWritingTime += gap
            }
        }

        // Update typing burst metrics
        if typingBurstStart == nil {
            typingBurstStart = now
            wordsInCurrentBurst = 0
        }

        lastTypingTime = now
        updateSpeedMetrics()
        updateMoodIndicator()
    }

    /// Record a pause in typing
    func recordPause(duration: TimeInterval) {
        guard isCollecting else { return }

        currentMetrics.pauseCount += 1
        currentMetrics.totalPauseDuration += duration

        if duration > currentMetrics.longestPause {
            currentMetrics.longestPause = duration
        }

        currentMetrics.averagePauseDuration = currentMetrics.totalPauseDuration / Double(currentMetrics.pauseCount)

        // End current typing burst
        if let burstStart = typingBurstStart, wordsInCurrentBurst > 0 {
            let burstDuration = Date().timeIntervalSince(burstStart) - duration
            if burstDuration > 0 {
                let burstWPM = Double(wordsInCurrentBurst) / (burstDuration / 60)
                if burstWPM > currentMetrics.peakWordsPerMinute {
                    currentMetrics.peakWordsPerMinute = burstWPM
                }
            }
        }

        typingBurstStart = nil
        wordsInCurrentBurst = 0

        updateFocusScore()
    }

    /// Record an app switch
    func recordAppSwitch(appName: String, duration: TimeInterval? = nil) {
        guard isCollecting else { return }

        currentMetrics.appSwitchCount += 1

        // Long app switches count as distractions
        if let dur = duration, dur > distractionThreshold {
            currentMetrics.distractionCount += 1
            updateFocusScore()
        }
    }

    /// Record a distraction event
    func recordDistraction() {
        guard isCollecting else { return }

        currentMetrics.distractionCount += 1
        updateFocusScore()
    }

    /// Record a revision/rewrite of the same section
    func recordRewrite() {
        guard isCollecting else { return }

        currentMetrics.rewriteEvents += 1
        currentMetrics.revisionCount += 1
    }

    /// Update document progress estimate (0-1)
    func updateProgress(_ progress: Double) {
        currentMetrics.estimatedDocumentProgress = min(max(progress, 0), 1)
    }

    // MARK: - Metric Calculations

    private func updateSpeedMetrics() {
        // Overall WPM based on active writing time
        if currentMetrics.activeWritingTime > 30 { // At least 30 seconds
            let minutes = currentMetrics.activeWritingTime / 60
            currentMetrics.wordsPerMinute = Double(currentMetrics.totalWordsWritten) / minutes
            currentMetrics.charactersPerMinute = Double(currentMetrics.totalCharactersTyped) / minutes
        }

        // Deletion rate
        if currentMetrics.totalCharactersTyped > 0 {
            currentMetrics.deletionRate = Double(currentMetrics.totalDeletions) / Double(currentMetrics.totalCharactersTyped) * 100
        }
    }

    private func updateFocusScore() {
        // Focus score decreases with:
        // - Distractions (major impact)
        // - Long pauses (moderate impact)
        // - Frequent app switches (minor impact)

        var score = 1.0

        // Distraction penalty: -0.15 per distraction, max -0.5
        let distractionPenalty = min(Double(currentMetrics.distractionCount) * 0.15, 0.5)
        score -= distractionPenalty

        // Pause penalty: based on ratio of pause time to total time
        if currentMetrics.activeWritingTime > 0 {
            let pauseRatio = currentMetrics.totalPauseDuration / (currentMetrics.activeWritingTime + currentMetrics.totalPauseDuration)
            let pausePenalty = min(pauseRatio * 0.3, 0.3)
            score -= pausePenalty
        }

        // App switch penalty: -0.02 per switch, max -0.2
        let switchPenalty = min(Double(currentMetrics.appSwitchCount) * 0.02, 0.2)
        score -= switchPenalty

        currentMetrics.focusScore = max(score, 0)
    }

    private func updateMoodIndicator() {
        let metrics = currentMetrics

        // Determine mood based on behavior patterns
        if metrics.isInFlowState {
            currentMetrics.estimatedMood = .flowing
        } else if metrics.frustrationSignals > 2 || metrics.deletionRate > 50 {
            currentMetrics.estimatedMood = .struggling
        } else if metrics.distractionCount > 3 || metrics.focusScore < 0.5 {
            currentMetrics.estimatedMood = .distracted
        } else if metrics.activeWritingTime > 3600 && metrics.wordsPerMinute < 10 {
            // Over an hour with slow output
            currentMetrics.estimatedMood = .fatigued
        } else {
            currentMetrics.estimatedMood = .focused
        }
    }

    private func finalizeMetrics() {
        currentMetrics.totalSessionTime = Date().timeIntervalSince(currentMetrics.sessionStartTime)
        updateSpeedMetrics()
        updateFocusScore()
        updateMoodIndicator()
    }

    // MARK: - Export for Storage

    /// Convert current metrics to CommentaryEntry.Metadata format
    func toEntryMetadata() -> CommentaryEntry.Metadata {
        var metadata = CommentaryEntry.Metadata()
        metadata.writingSpeedWPM = currentMetrics.wordsPerMinute
        metadata.documentProgress = currentMetrics.estimatedDocumentProgress
        metadata.moodIndicator = currentMetrics.estimatedMood.rawValue
        metadata.focusScore = currentMetrics.focusScore
        metadata.wordCountAtTime = currentMetrics.totalWordsWritten
        metadata.revisionCount = currentMetrics.revisionCount
        return metadata
    }

    /// Summary string for inclusion in commentary context
    func contextSummary() -> String {
        let m = currentMetrics

        var parts: [String] = []

        // Speed
        if m.wordsPerMinute > 0 {
            parts.append(String(format: "Writing speed: %.0f WPM", m.wordsPerMinute))
        }

        // Focus
        parts.append("Focus: \(m.focusPercentage)%")

        // Mood
        parts.append("Mood: \(m.estimatedMood.rawValue)")

        // Notable patterns
        if m.deletionRate > 30 {
            parts.append("High revision rate detected")
        }
        if m.isInFlowState {
            parts.append("Currently in flow state")
        }

        return parts.joined(separator: " | ")
    }

    // MARK: - Reset

    func reset() {
        currentMetrics = SessionMetrics()
        lastTextLength = 0
        lastTypingTime = nil
        currentPauseStart = nil
        recentDeletions = []
        typingBurstStart = nil
        wordsInCurrentBurst = 0
    }
}
