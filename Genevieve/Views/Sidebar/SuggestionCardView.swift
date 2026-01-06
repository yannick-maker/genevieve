import SwiftUI

/// Card view displaying a single draft suggestion
struct SuggestionCardView: View {
    let suggestion: DraftingAssistant.DraftSuggestionData
    let isSelected: Bool
    var isCompact: Bool = false
    let onAccept: () -> Void
    let onReject: () -> Void
    let onCopy: () -> Void

    @State private var isHovering = false
    @State private var showingFullExplanation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header (Badges)
            headerView

            // Content
            if isCompact {
                // In compact mode, just show the suggested text nicely
                Text(suggestion.suggestedText)
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(3)
            } else {
                // Full mode with comparison
                textView
                
                // Explanation
                explanationView
            }

            // Action buttons (Only show on hover or selection)
            if isHovering || isSelected {
                actionButtonsView
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(DesignSystem.Metrics.padding)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius)
                .fill(isSelected ? AnyShapeStyle(DesignSystem.Colors.accent.opacity(0.05)) : AnyShapeStyle(DesignSystem.Colors.surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius)
                .stroke(isSelected ? DesignSystem.Colors.accent : Color.clear, lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0.05), radius: 4, x: 0, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 8) {
            ConfidenceBadge(level: suggestion.confidenceLevel)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(suggestion.improvementAreas, id: \.rawValue) { area in
                        ImprovementTag(area: area)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Text View

    private var textView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Original Text
            if isSelected {
                Text(suggestion.originalText)
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .strikethrough(color: DesignSystem.Colors.textTertiary.opacity(0.5))
                    .lineLimit(2)
            }

            // Suggested Text
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.success)
                    .padding(.top, 4)
                
                Text(suggestion.suggestedText)
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Explanation

    private var explanationView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { showingFullExplanation.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    
                    Text(showingFullExplanation ? "Hide reasoning" : "View reasoning")
                        .font(.caption)
                    
                    Spacer()
                }
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)

            if showingFullExplanation {
                Text(suggestion.explanation)
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(8)
                    .background(DesignSystem.Colors.surfaceHighlight)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.smallCornerRadius))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            Button(action: onAccept) {
                Label("Accept", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.success)
            .controlSize(.small)

            Button(action: onReject) {
                Label("Reject", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Spacer()
            
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .help("Copy to clipboard")
        }
        .padding(.top, 4)
    }
}

// MARK: - Badges

struct ConfidenceBadge: View {
    let level: DraftingAssistant.DraftSuggestionData.ConfidenceLevel

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help("Confidence: \(String(describing: level))")
    }

    private var color: Color {
        switch level {
        case .high: return DesignSystem.Colors.success
        case .medium: return DesignSystem.Colors.warning
        case .low: return DesignSystem.Colors.textTertiary
        }
    }
}

struct ImprovementTag: View {
    let area: DraftingAssistant.DraftSuggestionData.ImprovementArea

    var body: some View {
        Text(area.rawValue)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DesignSystem.Colors.surfaceHighlight)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }
}