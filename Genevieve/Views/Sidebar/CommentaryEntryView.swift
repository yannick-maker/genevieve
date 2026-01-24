import SwiftUI

/// View for displaying a single commentary entry (from Genevieve or user)
struct CommentaryEntryView: View {
    let entry: CommentaryEntry
    var onAcceptSuggestion: ((String) -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            avatarView

            VStack(alignment: .leading, spacing: 6) {
                // Header with name and timestamp
                headerView

                // Content
                contentView

                // Inline suggestion if present
                if entry.hasSuggestion, let suggestion = entry.suggestionText {
                    suggestionView(suggestion)
                }
            }
        }
        .padding(12)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.smallCornerRadius))
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Subviews

    private var avatarView: some View {
        Group {
            if entry.isUserMessage {
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(DesignSystem.Colors.textSecondary.opacity(0.1))
                    .clipShape(Circle())
            } else {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(width: 24, height: 24)
                    .background(DesignSystem.Colors.accent.opacity(0.1))
                    .clipShape(Circle())
            }
        }
    }

    private var headerView: some View {
        HStack {
            Text(entry.senderName)
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(entry.isUserMessage ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.accent)

            Spacer()

            Text(entry.shortTimestamp)
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }

    private var contentView: some View {
        Text(displayContent)
            .font(DesignSystem.Fonts.body)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Parse and display content with suggestion markers highlighted
    private var displayContent: AttributedString {
        var result = AttributedString(entry.content)

        // Find and style [SUGGESTION: ...] markers
        let pattern = #"\[SUGGESTION:\s*(.+?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return result
        }

        let nsContent = entry.content as NSString
        let matches = regex.matches(in: entry.content, options: [], range: NSRange(location: 0, length: nsContent.length))

        // Process matches in reverse to maintain string indices
        for match in matches.reversed() {
            guard let range = Range(match.range, in: entry.content),
                  let attrRange = Range(range, in: result) else { continue }

            // Style the suggestion marker
            result[attrRange].backgroundColor = DesignSystem.Colors.accent.opacity(0.15)
            result[attrRange].foregroundColor = DesignSystem.Colors.accent
        }

        return result
    }

    private func suggestionView(_ suggestion: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.accent)

                Text("Suggestion")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)

                Spacer()

                // Copy button
                Button(action: { copyToClipboard(suggestion) }) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .help("Copy to clipboard")

                Button("Use This") {
                    onAcceptSuggestion?(suggestion)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }

            // Draggable suggestion text
            Text(suggestion)
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)
                .draggable(suggestion) // Enable drag-and-drop
                .overlay(alignment: .topTrailing) {
                    // Drag handle indicator
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .padding(4)
                }
                .help("Drag to insert into your document, or select and copy")
        }
        .padding(.top, 4)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var backgroundColor: Color {
        if entry.isUserMessage {
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        } else if isHovering {
            return Color(nsColor: .controlBackgroundColor).opacity(0.8)
        } else {
            return Color(nsColor: .controlBackgroundColor).opacity(0.3)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        CommentaryEntryView(
            entry: {
                let entry = CommentaryEntry(
                    content: "You're making good progress on this argument structure. The topic sentence is strong, but I'd push back on the second paragraph - it's trying to do too much. [SUGGESTION: Consider splitting this into two focused paragraphs, each addressing a single element of the test.]",
                    isUserMessage: false
                )
                entry.extractSuggestion()
                return entry
            }()
        )

        CommentaryEntryView(
            entry: CommentaryEntry(
                content: "Can you explain more about why you think the second paragraph is weak?",
                isUserMessage: true
            )
        )
    }
    .padding()
    .frame(width: 350)
}
