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
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // Icon and title
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)

                Text("Genevieve")
                    .font(.headline)
            }

            Spacer()

            // Context badge
            if let analysis = contextAnalyzer.currentAnalysis {
                HStack(spacing: 4) {
                    Text(analysis.documentType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let section = analysis.section, section != .unknown {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(section.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
            }

            // Pin button
            Button(action: { sidebarController.togglePin() }) {
                Image(systemName: sidebarController.isPinned ? "pin.fill" : "pin")
                    .font(.caption)
                    .foregroundStyle(sidebarController.isPinned ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(sidebarController.isPinned ? "Unpin sidebar" : "Pin sidebar")

            // Settings button
            Button(action: { showingSettings.toggle() }) {
                Image(systemName: "gear")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingSettings) {
                SidebarSettingsView(sidebarController: sidebarController)
                    .frame(width: 220)
            }
        }
        .padding()
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text("Analyzing your text...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "text.cursor")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("Ready to Help")
                    .font(.headline)

                Text("Start writing in any text field and I'll offer suggestions to improve your draft.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)

            Spacer()

            // Tips
            VStack(alignment: .leading, spacing: 8) {
                tipRow(icon: "keyboard", text: "Cmd+Shift+G toggles this sidebar")
                tipRow(icon: "return", text: "Tab to accept a suggestion")
                tipRow(icon: "escape", text: "Esc to dismiss")
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
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
            .padding()
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            // Suggestion count
            if !draftingAssistant.currentSuggestions.isEmpty {
                Text("\(draftingAssistant.currentSuggestions.count) suggestions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Keyboard hint
            Text("Tab: accept • Esc: dismiss")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Sidebar Settings View

struct SidebarSettingsView: View {
    @ObservedObject var sidebarController: GenevieveSidebarController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sidebar Settings")
                .font(.headline)

            Divider()

            // Position picker
            HStack {
                Text("Position")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $sidebarController.position) {
                    ForEach(GenevieveSidebarController.SidebarPosition.allCases, id: \.self) { pos in
                        Text(pos.displayName).tag(pos)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
            .onChange(of: sidebarController.position) { _, newValue in
                sidebarController.moveTo(newValue)
            }

            // Pin toggle
            Toggle("Keep sidebar visible", isOn: Binding(
                get: { sidebarController.isPinned },
                set: { _ in sidebarController.togglePin() }
            ))
            .font(.subheadline)

            Divider()

            // Keyboard shortcuts info
            VStack(alignment: .leading, spacing: 4) {
                Text("Keyboard Shortcuts")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                shortcutRow("Toggle sidebar", "Cmd+Shift+G")
                shortcutRow("Accept suggestion", "Tab")
                shortcutRow("Dismiss", "Esc")
                shortcutRow("Next suggestion", "↓")
                shortcutRow("Previous suggestion", "↑")
            }
        }
        .padding()
    }

    private func shortcutRow(_ action: String, _ shortcut: String) -> some View {
        HStack {
            Text(action)
                .font(.caption)
            Spacer()
            Text(shortcut)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - Preview

#Preview {
    let draftingAssistant = DraftingAssistant(
        aiService: AIProviderService()
    )
    let sidebarController = GenevieveSidebarController()
    let contextAnalyzer = ContextAnalyzer(
        aiService: AIProviderService()
    )

    return SuggestionPanelView(
        draftingAssistant: draftingAssistant,
        sidebarController: sidebarController,
        contextAnalyzer: contextAnalyzer,
        onAccept: { _ in },
        onReject: { _ in },
        onCopy: { _ in }
    )
    .frame(width: 300, height: 600)
}
