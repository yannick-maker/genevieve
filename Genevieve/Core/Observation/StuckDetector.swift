import Foundation
import Combine

/// Detects when a user appears to be "stuck" while writing
/// Uses multiple signals: pause duration, distraction patterns, rewriting behavior, navigation
@MainActor
final class StuckDetector: ObservableObject {
    // MARK: - Published State

    @Published private(set) var stuckScore: Double = 0.0
    @Published private(set) var isLikelyStuck = false
    @Published private(set) var currentSignals: StuckSignals = .init()
    @Published private(set) var flowState: FlowState = .unknown

    // MARK: - Types

    struct StuckSignals: Equatable {
        var pauseSignal: Double = 0
        var distractionSignal: Double = 0
        var rewritingSignal: Double = 0
        var navigationSignal: Double = 0

        var weighted: Double {
            // Weighted combination per plan
            (pauseSignal * 0.35) +
            (distractionSignal * 0.30) +
            (rewritingSignal * 0.25) +
            (navigationSignal * 0.10)
        }
    }

    enum FlowState: String {
        case flowing       // User is typing steadily
        case paused        // Brief pause
        case stuck         // Extended pause or struggle
        case distracted    // Switched to distraction app
        case unknown

        var shouldInterrupt: Bool {
            switch self {
            case .flowing:
                return false
            case .paused, .stuck, .distracted, .unknown:
                return true
            }
        }
    }

    enum StuckType: String, CaseIterable {
        case pause
        case distraction
        case rewriting
        case searching

        var displayName: String {
            switch self {
            case .pause: return "Taking a moment"
            case .distraction: return "Distracted"
            case .rewriting: return "Struggling with phrasing"
            case .searching: return "Searching for something"
            }
        }

        var helpPrompt: String {
            switch self {
            case .pause:
                return "Looks like you've paused. Would you like help continuing?"
            case .distraction:
                return "Ready to get back to your draft?"
            case .rewriting:
                return "Having trouble with this section? Let me suggest alternatives."
            case .searching:
                return "Looking for something? I can help you find the right phrasing or precedent."
            }
        }
    }

    // MARK: - Tracking Data

    private var lastTypingTime: Date?
    private var lastTextLength: Int = 0
    private var deletionCount: Int = 0
    private var deletionWindow: [Date] = []
    private var scrollEvents: [Date] = []
    private var textHistory: [(text: String, timestamp: Date)] = []

    // MARK: - Configuration

    struct Configuration {
        var pauseThreshold: TimeInterval = 30      // Seconds without typing
        var longPauseThreshold: TimeInterval = 60  // Extended pause
        var stuckThreshold: Double = 0.5           // Score threshold for "stuck"
        var flowThreshold: Double = 0.3            // Below this is "flowing"
        var rewriteWindowSeconds: TimeInterval = 30
        var navigationWindowSeconds: TimeInterval = 15
        var cooldownPeriod: TimeInterval = 120     // Min time between proactive triggers
    }

    var configuration = Configuration()

    // MARK: - Dependencies

    private var screenObserver: ScreenObserver?
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?

    // MARK: - Cooldown

    private var lastTriggerTime: Date?

    // MARK: - Initialization

    init() {}

    /// Connect to screen observer for distraction tracking
    func connect(to screenObserver: ScreenObserver) {
        self.screenObserver = screenObserver

        // Listen for distraction events
        screenObserver.onDistractionDetected = { [weak self] _, duration in
            Task { @MainActor in
                self?.recordDistraction(duration: duration)
            }
        }

        screenObserver.onReturnToWork = { [weak self] _ in
            Task { @MainActor in
                self?.recordReturnFromDistraction()
            }
        }
    }

    // MARK: - Observation

