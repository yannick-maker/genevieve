import SwiftUI

/// Morning briefing view showing daily summary and focus recommendations
struct MorningBriefingView: View {
    @ObservedObject var matterTracker: MatterTracker
    @ObservedObject var learningService: LearningService
    @Environment(\.dismiss) private var dismiss

    @State private var briefing: MatterTracker.MorningBriefing?
    @State private var yesterdayStats: YesterdayStats?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerView

                // Yesterday recap
                if let stats = yesterdayStats {
                    yesterdayRecapView(stats)
                }

                // Today's focus
                if let briefing = briefing {
                    todayFocusView(briefing)

                    // Upcoming deadlines
                    if !briefing.upcomingDeadlines.isEmpty {
                        deadlinesView(briefing.upcomingDeadlines)
                    }

                    // Quick wins
                    quickWinsView
                }

                // Learning insights
                learningInsightsView

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadBriefing()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingText)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(Date().formatted(date: .complete, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if briefing?.hasUrgentDeadlines == true {
                urgentBanner
            }
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    private var urgentBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)

            Text("You have deadlines within 3 days")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(12)
        .background(Color.red)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Yesterday Recap

    private func yesterdayRecapView(_ stats: YesterdayStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Yesterday's Recap")
                .font(.headline)

            HStack(spacing: 20) {
                StatCard(
                    icon: "clock",
                    value: stats.formattedTime,
                    label: "Time spent"
                )

                StatCard(
                    icon: "doc.text",
                    value: "\(stats.documentsWorked)",
                    label: "Documents"
                )

                StatCard(
                    icon: "checkmark.circle",
                    value: "\(stats.suggestionsAccepted)",
                    label: "Suggestions used"
                )

                StatCard(
                    icon: "brain",
                    value: "\(Int(stats.focusScore * 100))%",
                    label: "Focus score"
                )
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Today's Focus

    private func todayFocusView(_ briefing: MatterTracker.MorningBriefing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's Focus")
                    .font(.headline)

                Spacer()

                Text("\(briefing.totalActiveMatters) active matters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if briefing.focusRecommendations.isEmpty {
                Text("No specific focus recommendations. You're all caught up!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(briefing.focusRecommendations, id: \.id) { matter in
                    FocusMatterRow(matter: matter)
                }
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Deadlines

    private func deadlinesView(_ deadlines: [(matter: Matter, deadline: Date, name: String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming Deadlines")
                .font(.headline)

            ForEach(deadlines.prefix(5), id: \.name) { item in
                DeadlineRow(
                    matterName: item.matter.name,
                    deadlineName: item.name,
                    date: item.deadline
                )
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Quick Wins

    private var quickWinsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Wins")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                QuickWinRow(
                    icon: "doc.badge.plus",
                    text: "Save 3 arguments from yesterday's accepted suggestions"
                )

                QuickWinRow(
                    icon: "tag",
                    text: "Add tags to recently used arguments for better organization"
                )

                QuickWinRow(
                    icon: "clock.arrow.circlepath",
                    text: "Review and close completed matters"
                )
            }
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Learning Insights

    private var learningInsightsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Genevieve is Learning")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.green)

                    Text("Suggestion acceptance rate: \(Int(learningService.acceptanceRate * 100))%")
                        .font(.subheadline)
                }

                HStack {
                    Image(systemName: "text.quote")
                        .foregroundStyle(.blue)

                    Text("Preferred tone: \(learningService.userProfile.preferredTone.displayName)")
                        .font(.subheadline)
                }

                HStack {
                    Image(systemName: "textformat.size")
                        .foregroundStyle(.purple)

                    Text("Verbosity: \(learningService.userProfile.verbosityLevel.displayName)")
                        .font(.subheadline)
                }

                if !learningService.topRejectionReasons.isEmpty {
                    HStack(alignment: .top) {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(.orange)

                        Text("Top feedback: \(learningService.topRejectionReasons.first?.reason.displayName ?? "None")")
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data Loading

    private func loadBriefing() {
        briefing = matterTracker.getMorningBriefing()
        yesterdayStats = calculateYesterdayStats()
    }

    private func calculateYesterdayStats() -> YesterdayStats {
        // In a real implementation, this would query SwiftData
        // For now, return placeholder data
        YesterdayStats(
            totalTime: 14400, // 4 hours
            documentsWorked: 5,
            suggestionsAccepted: 12,
            focusScore: 0.78
        )
    }
}

// MARK: - Supporting Types

struct YesterdayStats {
    var totalTime: TimeInterval
    var documentsWorked: Int
    var suggestionsAccepted: Int
    var focusScore: Double

    var formattedTime: String {
        let hours = Int(totalTime) / 3600
        let minutes = (Int(totalTime) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Subviews

struct StatCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct FocusMatterRow: View {
    let matter: Matter

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(priorityColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(matter.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let client = matter.clientName {
                    Text(client)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let days = matter.daysUntilDeadline {
                Text("\(days) days")
                    .font(.caption)
                    .foregroundStyle(days <= 3 ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var priorityColor: Color {
        switch matter.matterPriority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        case .none: return .gray
        }
    }
}

struct DeadlineRow: View {
    let matterName: String
    let deadlineName: String
    let date: Date

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(deadlineName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(matterName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)

                Text(daysRemaining)
                    .font(.caption)
                    .foregroundStyle(urgencyColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var daysRemaining: String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days == 0 {
            return "Today"
        } else if days == 1 {
            return "Tomorrow"
        } else {
            return "\(days) days"
        }
    }

    private var urgencyColor: Color {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days <= 1 {
            return .red
        } else if days <= 3 {
            return .orange
        } else {
            return .secondary
        }
    }
}

struct QuickWinRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.green)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Preview

#Preview {
    MorningBriefingView(
        matterTracker: MatterTracker(),
        learningService: LearningService()
    )
}
