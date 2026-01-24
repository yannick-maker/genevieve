import SwiftUI

/// Main view for the suggestion sidebar panel
struct SuggestionPanelView: View {
    @ObservedObject var draftingAssistant: DraftingAssistant
    @ObservedObject var sidebarController: GenevieveSidebarController
    @ObservedObject var contextAnalyzer: ContextAnalyzer
    @ObservedObject var commentaryService: CommentaryService
    @ObservedObject var metricsCollector: WritingMetricsCollector

    var onAccept: (DraftingAssistant.DraftSuggestionData) -> Void
    var onReject: (DraftingAssistant.DraftSuggestionData) -> Void
    var onCopy: (DraftingAssistant.DraftSuggestionData) -> Void
    var onSendMessage: (String) async -> Void

    // MARK: - Tab Navigation

    enum SidebarTab: String, CaseIterable {
        case suggestions = "Suggestions"
        case commentary = "Commentary"
        case analytics = "Analytics"
        case matter = "Matter"

        var icon: String {
            switch self {
            case .suggestions: return "lightbulb"
            case .commentary: return "quote.bubble"
            case .analytics: return "chart.bar.fill"
            case .matter: return "folder"
            }
        }
    }

    @State private var selectedTab: SidebarTab = .suggestions
    @State private var selectedSuggestionID: UUID?
    @State private var showingSettings = false
    @State private var isCompact = false
    @State private var userMessageText = ""
    @State private var isSendingMessage = false
    @State private var showingArchive = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Tab picker
            tabPicker

            Divider()

            // Content based on selected tab
            switch selectedTab {
            case .suggestions:
                suggestionsContent
            case .commentary:
                commentaryContent
            case .analytics:
                WritingAnalyticsDashboard(
                    metricsCollector: metricsCollector,
                    commentaryService: commentaryService
                )
            case .matter:
                MatterContextView(contextAnalyzer: contextAnalyzer)
            }

            Divider()

            // Footer
            footerView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
        .onChange(of: draftingAssistant.commentaryModeEnabled) { _, isEnabled in
            if isEnabled {
                selectedTab = .commentary
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(SidebarTab.allCases, id: \.self) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DesignSystem.Metrics.padding)
        .padding(.vertical, 8)
    }

    // MARK: - Suggestions Content

    private var suggestionsContent: some View {
        Group {
            if draftingAssistant.isStreaming {
                streamingView
            } else if draftingAssistant.isGenerating {
                loadingView
            } else if draftingAssistant.currentSuggestions.isEmpty {
                emptyStateView
            } else {
                suggestionsListView
            }
        }
    }

    // MARK: - Commentary Content