    /// Start monitoring for stuck signals
    func startMonitoring() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStuckScore()
            }
        }
    }

    /// Stop monitoring
    func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Signal Recording

    /// Record typing activity
    func recordTyping(currentLength: Int) {
        let now = Date()

        // Check for deletions (text getting shorter)
        if currentLength < lastTextLength {
            let deleted = lastTextLength - currentLength
            if deleted > 0 {
                deletionCount += deleted
                deletionWindow.append(now)
            }
        }

        lastTypingTime = now
        lastTextLength = currentLength

        // Update flow state
        flowState = .flowing
    }

    /// Record text content for rewrite detection
    func recordTextContent(_ text: String) {
        let now = Date()

        // Keep limited history
        textHistory.append((text: text, timestamp: now))
        if textHistory.count > 10 {
            textHistory.removeFirst()
        }
    }

    /// Record scroll/navigation event
    func recordNavigation() {
        scrollEvents.append(Date())

        // Trim old events
        let cutoff = Date().addingTimeInterval(-configuration.navigationWindowSeconds)
        scrollEvents.removeAll { $0 < cutoff }
    }

    /// Record distraction (switching to non-work app)
    func recordDistraction(duration: TimeInterval) {
        // Distraction signal increases with duration
        let normalizedDuration = min(duration / 300, 1.0) // 5 min max
        currentSignals.distractionSignal = normalizedDuration
        flowState = .distracted
    }

    /// Record return from distraction
    func recordReturnFromDistraction() {
        // Gradually decay distraction signal
        Task {
            for _ in 0..<10 {
                try? await Task.sleep(for: .seconds(1))
                currentSignals.distractionSignal = max(0, currentSignals.distractionSignal - 0.1)
            }
        }
    }

    // MARK: - Score Calculation

    private func updateStuckScore() {
        // Calculate individual signals
        currentSignals.pauseSignal = calculatePauseSignal()
        currentSignals.rewritingSignal = calculateRewritingSignal()
        currentSignals.navigationSignal = calculateNavigationSignal()
        // Distraction signal is updated by recordDistraction

        // Calculate weighted score
        stuckScore = currentSignals.weighted

        // Update stuck status
        isLikelyStuck = stuckScore >= configuration.stuckThreshold

        // Update flow state
        updateFlowState()
    }

    private func calculatePauseSignal() -> Double {
        guard let lastTyping = lastTypingTime else { return 0 }

        let pauseDuration = Date().timeIntervalSince(lastTyping)

        if pauseDuration < configuration.pauseThreshold {
            return 0
        } else if pauseDuration < configuration.longPauseThreshold {
            // Linear increase from 0 to 0.7
            let progress = (pauseDuration - configuration.pauseThreshold) /
                          (configuration.longPauseThreshold - configuration.pauseThreshold)
            return progress * 0.7
        } else {
            // Cap at 1.0 for very long pauses
            return min(1.0, 0.7 + (pauseDuration - configuration.longPauseThreshold) / 120)
        }
    }

    private func calculateRewritingSignal() -> Double {
        let cutoff = Date().addingTimeInterval(-configuration.rewriteWindowSeconds)
        let recentDeletions = deletionWindow.filter { $0 > cutoff }

        // Also check for repeated similar text (editing same passage)
        let similarityScore = calculateTextSimilarity()

        // High deletion + editing same text = rewriting
        let deletionScore = min(Double(recentDeletions.count) / 10.0, 1.0)
        return max(deletionScore, similarityScore)
    }

    private func calculateTextSimilarity() -> Double {
        guard textHistory.count >= 3 else { return 0 }

        // Check if recent texts are similar (same paragraph being edited)
        let recentTexts = textHistory.suffix(5).map { $0.text }

        // Simple similarity: check if texts are within edit distance
        var similarPairs = 0
        for i in 0..<(recentTexts.count - 1) {
            if areTextsSimilar(recentTexts[i], recentTexts[i + 1]) {
                similarPairs += 1
            }
        }

        return Double(similarPairs) / Double(recentTexts.count - 1)
    }

    private func areTextsSimilar(_ text1: String, _ text2: String) -> Bool {
        // Simple check: same prefix (editing end of text)
        let minLength = min(text1.count, text2.count)
        guard minLength > 10 else { return false }

        let prefixLength = Int(Double(minLength) * 0.8)
        let prefix1 = String(text1.prefix(prefixLength))
        let prefix2 = String(text2.prefix(prefixLength))

        return prefix1 == prefix2
    }

    private func calculateNavigationSignal() -> Double {
        let cutoff = Date().addingTimeInterval(-configuration.navigationWindowSeconds)
        let recentScrolls = scrollEvents.filter { $0 > cutoff }

        // Rapid scrolling indicates searching
        return min(Double(recentScrolls.count) / 5.0, 1.0)
    }

    private func updateFlowState() {
        if stuckScore >= configuration.stuckThreshold {
            flowState = .stuck
        } else if stuckScore >= configuration.flowThreshold {
            flowState = .paused
        } else if screenObserver?.isInDistraction == true {
            flowState = .distracted
        } else if lastTypingTime != nil &&
                  Date().timeIntervalSince(lastTypingTime!) < 5 {
            flowState = .flowing
        } else {
            flowState = .unknown
        }
    }

    // MARK: - Trigger Decision

    /// Check if we should proactively help
    func shouldTriggerHelp() -> (should: Bool, type: StuckType?) {
        // Check cooldown
        if let lastTrigger = lastTriggerTime,
           Date().timeIntervalSince(lastTrigger) < configuration.cooldownPeriod {
            return (false, nil)
        }

        // Don't interrupt flowing state
        guard flowState.shouldInterrupt else {
            return (false, nil)
        }

        // Check if stuck enough
        guard isLikelyStuck else {
            return (false, nil)
        }

        // Determine stuck type
        let stuckType = determineStuckType()

        return (true, stuckType)
    }

    private func determineStuckType() -> StuckType {
        // Find dominant signal
        let signals = [
            (type: StuckType.pause, value: currentSignals.pauseSignal),
            (type: StuckType.distraction, value: currentSignals.distractionSignal),
            (type: StuckType.rewriting, value: currentSignals.rewritingSignal),
            (type: StuckType.searching, value: currentSignals.navigationSignal)
        ]

        return signals.max(by: { $0.value < $1.value })?.type ?? .pause
    }

    /// Record that help was triggered (for cooldown)
    func recordHelpTriggered() {
        lastTriggerTime = Date()
    }

    // MARK: - Reset

    /// Reset all signals (e.g., when starting new session)
    func reset() {
        stuckScore = 0
        isLikelyStuck = false
        currentSignals = .init()
        flowState = .unknown
        lastTypingTime = nil
        lastTextLength = 0
        deletionCount = 0
        deletionWindow = []
        scrollEvents = []
        textHistory = []
        lastTriggerTime = nil
    }
}

// MARK: - Score Interpretation

extension StuckDetector {
    /// Interpret current stuck score
    var scoreInterpretation: String {
        switch stuckScore {
        case 0..<0.3:
            return "Normal flow - no intervention needed"
        case 0.3..<0.5:
            return "Possible pause - preparing suggestion"
        case 0.5..<0.7:
            return "Likely stuck - subtle indicator shown"
        case 0.7...1.0:
            return "Definitely stuck - proactive suggestion"
        default:
            return "Unknown"
        }
    }

    /// Get appropriate assistance level
    var assistanceLevel: AssistanceLevel {
        switch stuckScore {
        case 0..<0.3:
            return .none
        case 0.3..<0.5:
            return .subtle
        case 0.5..<0.7:
            return .moderate
        case 0.7...1.0:
            return .proactive
        default:
            return .none
        }
    }

    enum AssistanceLevel {
        case none
        case subtle      // Small indicator that help is available
        case moderate    // More visible indicator
        case proactive   // Auto-show suggestion

        var description: String {
            switch self {
            case .none: return "No assistance"
            case .subtle: return "Help available"
            case .moderate: return "Showing suggestions"
            case .proactive: return "Proactive help"
            }
        }
    }
}
