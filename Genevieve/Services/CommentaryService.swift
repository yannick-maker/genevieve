import Foundation
import SwiftData
import Combine

/// Service managing Genevieve's commentary lifecycle - generation, persistence, dialogue, and memory
@MainActor
final class CommentaryService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var currentSessionEntries: [CommentaryEntry] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var streamingProgress: StreamingProgress = .idle
    @Published private(set) var currentStreamingText: String = ""

    @Published var isEnabled: Bool = false {
        didSet {
            if !isEnabled {
                cancelCurrentGeneration()
            }
        }
    }

    enum StreamingProgress: Equatable {
        case idle
        case starting
        case streaming
        case complete
        case error(String)

        var isError: Bool {
            if case .error = self { return true }
            return false
        }

        var errorMessage: String? {
            if case .error(let msg) = self { return msg }
            return nil
        }
    }

    // MARK: - Dependencies

    private let aiService: AIProviderService
    private var modelContext: ModelContext?
    private var generationTask: Task<Void, Never>?

    // MARK: - Configuration

    private let minTextLength = 30
    private let cooldownInterval: TimeInterval = 2.0 // Reduced from 8s for more continuous feel
    private var lastGenerationTime: Date?
    private var lastTextKey: String?

    // MARK: - Context

    private(set) var currentMatter: Matter?
    private(set) var currentSession: WritingSession?
    private(set) var userProfile: UserWritingProfile?
    private(set) var stuckState: String?
    private(set) var relevantArguments: [Argument] = []

    // MARK: - Initialization

    init(aiService: AIProviderService, modelContext: ModelContext? = nil) {
        self.aiService = aiService
        self.modelContext = modelContext
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadUserProfile()
    }

    // MARK: - Context Management

    func setCurrentMatter(_ matter: Matter?) {
        self.currentMatter = matter
    }

    func setCurrentSession(_ session: WritingSession?) {
        self.currentSession = session
        if session != nil {
            loadSessionEntries()
        }
    }

    func setStuckState(_ state: String?) {
        self.stuckState = state
    }

    func setRelevantArguments(_ arguments: [Argument]) {
        self.relevantArguments = arguments
    }

    /// Find and set relevant arguments based on current matter and document context
    func updateRelevantArguments(from matter: Matter?, documentType: String?) {
        guard let matter = matter, let arguments = matter.arguments else {
            relevantArguments = []
            return
        }

        // Filter to most relevant arguments (limit to 3)
        relevantArguments = Array(arguments.prefix(3))
    }

    // MARK: - User Profile

    private func loadUserProfile() {
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<UserWritingProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        if let profiles = try? modelContext.fetch(descriptor), let profile = profiles.first {
            self.userProfile = profile
        } else {
            // Create new profile
            let newProfile = UserWritingProfile()
            modelContext.insert(newProfile)
            try? modelContext.save()
            self.userProfile = newProfile
        }
    }

    // MARK: - Session Entries

    private func loadSessionEntries() {
        guard let modelContext = modelContext, let session = currentSession else {
            currentSessionEntries = []
            return
        }

        let sessionId = session.id
        let descriptor = FetchDescriptor<CommentaryEntry>(
            predicate: #Predicate<CommentaryEntry> { entry in
                entry.session?.id == sessionId
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        currentSessionEntries = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Commentary Generation

    /// Generate commentary for the current writing context
    func generateCommentary(
        text: String,
        selectedText: String? = nil,
        documentType: String,
        documentSection: String,
        tone: String,
        appName: String? = nil,
        windowTitle: String? = nil
    ) async {
        guard isEnabled else { return }
        guard aiService.hasAnyProvider else { return }

        let textToAnalyze = selectedText ?? text
        guard textToAnalyze.count >= minTextLength else { return }

        // Check cooldown and redundancy
        let key = textKey(for: textToAnalyze)
        if let lastTime = lastGenerationTime,
           Date().timeIntervalSince(lastTime) < cooldownInterval,
           key == lastTextKey {
            return
        }

        lastTextKey = key
        lastGenerationTime = Date()

        // Cancel any existing generation
        cancelCurrentGeneration()

        isStreaming = true
        streamingProgress = .starting
        currentStreamingText = ""

        generationTask = Task {
            await performGeneration(
                text: textToAnalyze,
                documentType: documentType,
                documentSection: documentSection,
                tone: tone,
                appName: appName,
                windowTitle: windowTitle
            )
        }
    }

    private func performGeneration(
        text: String,
        documentType: String,
        documentSection: String,
        tone: String,
        appName: String?,
        windowTitle: String?
    ) async {
        let prompt = buildPrompt(text: text)
        let systemPrompt = buildSystemPrompt(
            documentType: documentType,
            documentSection: documentSection,
            tone: tone
        )

        streamingProgress = .streaming
        var buffer = ""

        do {
            let stream = aiService.generateStream(
                prompt: prompt,
                systemPrompt: systemPrompt,
                task: .commentary
            )

            for try await chunk in stream {
                guard !Task.isCancelled else { break }
                buffer += chunk
                currentStreamingText = buffer
            }

            guard !Task.isCancelled else { return }

            // Create and save entry
            let entry = CommentaryEntry(
                content: buffer,
                isUserMessage: false,
                documentType: documentType,
                documentSection: documentSection,
                appName: appName,
                windowTitle: windowTitle
            )

            entry.session = currentSession
            entry.matter = currentMatter
            entry.stuckType = stuckState
            entry.extractSuggestion()

            // Add metadata
            var metadata = CommentaryEntry.Metadata()
            metadata.focusScore = currentSession?.focusScore
            entry.metadata = metadata

            saveEntry(entry)
            currentSessionEntries.append(entry)

            // Update user profile
            userProfile?.recordCommentaryEntry(isUserMessage: false)
            try? modelContext?.save()

            streamingProgress = .complete

        } catch {
            streamingProgress = .error(error.localizedDescription)
        }

        isStreaming = false
    }

    // MARK: - User Dialogue

    /// Send a user message and get Genevieve's response
    func sendUserMessage(_ message: String, context: String? = nil) async {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Save user message
        let userEntry = CommentaryEntry(
            content: message,
            isUserMessage: true
        )
        userEntry.session = currentSession
        userEntry.matter = currentMatter
        saveEntry(userEntry)
        currentSessionEntries.append(userEntry)

        userProfile?.recordCommentaryEntry(isUserMessage: true)

        // Generate response
        isStreaming = true
        streamingProgress = .starting
        currentStreamingText = ""

        let prompt = buildDialoguePrompt(userMessage: message, context: context)
        let systemPrompt = buildDialogueSystemPrompt()

        streamingProgress = .streaming
        var buffer = ""

        do {
            let stream = aiService.generateStream(
                prompt: prompt,
                systemPrompt: systemPrompt,
                task: .commentary
            )

            for try await chunk in stream {
                guard !Task.isCancelled else { break }
                buffer += chunk
                currentStreamingText = buffer
            }

            guard !Task.isCancelled else { return }

            let responseEntry = CommentaryEntry(
                content: buffer,
                isUserMessage: false
            )
            responseEntry.session = currentSession
            responseEntry.matter = currentMatter
            responseEntry.extractSuggestion()
            saveEntry(responseEntry)
            currentSessionEntries.append(responseEntry)

            userProfile?.recordCommentaryEntry(isUserMessage: false)
            try? modelContext?.save()

            streamingProgress = .complete

        } catch {
            streamingProgress = .error(error.localizedDescription)
        }

        isStreaming = false
    }

    // MARK: - Prompt Building

    private func buildPrompt(text: String) -> String {
        let trimmedText = String(text.prefix(1000))
        let priorContext = recentEntriesContext(limit: 3)

        return """
        Observe this writing and provide your commentary.

        Draft excerpt:
        ---
        \(trimmedText)
        ---

        \(priorContext.isEmpty ? "" : "Prior commentary for continuity:\n\(priorContext)")
        """
    }

    private func buildSystemPrompt(documentType: String, documentSection: String, tone: String) -> String {
        // Use the Genevieve persona prompt from DraftingPrompts
        var matterContext: String? = nil
        if let matter = currentMatter {
            var parts: [String] = []
            parts.append("Matter: \(matter.name)")
            if let client = matter.clientName { parts.append("Client: \(client)") }
            if let number = matter.matterNumber { parts.append("Number: \(number)") }
            if let type = matter.matterType { parts.append("Type: \(type)") }

            // Add relevant arguments from library
            if !relevantArguments.isEmpty {
                parts.append("\nRelevant arguments from library:")
                for arg in relevantArguments.prefix(3) {
                    parts.append("- \(arg.title): \(String(arg.content.prefix(100)))...")
                }
            }

            matterContext = parts.joined(separator: "\n")
        }

        let profileContext = userProfile?.contextSummary(maxLength: 300)

        // Add narrative memory from recent sessions
        let narrativeContext = narrativeContextSummary()

        // Build Genevieve prompt with context
        var fullProfileContext = profileContext ?? ""
        if !narrativeContext.isEmpty {
            fullProfileContext += "\n\n" + narrativeContext
        }

        return buildGenevieveSystemPrompt(
            documentType: documentType,
            documentSection: documentSection,
            tone: tone,
            matterContext: matterContext,
            userProfile: fullProfileContext.isEmpty ? nil : fullProfileContext,
            stuckState: stuckState
        )
    }

    /// Get a narrative context summary from recent sessions for memory
    private func narrativeContextSummary() -> String {
        let memory = loadNarrativeMemory(daysBack: 7, limit: 5)
        guard !memory.isEmpty else { return "" }

        var summary = "From recent sessions:\n"
        for entry in memory {
            let snippet = String(entry.content.prefix(80)).replacingOccurrences(of: "\n", with: " ")
            summary += "- \(snippet)...\n"
        }

        return summary
    }

    private func buildGenevieveSystemPrompt(
        documentType: String,
        documentSection: String,
        tone: String,
        matterContext: String?,
        userProfile: String?,
        stuckState: String?
    ) -> String {
        var prompt = """
        You are Genevieve, a wise and experienced legal writing mentor with decades of practice.

        ## Your Personality
        - Wise and experienced, with a wry sense of humor
        - Precise, quick-witted, and detail-oriented
        - Goal-focused and effective
        - You speak like a senior partner who genuinely wants to help a promising associate grow
        - Direct but never harsh—you tell the truth because you respect the writer

        ## Your Role
        You observe the writer at work and provide flowing, insightful commentary. You are like a trusted colleague looking over their shoulder, offering observations, teaching moments, and suggestions naturally woven into your narrative.

        ## Style Guidelines
        - Write in present tense, reflective and conversational
        - Provide detailed paragraphs, not just a few sentences
        - Be very direct when you spot issues: "This argument is weak because..." or "I'd push back on this approach..."
        - Acknowledge struggles directly when you notice them
        - Weave in legal writing principles when relevant
        - Never quote the draft verbatim—paraphrase or describe instead
        - When you have a concrete suggestion, mark it with [SUGGESTION: your suggested text here]

        ## Current Context
        - Document type: \(documentType)
        - Section: \(documentSection)
        - Target tone: \(tone)
        """

        if let matter = matterContext {
            prompt += "\n\n## Matter Context\n\(matter)"
        }

        if let profile = userProfile {
            prompt += "\n\n## Writer Profile\n\(profile)"
        }

        if let stuck = stuckState {
            prompt += "\n\n## Current State\nThe writer appears to be \(stuck). Acknowledge this gently and offer guidance."
        }

        prompt += """


        ## Legal Writing Principles (reference when relevant)
        - Strong topic sentences that telegraph the argument
        - Rule synthesis before application
        - Concrete facts over abstract assertions
        - Active voice for clarity and impact
        - One idea per paragraph
        - Signposting for the reader's benefit
        - Addressing counterarguments preemptively

        Remember: You are Genevieve—confident, insightful, and genuinely invested in this writer's success.
        """

        return prompt
    }

    private func buildDialoguePrompt(userMessage: String, context: String?) -> String {
        let recentContext = recentEntriesContext(limit: 5)

        var prompt = """
        The writer has a question or comment for you:

        "\(userMessage)"
        """

        if let ctx = context {
            prompt += "\n\nCurrent draft context:\n\(ctx)"
        }

        if !recentContext.isEmpty {
            prompt += "\n\nRecent conversation:\n\(recentContext)"
        }

        return prompt
    }

    private func buildDialogueSystemPrompt() -> String {
        """
        You are Genevieve, responding to a direct question or comment from the writer.

        Be conversational, helpful, and direct. Reference earlier observations if relevant.
        If they ask about a suggestion, explain your reasoning.
        If they disagree with your feedback, engage thoughtfully—you may be wrong, or there may be context you're missing.

        Keep responses focused and actionable. You can use [SUGGESTION: text] to provide concrete alternatives.
        """
    }

    private func recentEntriesContext(limit: Int) -> String {
        let recent = currentSessionEntries.suffix(limit)
        guard !recent.isEmpty else { return "" }

        return recent.map { entry in
            let prefix = entry.isUserMessage ? "Writer: " : "Genevieve: "
            return prefix + String(entry.content.prefix(200))
        }.joined(separator: "\n\n")
    }

    // MARK: - Search

    /// Search commentary entries with optional filters
    func searchEntries(
        query: String,
        dateRange: ClosedRange<Date>? = nil,
        matterId: UUID? = nil,
        documentType: String? = nil,
        limit: Int = 50
    ) -> [CommentaryEntry] {
        guard let modelContext = modelContext else { return [] }

        var descriptor = FetchDescriptor<CommentaryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        guard let allEntries = try? modelContext.fetch(descriptor) else { return [] }

        return allEntries.filter { entry in
            // Query filter
            if !query.isEmpty && !entry.matches(query: query) {
                return false
            }

            // Date range filter
            if let range = dateRange, !range.contains(entry.timestamp) {
                return false
            }

            // Matter filter
            if let mId = matterId, entry.matter?.id != mId {
                return false
            }

            // Document type filter
            if let docType = documentType, entry.documentType != docType {
                return false
            }

            return true
        }
    }

    // MARK: - Narrative Memory

    /// Load cross-session context for narrative memory
    func loadNarrativeMemory(daysBack: Int = 30, limit: Int = 20) -> [CommentaryEntry] {
        guard let modelContext = modelContext else { return [] }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<CommentaryEntry>(
            predicate: #Predicate<CommentaryEntry> { entry in
                entry.timestamp >= cutoffDate && !entry.isUserMessage
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        guard let entries = try? modelContext.fetch(descriptor) else { return [] }
        return Array(entries.prefix(limit))
    }

    // MARK: - Persistence

    private func saveEntry(_ entry: CommentaryEntry) {
        guard let modelContext = modelContext else { return }
        modelContext.insert(entry)
        try? modelContext.save()
    }

    /// Clear current session entries from memory (not from database)
    func clearCurrentSession() {
        currentSessionEntries = []
        currentStreamingText = ""
        streamingProgress = .idle
    }

    /// Delete entries (for cleanup)
    func deleteEntries(_ entries: [CommentaryEntry]) {
        guard let modelContext = modelContext else { return }

        for entry in entries {
            modelContext.delete(entry)
            currentSessionEntries.removeAll { $0.id == entry.id }
        }

        try? modelContext.save()
    }

    // MARK: - Helpers

    private func textKey(for text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }

    func cancelCurrentGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isStreaming = false
        streamingProgress = .idle
    }

    // MARK: - Suggestion Handling

    /// Accept an inline suggestion from a commentary entry
    func acceptSuggestion(from entry: CommentaryEntry) -> String? {
        guard entry.hasSuggestion, let suggestion = entry.suggestionText else { return nil }
        entry.acceptSuggestion()
        try? modelContext?.save()
        return suggestion
    }

    /// Reject an inline suggestion
    func rejectSuggestion(from entry: CommentaryEntry) {
        entry.rejectSuggestion()
        try? modelContext?.save()
    }
}