    private var commentaryContent: some View {
        VStack(spacing: 0) {
            // Header controls
            HStack(spacing: 12) {
                Toggle("Genevieve", isOn: $draftingAssistant.commentaryModeEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Spacer()

                if commentaryService.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: { showingArchive = true }) {
                    Image(systemName: "archivebox")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Browse commentary archive")

                Menu {
                    Button("Export as Text") {
                        exportCommentary(format: .plainText)
                    }
                    Button("Export as Markdown") {
                        exportCommentary(format: .markdown)
                    }
                    Button("Export as PDF") {
                        exportCommentary(format: .pdf)
                    }
                    Divider()
                    Button("Clear Session") {
                        commentaryService.clearCurrentSession()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, DesignSystem.Metrics.padding)
            .padding(.vertical, 8)

            Divider()

            // Show error state if there's an error
            if commentaryService.streamingProgress.isError {
                commentaryErrorView(message: commentaryService.streamingProgress.errorMessage ?? "Unknown error")
            } else {
                // Commentary entries list
                ScrollViewReader { proxy in
                    ScrollView {
                        if commentaryService.currentSessionEntries.isEmpty && !commentaryService.isStreaming {
                            commentaryEmptyState
                                .frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(commentaryService.currentSessionEntries) { entry in
                                    CommentaryEntryView(
                                        entry: entry,
                                        onAcceptSuggestion: { suggestion in
                                            handleInlineSuggestion(suggestion)
                                        }
                                    )
                                    .id(entry.id)
                                }

                                // Show streaming indicator
                                if commentaryService.isStreaming && !commentaryService.currentStreamingText.isEmpty {
                                    streamingEntryView
                                        .id("streaming")
                                }
                            }
                            .padding(DesignSystem.Metrics.padding)
                        }
                    }
                    .onChange(of: commentaryService.currentSessionEntries.count) { _, _ in
                        // Auto-scroll to bottom on new entry
                        if let lastEntry = commentaryService.currentSessionEntries.last {
                            withAnimation {
                                proxy.scrollTo(lastEntry.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            // Dialogue input field
            dialogueInputView
        }
        .sheet(isPresented: $showingArchive) {
            CommentaryArchiveView(commentaryService: commentaryService)
                .frame(minWidth: 500, minHeight: 400)
        }
        .onKeyPress(.tab) {
            // Accept the most recent suggestion when Tab is pressed
            acceptMostRecentSuggestion()
            return .handled
        }
    }

    /// Accept the most recent commentary suggestion
    private func acceptMostRecentSuggestion() {
        // Find the most recent entry with a suggestion
        guard let recentWithSuggestion = commentaryService.currentSessionEntries
            .reversed()
            .first(where: { $0.hasSuggestion && $0.suggestionText != nil }),
              let suggestion = recentWithSuggestion.suggestionText else {
            return
        }

        handleInlineSuggestion(suggestion)
    }

    // MARK: - Dialogue Input

    private var dialogueInputView: some View {
        HStack(spacing: 8) {
            TextField("Ask Genevieve...", text: $userMessageText)
                .textFieldStyle(.plain)
                .font(DesignSystem.Fonts.body)
                .disabled(!draftingAssistant.commentaryModeEnabled || isSendingMessage)
                .onSubmit {
                    sendMessage()
                }

            Button(action: sendMessage) {
                if isSendingMessage {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(userMessageText.isEmpty ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.accent)
                }
            }
            .buttonStyle(.plain)
            .disabled(userMessageText.trimmingCharacters(in: .whitespaces).isEmpty || isSendingMessage)
        }
        .padding(.horizontal, DesignSystem.Metrics.padding)
        .padding(.vertical, 10)
        .background(DesignSystem.Colors.surface)
    }

    private func sendMessage() {
        let message = userMessageText.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else { return }

        userMessageText = ""
        isSendingMessage = true

        Task {
            await onSendMessage(message)
            isSendingMessage = false
        }
    }

    // MARK: - Streaming Entry View

    private var streamingEntryView: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            Image(systemName: "brain.head.profile")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 24, height: 24)
                .background(DesignSystem.Colors.accent.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Genevieve")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(DesignSystem.Colors.accent)

                    Spacer()

                    ProgressView()
                        .controlSize(.mini)
                }

                Text(commentaryService.currentStreamingText)
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.smallCornerRadius))
    }

    // MARK: - Helpers

    private func exportCommentary(format: CommentaryExporter.ExportFormat) {
        _ = CommentaryExporter.exportWithSaveDialog(
            entries: commentaryService.currentSessionEntries,
            format: format
        )
    }

    private func handleInlineSuggestion(_ suggestion: String) {
        // Copy to clipboard for now - later integrate with text service
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(suggestion, forType: .string)
    }

    private func commentaryErrorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(DesignSystem.Colors.warning)

            VStack(spacing: 8) {
                Text("Commentary Paused")
                    .font(DesignSystem.Fonts.title)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text(friendlyErrorMessage(from: message))
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 12) {
                Button("Retry") {
                    retryCommentary()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button("Continue Without AI") {
                    draftingAssistant.commentaryModeEnabled = false
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            // Show existing commentary if any
            if !draftingAssistant.commentaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                    .padding(.top, 8)

                Text("Previous commentary:")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)

                ScrollView {
                    Text(draftingAssistant.commentaryText)
                        .font(DesignSystem.Fonts.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(DesignSystem.Metrics.padding)
                }
                .frame(maxHeight: 150)
            }

            Spacer()
        }
        .padding()
    }

    private func friendlyErrorMessage(from message: String) -> String {
        let lowercased = message.lowercased()

        if lowercased.contains("rate limit") {
            return "The AI service is temporarily busy. Please try again in a moment."
        } else if lowercased.contains("network") || lowercased.contains("connection") {
            return "Unable to connect to the AI service. Please check your internet connection."
        } else if lowercased.contains("api key") || lowercased.contains("unauthorized") || lowercased.contains("401") {
            return "There's an issue with your API key. Please check Settings > API Keys."
        } else if lowercased.contains("timeout") {
            return "The request took too long. Please try again."
        } else if lowercased.contains("quota") || lowercased.contains("billing") {
            return "API quota exceeded. Please check your billing settings."
        } else {
            return "Something went wrong. Please try again."
        }
    }

    private func retryCommentary() {
        // Clear the error state and trigger a new generation
        draftingAssistant.clearCommentary()
        // The coordinator will pick up the enabled state and regenerate
    }

    private var commentaryEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 36))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("No commentary yet")
                .font(DesignSystem.Fonts.title)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text(draftingAssistant.commentaryModeEnabled
                 ? "Start typing in a text field to see live commentary."
                 : "Enable stream-of-consciousness mode to get live commentary as you work.")
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 32)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Icon and title
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.title3)
                        .foregroundStyle(DesignSystem.Colors.accent)

