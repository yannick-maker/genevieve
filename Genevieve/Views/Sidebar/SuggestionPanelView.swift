import SwiftUI

/// Main view for the suggestion sidebar panel
struct SuggestionPanelView: View {
    @ObservedObject var draftingAssistant: DraftingAssistant
    @ObservedObject var sidebarController: GenevieveSidebarController
    @ObservedObject var contextAnalyzer: ContextAnalyzer

    var onAccept: (DraftingAssistant.DraftSuggestionData) -> Void
    var onReject: (DraftingAssistant.DraftSuggestionData) -> Void
    var onCopy: (DraftingAssistant.DraftSuggestionData) -> Void

    @State private var selectedSuggestionID: UUID?
    @State private var showingSettings = false
    @State private var isCompact = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            if draftingAssistant.isGenerating {
                loadingView
            } else if draftingAssistant.currentSuggestions.isEmpty {
                emptyStateView
            } else {
                suggestionsListView
            }

            Divider()

            // Footer
            footerView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Header

    private var headerView: some View {
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
        .padding(DesignSystem.Metrics.padding)
        .background(DesignSystem.Colors.surface)
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