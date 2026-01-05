import SwiftUI

/// Card view displaying a single draft suggestion
struct SuggestionCardView: View {
    let suggestion: DraftingAssistant.DraftSuggestionData
    let isSelected: Bool
    let onAccept: () -> Void
    let onReject: () -> Void
    let onCopy: () -> Void

    @State private var isHovering = false
    @State private var showingFullExplanation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Confidence badge and improvements
            headerView

            // Suggested text
            textView

            // Explanation (collapsible)
            explanationView

            // Action buttons
            if isSelected || isHovering {
                actionButtonsView
            }
        }
        .padding(12)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
        )
        .shadow(color: .black.opacity(isSelected ? 0.1 : 0.05), radius: isSelected ? 4 : 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 8) {
            // Confidence indicator
            ConfidenceBadge(level: suggestion.confidenceLevel)

            // Improvement tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(suggestion.improvementAreas, id: \.rawValue) { area in
                        ImprovementTag(area: area)
                    }
                }
            }

            Spacer()

            // Timestamp
            Text(timeAgo(suggestion.generatedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Text View

    private var textView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Original (strikethrough, dimmed)
            if isSelected {
                Text(suggestion.originalText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .strikethrough(color: .secondary.opacity(0.5))
                    .lineLimit(2)
            }

            // Suggested text
            Text(suggestion.suggestedText)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(isSelected ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Explanation

    private var explanationView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { showingFullExplanation.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Text(showingFullExplanation ? "Hide explanation" : "Why is this better?")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: showingFullExplanation ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if showingFullExplanation {
                Text(suggestion.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.orange.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingFullExplanation)
    }

    // MARK: - Action Buttons

    private var actionButtonsView: some View {
        HStack(spacing: 8) {
            // Accept button
            Button(action: onAccept) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text("Accept")
                }
                .font(.caption)
                .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            // Copy button
            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            // Reject button
            Button(action: onReject) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Background

    private var cardBackground: some View {
        Group {
            if isSelected {
                Color.accentColor.opacity(0.05)
            } else if isHovering {
                Color.secondary.opacity(0.05)
            } else {
                Color(nsColor: .controlBackgroundColor)
            }
        }
    }

    // MARK: - Helpers

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
}

// MARK: - Confidence Badge

struct ConfidenceBadge: View {
    let level: DraftingAssistant.DraftSuggestionData.ConfidenceLevel

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor)
                .frame(width: 6, height: 6)

            Text(badgeText)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch level {
        case .high:
            return .green
        case .medium:
            return .orange
        case .low:
            return .gray
        }
    }

    private var badgeText: String {
        switch level {
        case .high:
            return "High confidence"
        case .medium:
            return "Moderate"
        case .low:
            return "Suggestion"
        }
    }
}

// MARK: - Improvement Tag

struct ImprovementTag: View {
    let area: DraftingAssistant.DraftSuggestionData.ImprovementArea

    var body: some View {
        Text(area.rawValue)
            .font(.caption2)
            .foregroundStyle(tagColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tagColor.opacity(0.1))
            .clipShape(Capsule())
    }

    private var tagColor: Color {
        switch area {
        case .clarity:
            return .blue
        case .precision:
            return .purple
        case .persuasiveness:
            return .orange
        case .conciseness:
            return .green
        case .formality:
            return .indigo
        case .flow:
            return .cyan
        case .legalStandard:
            return .red
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        SuggestionCardView(
            suggestion: DraftingAssistant.DraftSuggestionData(
                id: UUID(),
                originalText: "The defendant failed to comply with the requirements.",
                suggestedText: "Defendant materially breached Section 4.2 by failing to deliver conforming goods within the contractually mandated timeframe.",
                explanation: "This is stronger because it: (1) specifies the exact contractual provision, (2) uses the legal term 'materially breached', and (3) identifies the specific failure.",
                improvementAreas: [.precision, .legalStandard, .persuasiveness],
                confidence: 0.85,
                generatedAt: Date()
            ),
            isSelected: true,
            onAccept: {},
            onReject: {},
            onCopy: {}
        )

        SuggestionCardView(
            suggestion: DraftingAssistant.DraftSuggestionData(
                id: UUID(),
                originalText: "We think the court should rule in our favor.",
                suggestedText: "For the foregoing reasons, the Court should grant Plaintiff's motion for summary judgment.",
                explanation: "More formal and uses proper legal convention for conclusion sections.",
                improvementAreas: [.formality, .clarity],
                confidence: 0.72,
                generatedAt: Date().addingTimeInterval(-300)
            ),
            isSelected: false,
            onAccept: {},
            onReject: {},
            onCopy: {}
        )
    }
    .padding()
    .frame(width: 300)
}