                    Text("Genevieve")
                        .font(DesignSystem.Fonts.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }

                Spacer()

                // Pin button
                Button(action: { sidebarController.togglePin() }) {
                    Image(systemName: sidebarController.isPinned ? "pin.fill" : "pin")
                        .font(.caption)
                        .foregroundStyle(sidebarController.isPinned ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .help(sidebarController.isPinned ? "Unpin sidebar" : "Pin sidebar")

                // Settings button
                Button(action: { showingSettings.toggle() }) {
                    Image(systemName: "gear")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingSettings) {
                    SidebarSettingsView(sidebarController: sidebarController, isCompact: $isCompact)
                        .frame(width: 250)
                }
            }

            // Session stats row
            HStack(spacing: 12) {
                // Session duration
                StatBadge(icon: "clock", value: draftingAssistant.sessionStats.formattedDuration)

                // Accepted count
                StatBadge(icon: "checkmark.circle", value: "\(draftingAssistant.sessionStats.suggestionsAccepted)")

                Spacer()

                // Context badge
                if let analysis = contextAnalyzer.currentAnalysis {
                    HStack(spacing: 4) {
                        Text(analysis.documentType.displayName)
                            .font(DesignSystem.Fonts.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)

                        if let section = analysis.section, section != .unknown {
                            Text("•")
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                            Text(section.displayName)
                                .font(DesignSystem.Fonts.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.surfaceHighlight)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(DesignSystem.Metrics.padding)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Stat Badge

    private struct StatBadge: View {
        let icon: String
        let value: String

        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)

                Text(value)
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(DesignSystem.Colors.surfaceHighlight.opacity(0.5))
            .clipShape(Capsule())
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text("Analyzing your text...")
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Streaming View

    private var streamingView: some View {
        VStack(spacing: 0) {
            // Progress indicator
            streamingProgressHeader

            // Show any suggestions that have completed
            if !draftingAssistant.currentSuggestions.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(draftingAssistant.currentSuggestions) { suggestion in
                            SuggestionCardView(
                                suggestion: suggestion,
                                isSelected: selectedSuggestionID == suggestion.id,
                                isCompact: isCompact,
                                onAccept: { onAccept(suggestion) },
                                onReject: { onReject(suggestion) },
                                onCopy: { onCopy(suggestion) }
                            )
                            .opacity(0.9)
                        }

                        // Show streaming indicator for next suggestion
                        streamingPlaceholderCard
                    }
                    .padding(DesignSystem.Metrics.padding)
                }
            } else {
                // No suggestions yet, show streaming text preview
                streamingTextPreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var streamingProgressHeader: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Group {
                switch draftingAssistant.streamingProgress {
                case .idle:
                    Text("Ready")
                case .starting:
                    Text("Starting...")
                case .streaming(let index, let total):
                    Text("Generating suggestion \(index) of \(total)...")
                case .parsing:
                    Text("Processing suggestions...")
                case .complete:
                    Text("Complete")
                case .error(let message):
                    Text("Error: \(message)")
                        .foregroundStyle(.red)
                }
            }
            .font(DesignSystem.Fonts.caption)
            .foregroundStyle(DesignSystem.Colors.textSecondary)

            Spacer()
        }
        .padding(.horizontal, DesignSystem.Metrics.padding)
        .padding(.vertical, 8)
        .background(DesignSystem.Colors.surface)
    }

    private var streamingPlaceholderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Typing cursor animation
                typingCursor

                Text("Generating next suggestion...")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            // Show partial streaming text if available
            if !draftingAssistant.streamingText.isEmpty {
                Text(truncatedStreamingText)
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(DesignSystem.Metrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius)
                .strokeBorder(DesignSystem.Colors.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }

    private var truncatedStreamingText: String {
        let text = draftingAssistant.streamingText
        if text.count > 200 {
            // Show last 200 characters
            let startIndex = text.index(text.endIndex, offsetBy: -200)
            return "..." + text[startIndex...]
        }
        return text
    }

    private var typingCursor: some View {
        Rectangle()
            .fill(DesignSystem.Colors.accent)
            .frame(width: 2, height: 14)
            .opacity(cursorOpacity)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorOpacity)
            .onAppear { cursorOpacity = 0.2 }
    }

    @State private var cursorOpacity: Double = 1.0

    private var streamingTextPreview: some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    typingCursor

                    Text("Generating suggestions...")
                        .font(DesignSystem.Fonts.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }

                if !draftingAssistant.streamingText.isEmpty {
                    ScrollView {
                        Text(draftingAssistant.streamingText)
                            .font(DesignSystem.Fonts.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            }
            .padding(DesignSystem.Metrics.padding)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius))
            .padding(.horizontal, DesignSystem.Metrics.padding)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "text.cursor")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            VStack(spacing: 12) {
                Text("Ready to Help")
                    .font(DesignSystem.Fonts.title)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Start writing in any text field and I'll offer suggestions to improve your draft.")
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)

            Spacer()

            // Tips
            VStack(alignment: .leading, spacing: 12) {
                Text("Tips")
                    .font(DesignSystem.Fonts.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                tipRow(icon: "keyboard", text: "Cmd+Shift+G toggles this sidebar")
                tipRow(icon: "return", text: "Tab to accept a suggestion")
                tipRow(icon: "escape", text: "Esc to dismiss")
            }
            .padding(DesignSystem.Metrics.padding)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius))
            .padding(.horizontal, DesignSystem.Metrics.padding)
            .padding(.bottom, DesignSystem.Metrics.padding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 16)

            Text(text)
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    // MARK: - Suggestions List

    private var suggestionsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(draftingAssistant.currentSuggestions) { suggestion in
                    SuggestionCardView(
                        suggestion: suggestion,
                        isSelected: selectedSuggestionID == suggestion.id,
                        isCompact: isCompact,
                        onAccept: {
                            onAccept(suggestion)
                        },
                        onReject: {
                            onReject(suggestion)
                        },
                        onCopy: {
                            onCopy(suggestion)
                        }
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if selectedSuggestionID == suggestion.id {
                                selectedSuggestionID = nil
                            } else {
                                selectedSuggestionID = suggestion.id
                            }
                        }
                    }
                }
            }
            .padding(DesignSystem.Metrics.padding)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            // Suggestion count
            if !draftingAssistant.currentSuggestions.isEmpty {
                Text("\(draftingAssistant.currentSuggestions.count) suggestions")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            Spacer()

            // Keyboard hint
            Text("Tab: accept • Esc: dismiss")
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .padding(.horizontal, DesignSystem.Metrics.padding)
        .padding(.vertical, 8)
        .background(DesignSystem.Colors.surface)
    }
}

