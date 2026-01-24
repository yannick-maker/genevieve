import SwiftUI

/// View showing history of recent suggestions
struct SuggestionHistoryView: View {
    @ObservedObject var draftingAssistant: DraftingAssistant

    var onReapply: (DraftingAssistant.DraftSuggestionData) -> Void

    // Track history of suggestions with their status
    @State private var history: [HistoryItem] = []

    struct HistoryItem: Identifiable {
        let id = UUID()
        let suggestion: DraftingAssistant.DraftSuggestionData
        let status: Status
        let timestamp: Date

        enum Status {
            case accepted
            case rejected
            case pending
        }
    }

    var body: some View {
        if history.isEmpty {
            emptyHistoryView
        } else {
            historyListView
        }
    }

    // MARK: - Empty State

    private var emptyHistoryView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "clock")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            VStack(spacing: 12) {
                Text("No History Yet")
                    .font(DesignSystem.Fonts.title)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Your accepted and rejected suggestions will appear here.")
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - History List

    private var historyListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(history) { item in
                    HistoryItemView(
                        item: item,
                        onReapply: {
                            onReapply(item.suggestion)
                        }
                    )
                }
            }
            .padding(DesignSystem.Metrics.padding)
        }
    }
}

// MARK: - History Item View

struct HistoryItemView: View {
    let item: SuggestionHistoryView.HistoryItem
    var onReapply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with status and time
            HStack {
                statusIcon

                Text(timeAgo)
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)

                Spacer()

                // Reapply button for accepted items
                if item.status == .accepted {
                    Button(action: onReapply) {
                        Label("Reapply", systemImage: "arrow.uturn.left")
                            .font(DesignSystem.Fonts.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignSystem.Colors.accent)
                }
            }

            // Suggestion text preview
            Text(item.suggestion.suggestedText)
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(3)

            // Explanation
            Text(item.suggestion.explanation)
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(2)
        }
        .padding(DesignSystem.Metrics.padding)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius))
        .opacity(item.status == .rejected ? 0.6 : 1.0)
    }

    private var statusIcon: some View {
        Group {
            switch item.status {
            case .accepted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .rejected:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        }
        .font(.caption)
    }

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(item.timestamp)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
}
