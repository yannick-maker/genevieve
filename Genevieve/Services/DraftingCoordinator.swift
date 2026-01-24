import Foundation
import SwiftUI
import SwiftData
import Combine

/// Central orchestrator that coordinates all Genevieve services
/// Manages the flow from screen observation → context analysis → suggestion generation → UI
@MainActor
final class DraftingCoordinator: ObservableObject {
    // MARK: - Published State

    @Published private(set) var isActive = false
    @Published private(set) var currentSession: WritingSession?
    @Published private(set) var currentMatter: Matter?
    @Published private(set) var state: CoordinatorState = .idle

    enum CoordinatorState {
        case idle
        case observing
        case analyzing
        case generating
        case displaying
        case error(String)
    }

    // MARK: - Services

    let aiService: AIProviderService
    let screenObserver: ScreenObserver
    let textService: AccessibilityTextService
    let focusedElementDetector: FocusedElementDetector
    let contextAnalyzer: ContextAnalyzer
    let stuckDetector: StuckDetector
    let draftingAssistant: DraftingAssistant
    let sidebarController: GenevieveSidebarController
    let commentaryService: CommentaryService
    let metricsCollector: WritingMetricsCollector

    // MARK: - Storage

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Configuration

    private var analysisDebouncer: Task<Void, Never>?
    private let analysisDebounceInterval: TimeInterval = 1.0
    private var lastAnalyzedText: String?
    private var lastWritingContextBeforeSwitch: FocusedElementDetector.WritingContext?
    private var isInAppSwitch = false
    private var appSwitchStartTime: Date?

    // MARK: - Screen Observation for Commentary

    private var screenObservationTimer: Timer?
    private let screenObservationInterval: TimeInterval = 5.0 // Check every 5 seconds
    private var lastWindowContentHash: Int?
    private var lastCommentaryTime: Date?
    private let minimumCommentaryInterval: TimeInterval = 15.0 // Minimum 15s between commentary

    // MARK: - Initialization

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext

        // Initialize services
        self.aiService = AIProviderService()
        self.screenObserver = ScreenObserver()
        self.textService = AccessibilityTextService.shared
        self.focusedElementDetector = FocusedElementDetector(textService: textService)
        self.contextAnalyzer = ContextAnalyzer(aiService: aiService)
        self.stuckDetector = StuckDetector()
        self.draftingAssistant = DraftingAssistant(aiService: aiService)
        self.sidebarController = GenevieveSidebarController()
        self.commentaryService = CommentaryService(aiService: aiService, modelContext: modelContext)
        self.metricsCollector = WritingMetricsCollector()

        // Set model context for commentary persistence
        if let context = modelContext {
            commentaryService.setModelContext(context)
        }

        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Connect stuck detector to screen observer
        stuckDetector.connect(to: screenObserver)

        // Observe focused element changes
        focusedElementDetector.$currentContext
            .compactMap { $0 }
            .sink { [weak self] context in
                self?.handleContextChange(context)
            }
            .store(in: &cancellables)

        // Observe writing state (only pause if not in app switch with commentary active)
        focusedElementDetector.$isWriting
            .removeDuplicates()
            .sink { [weak self] isWriting in
                guard let self = self else { return }
                if isWriting {
                    self.isInAppSwitch = false
                    self.startSessionIfNeeded()
                } else if !self.isInAppSwitch || !self.commentaryService.isEnabled {
                    self.pauseSession()
                }
            }
            .store(in: &cancellables)

        // Handle app switching - preserve commentary context
        screenObserver.onAppSwitch = { [weak self] change in
            guard let self = self else { return }
            self.handleAppSwitch(from: change.fromApp, to: change.toApp)
        }

        screenObserver.onReturnToWork = { [weak self] app in
            guard let self = self else { return }
            self.handleReturnToWork(app: app)
        }