// MARK: - Sidebar Settings View

struct SidebarSettingsView: View {
    @ObservedObject var sidebarController: GenevieveSidebarController
    @Binding var isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sidebar Settings")
                .font(DesignSystem.Fonts.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Divider()

            // View Options
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                
                Toggle("Compact suggestions", isOn: $isCompact)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                
                Toggle("Keep sidebar visible", isOn: Binding(
                    get: { sidebarController.isPinned },
                    set: { _ in sidebarController.togglePin() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Divider()
            
            // Position
            VStack(alignment: .leading, spacing: 12) {
                Text("Position")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                
                Picker("", selection: $sidebarController.position) {
                    ForEach(GenevieveSidebarController.SidebarPosition.allCases, id: \.self) { pos in
                        Text(pos.displayName).tag(pos)
                    }
                }
                .pickerStyle(.segmented)
            }
            .onChange(of: sidebarController.position) { _, newValue in
                sidebarController.moveTo(newValue)
            }

            Divider()

            // Keyboard shortcuts info
            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard Shortcuts")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)

                shortcutRow("Toggle sidebar", "Cmd+Shift+G")
                shortcutRow("Accept suggestion", "Tab")
                shortcutRow("Dismiss", "Esc")
            }
        }
        .padding(DesignSystem.Metrics.padding)
    }

    private func shortcutRow(_ action: String, _ shortcut: String) -> some View {
        HStack {
            Text(action)
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer()
            Text(shortcut)
                .font(DesignSystem.Fonts.monospaceNumeric)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignSystem.Colors.surfaceHighlight)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
