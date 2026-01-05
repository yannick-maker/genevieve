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

    // MARK: - Storage

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Configuration

    private var analysisDebouncer: Task<Void, Never>?
    private let analysisDebounceInterval: TimeInterval = 1.0
    private var lastAnalyzedText: String?

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

        // Observe writing state
        focusedElementDetector.$isWriting
            .removeDuplicates()
            .sink { [weak self] isWriting in
                if isWriting {
                    self?.startSessionIfNeeded()
                } else {
                    self?.pauseSession()
                }
            }
            .store(in: &cancellables)

        // Observe stuck state
        stuckDetector.$isLikelyStuck
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.handleStuckState()
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
            onAccept: { [weak self] suggestion in
                self?.acceptSuggestion(suggestion)
            },
            onReject: { [weak self] suggestion in
                self?.rejectSuggestion(suggestion)
            },
            onCopy: { [weak self] suggestion in
                self?.copySuggestion(suggestion)
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
        // Debounce analysis
        analysisDebouncer?.cancel()

        analysisDebouncer = Task {
            try? await Task.sleep(for: .seconds(analysisDebounceInterval))
            guard !Task.isCancelled else { return }

            await analyzeContext(context)
        }

        // Update stuck detector
        if let text = context.selectedText ?? context.surroundingText {
            stuckDetector.recordTyping(currentLength: text.count)
            stuckDetector.recordTextContent(text)
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

        _ = await draftingAssistant.generateSuggestions(for: generationContext)

        // Show sidebar if we have suggestions
        if !draftingAssistant.currentSuggestions.isEmpty {
            showSidebar()
        }

        state = .displaying
    }

    // MARK: - Stuck Handling

    private func handleStuckState() {
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

        _ = await draftingAssistant.generateSuggestions(for: generationContext)

        if !draftingAssistant.currentSuggestions.isEmpty {
            showSidebar()
            sidebarController.bounceForNewSuggestion()
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
        Task {
            try? await Task.sleep(for: .seconds(2))
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