        // Observe stuck state
        stuckDetector.$isLikelyStuck
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.handleStuckState()
            }
            .store(in: &cancellables)

        // Observe commentary mode changes - sync with CommentaryService
        draftingAssistant.$commentaryModeEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self = self else { return }
                self.commentaryService.isEnabled = isEnabled

                if isEnabled {
                    self.metricsCollector.startCollecting()
                    self.commentaryService.setCurrentSession(self.currentSession)
                    self.commentaryService.setCurrentMatter(self.currentMatter)
                    self.startScreenObservation()
                } else {
                    self.metricsCollector.stopCollecting()
                    self.stopScreenObservation()
                }
            }
            .store(in: &cancellables)

        // Observe stuck state for commentary integration
        stuckDetector.$isLikelyStuck
            .combineLatest(stuckDetector.$currentSignals)
            .sink { [weak self] (isStuck, signals) in
                guard let self = self else { return }
                if isStuck {
                    // Determine dominant stuck type from signals
                    let stuckType = self.determineDominantStuckType(signals)
                    self.commentaryService.setStuckState(stuckType)
                } else {
                    self.commentaryService.setStuckState(nil)
                }
            }
            .store(in: &cancellables)

        // Setup sidebar panel content
        setupSidebar()
    }

    private func setupSidebar() {
        let panelContent = SuggestionPanelView(
            draftingAssistant: draftingAssistant,
            sidebarController: sidebarController,
            contextAnalyzer: contextAnalyzer,
            commentaryService: commentaryService,
            metricsCollector: metricsCollector,
            onAccept: { [weak self] suggestion in
                self?.acceptSuggestion(suggestion)
            },
            onReject: { [weak self] suggestion in
                self?.rejectSuggestion(suggestion)
            },
            onCopy: { [weak self] suggestion in
                self?.copySuggestion(suggestion)
            },
            onSendMessage: { [weak self] message in
                await self?.sendUserMessage(message)
            }
        )

        sidebarController.setup(with: panelContent)
        sidebarController.registerGlobalShortcuts()
    }

    // MARK: - Lifecycle

    /// Start coordinating all services
    func start() async {
        guard !isActive else { return }

        // Initialize AI service
        await aiService.initialize()

        // Start observation services
        screenObserver.startObserving()
        focusedElementDetector.startDetecting()
        stuckDetector.startMonitoring()

        isActive = true
        state = .observing
    }

    /// Stop all services
    func stop() {
        guard isActive else { return }

        screenObserver.stopObserving()
        focusedElementDetector.stopDetecting()
        stuckDetector.stopMonitoring()

        endCurrentSession()

        isActive = false
        state = .idle
    }

    // MARK: - Context Handling

    private func handleContextChange(_ context: FocusedElementDetector.WritingContext) {
        // Update metrics collector if active
        if let text = context.selectedText ?? context.surroundingText {
            metricsCollector.recordTyping(currentLength: text.count)
            stuckDetector.recordTyping(currentLength: text.count)
            stuckDetector.recordTextContent(text)
        }

        // Use shorter debounce for commentary mode (more continuous feel)
        let debounceInterval = commentaryService.isEnabled ? 0.5 : analysisDebounceInterval

        // Debounce analysis
        analysisDebouncer?.cancel()

        analysisDebouncer = Task {
            try? await Task.sleep(for: .seconds(debounceInterval))
            guard !Task.isCancelled else { return }

            await analyzeContext(context)
        }
    }

    private func analyzeContext(_ context: FocusedElementDetector.WritingContext) async {
        let textToAnalyze = context.selectedText ?? context.surroundingText

        // Skip if same text
        guard textToAnalyze != lastAnalyzedText else { return }
        lastAnalyzedText = textToAnalyze

        state = .analyzing

        // Analyze document context
        _ = await contextAnalyzer.analyze(context: context)

        // Commentary mode takes precedence over suggestions
        if commentaryService.isEnabled {
            await generateCommentaryWithService(for: context)
            state = .observing
            return
        }

        // Check if we should generate suggestions
        if shouldGenerateSuggestions() {
            await generateSuggestions(for: context)
        }

        state = .observing
    }

    private func shouldGenerateSuggestions() -> Bool {
        // Need sufficient context
        guard focusedElementDetector.hasEnoughContext else { return false }

        // Need AI service configured
        guard aiService.hasAnyProvider else { return false }

        // Check if user is stuck or has been writing for a while
        if stuckDetector.isLikelyStuck { return true }

        // Proactive suggestion based on typing patterns
        // Could add more heuristics here

        return false
    }

    private func generateSuggestions(for context: FocusedElementDetector.WritingContext) async {
        state = .generating

        let generationContext = DraftingAssistant.GenerationContext(
            text: context.surroundingText ?? "",
            selectedText: context.selectedText,
            documentType: contextAnalyzer.currentAnalysis?.documentType ?? .unknown,
            section: contextAnalyzer.currentAnalysis?.section ?? .unknown,
            tone: contextAnalyzer.currentAnalysis?.tone ?? .neutral,
            triggerReason: stuckDetector.isLikelyStuck ? .stuckDetected : .proactive
        )

        // Show sidebar immediately so user sees streaming progress
        showSidebar()

        // Use streaming generation for progressive updates
        await draftingAssistant.generateSuggestionsStreaming(for: generationContext)

        // Hide sidebar if generation completed with no suggestions
        if draftingAssistant.currentSuggestions.isEmpty && !draftingAssistant.isStreaming {
            hideSidebarAfterDelay()
        }

        state = .displaying
    }

    private func generateCommentary(for context: FocusedElementDetector.WritingContext) async {
        guard aiService.hasAnyProvider else { return }

        state = .generating

        let generationContext = DraftingAssistant.GenerationContext(
            text: context.surroundingText ?? "",
            selectedText: context.selectedText,
            documentType: contextAnalyzer.currentAnalysis?.documentType ?? .unknown,
            section: contextAnalyzer.currentAnalysis?.section ?? .unknown,
            tone: contextAnalyzer.currentAnalysis?.tone ?? .neutral,
            triggerReason: .proactive
        )

        showSidebar()
        await draftingAssistant.generateCommentaryStreaming(for: generationContext)

        state = .displaying
    }

    /// Generate commentary using the new CommentaryService (with persistence and dialogue support)
    private func generateCommentaryWithService(for context: FocusedElementDetector.WritingContext) async {
        guard aiService.hasAnyProvider else { return }

        state = .generating
        showSidebar()

        // Update metrics
        if let text = context.selectedText ?? context.surroundingText {
            metricsCollector.recordTyping(currentLength: text.count)
        }

        await commentaryService.generateCommentary(
            text: context.surroundingText ?? "",
            selectedText: context.selectedText,
            documentType: contextAnalyzer.currentAnalysis?.documentType.rawValue ?? "Unknown",
            documentSection: contextAnalyzer.currentAnalysis?.section?.rawValue ?? "Unknown",
            tone: contextAnalyzer.currentAnalysis?.tone.rawValue ?? "Neutral",
            appName: context.appName,
            windowTitle: context.windowTitle
        )

        state = .displaying
    }

    /// Determine the dominant stuck type from current signals
    private func determineDominantStuckType(_ signals: StuckDetector.StuckSignals) -> String {
        let signalValues = [
            ("pause", signals.pauseSignal),
            ("distraction", signals.distractionSignal),
            ("rewriting", signals.rewritingSignal),
            ("navigation", signals.navigationSignal)
        ]

        let dominant = signalValues.max(by: { $0.1 < $1.1 })
        return dominant?.0 ?? "pause"
    }

    /// Send a user message for dialogue
    func sendUserMessage(_ message: String) async {
        let windowContent = textService.getWindowContent()
        let context = windowContent?.visibleText ?? focusedElementDetector.currentContext?.surroundingText
        await commentaryService.sendUserMessage(message, context: context)
    }

    // MARK: - Screen Observation for Commentary

    /// Start observing the screen for commentary mode (not dependent on text field focus)
    private func startScreenObservation() {
        stopScreenObservation()

        // Immediately generate commentary for current screen
        Task { @MainActor in
            await self.observeScreenAndGenerateCommentary()
        }

        // Start periodic observation
        screenObservationTimer = Timer.scheduledTimer(withTimeInterval: screenObservationInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.observeScreenAndGenerateCommentary()
            }
        }
    }

    /// Stop screen observation
    private func stopScreenObservation() {
        screenObservationTimer?.invalidate()
        screenObservationTimer = nil
        lastWindowContentHash = nil
        lastCommentaryTime = nil
    }

    /// Observe the current screen and generate commentary if content has changed
    private func observeScreenAndGenerateCommentary() async {
        guard commentaryService.isEnabled else { return }
        guard aiService.hasAnyProvider else { return }

        // Get current window content
        guard let windowContent = textService.getWindowContent() else { return }

        // Check if content has changed significantly
        let currentHash = windowContent.contentHash
        let contentChanged = lastWindowContentHash != currentHash
        lastWindowContentHash = currentHash

        // Check minimum time interval between commentary
        let timeSinceLastCommentary = lastCommentaryTime.map { Date().timeIntervalSince($0) } ?? .infinity
        let enoughTimePassed = timeSinceLastCommentary >= minimumCommentaryInterval

        // Only generate if content changed and enough time has passed (or it's the first time)
        guard contentChanged || lastCommentaryTime == nil else { return }
        guard enoughTimePassed else { return }

        // Generate commentary based on visible screen content
        await generateCommentaryFromScreen(windowContent)
        lastCommentaryTime = Date()
    }

    /// Generate commentary from screen observation (not dependent on text field)
    private func generateCommentaryFromScreen(_ windowContent: AccessibilityTextService.WindowContentInfo) async {
        guard aiService.hasAnyProvider else { return }

        state = .generating
        showSidebar()

        // Try to analyze what type of content this is
        let docType = contextAnalyzer.currentAnalysis?.documentType.rawValue ?? inferDocumentType(from: windowContent)

        await commentaryService.generateCommentary(
            text: windowContent.visibleText,
            selectedText: nil,
            documentType: docType,
            documentSection: "Unknown",
            tone: "Neutral",
            appName: windowContent.appName,
            windowTitle: windowContent.windowTitle
        )

        state = .displaying
    }

    /// Infer document type from window content and app name
    private func inferDocumentType(from content: AccessibilityTextService.WindowContentInfo) -> String {
        let text = content.visibleText.lowercased()
        let app = content.appName.lowercased()

        // Check app-based hints
        if app.contains("word") || app.contains("pages") || app.contains("docs") {
            if text.contains("whereas") || text.contains("hereby") || text.contains("party") {
                return "Contract"
            }
            if text.contains("court") || text.contains("plaintiff") || text.contains("defendant") {
                return "Court Filing"
            }
            if text.contains("dear") || text.contains("sincerely") {
                return "Letter"
            }
            return "Document"
        }

        if app.contains("mail") || app.contains("outlook") {
            return "Email"
        }

        if app.contains("browser") || app.contains("chrome") || app.contains("safari") || app.contains("firefox") {
            return "Web Content"
        }

        return "Unknown"
    }

    // MARK: - App Switching

    private func handleAppSwitch(from: ScreenObserver.AppInfo?, to: ScreenObserver.AppInfo) {
        // Only track if commentary is active
        guard commentaryService.isEnabled else { return }

        // Save the current context before switching
        if let context = focusedElementDetector.currentContext {
            lastWritingContextBeforeSwitch = context
        }

        isInAppSwitch = true
        appSwitchStartTime = Date()

        // Record app switch in metrics
        metricsCollector.recordAppSwitch(
            appName: to.name,
            duration: 0 // Duration unknown until return
        )

        // Don't cancel commentary - let it continue streaming if in progress
        // The context is preserved in lastWritingContextBeforeSwitch
    }

    private func handleReturnToWork(app: ScreenObserver.AppInfo) {
        guard commentaryService.isEnabled else { return }

        // Calculate time spent away
        let timeAway = appSwitchStartTime.map { Date().timeIntervalSince($0) } ?? 0

        isInAppSwitch = false
        appSwitchStartTime = nil

        // Record the app switch duration
        if timeAway > 0 {
            metricsCollector.recordAppSwitch(appName: app.name, duration: timeAway)
        }

        // If we have saved context and user returns to writing, resume naturally
        // The commentary will pick up from the next context change
        // No need to force a new generation - just let the normal flow continue

        // If user was away for a while (> 30 seconds), acknowledge their return
        if timeAway > 30, let context = focusedElementDetector.currentContext ?? lastWritingContextBeforeSwitch {
            Task { @MainActor in
                // Trigger a gentle refresh of commentary to acknowledge the return
                await self.generateCommentaryWithService(for: context)
            }
        }

        lastWritingContextBeforeSwitch = nil
    }

    // MARK: - Stuck Handling

    private func handleStuckState() {
        guard !draftingAssistant.commentaryModeEnabled else { return }
        let (shouldTrigger, stuckType) = stuckDetector.shouldTriggerHelp()

        guard shouldTrigger else { return }

        // Generate context-aware help
        Task {
            if let context = focusedElementDetector.currentContext {
                await generateStuckHelp(for: context, stuckType: stuckType)
            }
        }

        stuckDetector.recordHelpTriggered()
    }

    private func generateStuckHelp(
        for context: FocusedElementDetector.WritingContext,
        stuckType: StuckDetector.StuckType?
    ) async {
        let generationContext = DraftingAssistant.GenerationContext(
            text: context.surroundingText ?? "",
            selectedText: context.selectedText,
            documentType: contextAnalyzer.currentAnalysis?.documentType ?? .unknown,
            section: contextAnalyzer.currentAnalysis?.section ?? .unknown,
            tone: contextAnalyzer.currentAnalysis?.tone ?? .neutral,
            triggerReason: .stuckDetected
        )

        // Show sidebar immediately with bounce to get attention
        showSidebar()
        sidebarController.bounceForNewSuggestion()

        // Use streaming generation
        await draftingAssistant.generateSuggestionsStreaming(for: generationContext)

        // Hide sidebar if no suggestions after completion
        if draftingAssistant.currentSuggestions.isEmpty && !draftingAssistant.isStreaming {
            hideSidebarAfterDelay()
        }
    }

    // MARK: - Suggestion Actions

    private func acceptSuggestion(_ suggestion: DraftingAssistant.DraftSuggestionData) {
        let textToInsert = draftingAssistant.acceptSuggestion(suggestion)

        // Insert text
        let result = textService.insertText(textToInsert)

        // Track in session
        currentSession?.recordSuggestionAccepted()

        // Save suggestion to database
        saveSuggestion(suggestion, status: .accepted)

        // Log result
        switch result {
        case .success:
            break
        case .fallbackToClipboard:
            // Already inserted via clipboard
            break
        case .noFocusedElement, .accessDenied, .insertionFailed:
            // Copy to clipboard as fallback
            textService.copyToClipboard(textToInsert)
        }

        // Hide sidebar if no more suggestions
        if draftingAssistant.currentSuggestions.isEmpty {
            hideSidebarAfterDelay()
        }
    }

    private func rejectSuggestion(_ suggestion: DraftingAssistant.DraftSuggestionData) {
        draftingAssistant.rejectSuggestion(suggestion)
        currentSession?.recordSuggestionRejected()
        saveSuggestion(suggestion, status: .rejected)

        if draftingAssistant.currentSuggestions.isEmpty {
            hideSidebarAfterDelay()
        }
    }

    private func copySuggestion(_ suggestion: DraftingAssistant.DraftSuggestionData) {
        textService.copyToClipboard(suggestion.suggestedText)
        // Don't mark as accepted - user may still be reviewing
    }

    // MARK: - Sidebar Control

    func showSidebar() {
        sidebarController.show()
    }

    func hideSidebar() {
        sidebarController.hide()
    }

    func toggleSidebar() {
        sidebarController.toggle()
    }

    private func hideSidebarAfterDelay() {
        // Don't auto-hide when commentary mode is active - sidebar should stay visible
        guard !draftingAssistant.commentaryModeEnabled else { return }

        Task {
            try? await Task.sleep(for: .seconds(2))
            // Double-check commentary mode hasn't been enabled during the delay
            guard !draftingAssistant.commentaryModeEnabled else { return }
            if draftingAssistant.currentSuggestions.isEmpty {
                hideSidebar()
            }
        }
    }

    // MARK: - Session Management

    private func startSessionIfNeeded() {
        guard currentSession == nil || currentSession?.isActive == false else { return }

        let context = focusedElementDetector.currentContext

        let session = WritingSession(
            documentType: context?.documentType?.rawValue,
            documentTitle: context?.windowTitle,
            appBundleID: context?.appBundleID,
            appName: context?.appName
        )

        currentSession = session

        // Detect matter
        detectMatter(for: context)

        // Save to database
        modelContext?.insert(session)
        try? modelContext?.save()
    }

    private func pauseSession() {
        // Keep session active but note the pause
    }

    private func endCurrentSession() {
        guard let session = currentSession else { return }

        session.end()

        try? modelContext?.save()
        currentSession = nil
    }

    // MARK: - Matter Detection

    private func detectMatter(for context: FocusedElementDetector.WritingContext?) {
        guard let context = context, let modelContext = modelContext else { return }

        // Try to find matching matter
        let descriptor = FetchDescriptor<Matter>(
            predicate: #Predicate<Matter> { $0.status == "active" }
        )

        guard let matters = try? modelContext.fetch(descriptor) else { return }

        for matter in matters {
            if matter.matches(documentTitle: context.windowTitle, windowTitle: context.windowTitle) {
                currentMatter = matter
                currentSession?.matter = matter
                return
            }
        }
    }

    // MARK: - Persistence

    private func saveSuggestion(
        _ data: DraftingAssistant.DraftSuggestionData,
        status: DraftSuggestion.SuggestionStatus
    ) {
        guard let modelContext = modelContext else { return }

        let suggestion = DraftSuggestion(
            originalText: data.originalText,
            suggestedText: data.suggestedText,
            explanation: data.explanation,
            documentType: contextAnalyzer.currentAnalysis?.documentType.rawValue,
            sectionType: contextAnalyzer.currentAnalysis?.section?.rawValue,
            confidence: data.confidence
        )

        suggestion.suggestionStatus = status
        suggestion.session = currentSession
        suggestion.matter = currentMatter

        modelContext.insert(suggestion)
        try? modelContext.save()
    }

    // MARK: - Keyboard Shortcuts

    func handleKeyboardShortcut(_ shortcut: KeyboardShortcut) {
        switch shortcut {
        case .toggleSidebar:
            toggleSidebar()
        case .acceptSuggestion:
            if let first = draftingAssistant.currentSuggestions.first {
                acceptSuggestion(first)
            }
        case .dismissSuggestion:
            if let first = draftingAssistant.currentSuggestions.first {
                rejectSuggestion(first)
            }
        case .nextSuggestion, .previousSuggestion:
            // Handled by UI
            break
        }
    }

    enum KeyboardShortcut {
        case toggleSidebar      // Cmd+Shift+G
        case acceptSuggestion   // Tab
        case dismissSuggestion  // Esc
        case nextSuggestion     // Down arrow
        case previousSuggestion // Up arrow
    }
}

// MARK: - Statistics

extension DraftingCoordinator {
    /// Get session statistics
    var sessionStats: SessionStats {
        guard let session = currentSession else {
            return SessionStats()
        }

        return SessionStats(
            duration: session.duration,
            suggestionsShown: session.suggestionsShown,
            suggestionsAccepted: session.suggestionsAccepted,
            acceptanceRate: session.acceptanceRate,
            focusScore: session.focusScore
        )
    }

    struct SessionStats {
        var duration: TimeInterval = 0
        var suggestionsShown: Int = 0
        var suggestionsAccepted: Int = 0
        var acceptanceRate: Double = 0
        var focusScore: Double?
    }
}
