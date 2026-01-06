import SwiftUI

/// Morning briefing view showing daily summary and focus recommendations
struct MorningBriefingView: View {
    @ObservedObject var matterTracker: MatterTracker
    @ObservedObject var learningService: LearningService
    @Environment(\.dismiss) private var dismiss

    @State private var briefing: MatterTracker.MorningBriefing?
    @State private var yesterdayStats: YesterdayStats?

    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerView

                if let briefing = briefing, let stats = yesterdayStats {
                    LazyVGrid(columns: columns, spacing: 20) {
                        // Row 1: Recap & Focus (Full width if needed, or split)
                        GridRow {
                            yesterdayRecapView(stats)
                                .gridCellColumns(2)
                        }

                        // Row 2: Today's Focus & Deadlines
                        todayFocusView(briefing)
                        
                        if !briefing.upcomingDeadlines.isEmpty {
                            deadlinesView(briefing.upcomingDeadlines)
                        } else {
                            // If no deadlines, stretch focus or show placeholder
                            ContentUnavailableView("No Deadlines", systemImage: "calendar.badge.checkmark")
                                .genevieveCardStyle()
                        }

                        // Row 3: Quick Wins & Learning
                        QuickWinsCard()
                        
                        learningInsightsView
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(DesignSystem.Metrics.padding)
        }
        .background(DesignSystem.Colors.background)
        .onAppear {
            loadBriefing()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingText)
                        .font(DesignSystem.Fonts.display)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Text(Date().formatted(date: .complete, time: .omitted))
                        .font(DesignSystem.Fonts.title)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                Spacer()
            }

            if briefing?.hasUrgentDeadlines == true {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignSystem.Colors.error)
                    
                    Text("You have deadlines within 3 days")
                        .font(DesignSystem.Fonts.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    
                    Spacer()
                }
                .padding()
                .background(DesignSystem.Colors.error.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius)
                        .stroke(DesignSystem.Colors.error.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - Cards

    private func yesterdayRecapView(_ stats: YesterdayStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Yesterday's Recap")
                .genevieveSubtitle()

            HStack(spacing: 0) {
                StatView(
                    icon: "clock",
                    value: stats.formattedTime,
                    label: "Time spent",
                    color: .blue
                )
                
                Divider()

                StatView(
                    icon: "doc.text",
                    value: "\(stats.documentsWorked)",
                    label: "Documents",
                    color: .purple
                )
                
                Divider()

                StatView(
                    icon: "checkmark.circle",
                    value: "\(stats.suggestionsAccepted)",
                    label: "Suggestions",
                    color: .green
                )
                
                Divider()

                StatView(
                    icon: "brain",
                    value: "\(Int(stats.focusScore * 100))%",
                    label: "Focus score",
                    color: .orange
                )
            }
        }
        .genevieveCardStyle()
    }

    private func todayFocusView(_ briefing: MatterTracker.MorningBriefing) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Focus")
                    .genevieveSubtitle()

                Spacer()

                Text("\(briefing.totalActiveMatters) active")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            if briefing.focusRecommendations.isEmpty {
                Text("You're all caught up!")
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(briefing.focusRecommendations.prefix(3), id: \.id) { matter in
                        FocusMatterRow(matter: matter)
                        if matter.id != briefing.focusRecommendations.prefix(3).last?.id {
                            Divider().padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .genevieveCardStyle()
    }

    private func deadlinesView(_ deadlines: [(matter: Matter, deadline: Date, name: String)]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Upcoming Deadlines")
                .genevieveSubtitle()

            VStack(spacing: 12) {
                ForEach(deadlines.prefix(3), id: \.name) { item in
                    DeadlineRow(
                        matterName: item.matter.name,
                        deadlineName: item.name,
                        date: item.deadline
                    )
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .genevieveCardStyle()
    }

    private var learningInsightsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insights")
                .genevieveSubtitle()

            VStack(alignment: .leading, spacing: 12) {
                InsightRow(
                    icon: "chart.line.uptrend.xyaxis",
                    color: .green,
                    text: "Acceptance rate: \(Int(learningService.acceptanceRate * 100))%"
                )

                InsightRow(
                    icon: "text.quote",
                    color: .blue,
                    text: "Tone: \(learningService.userProfile.preferredTone.displayName)"
                )
            }
        }
        .genevieveCardStyle()
    }

    // MARK: - Data Loading

    private func loadBriefing() {
        briefing = matterTracker.getMorningBriefing()
        yesterdayStats = calculateYesterdayStats()
    }

    private func calculateYesterdayStats() -> YesterdayStats {
        YesterdayStats(
            totalTime: 14400,
            documentsWorked: 5,
            suggestionsAccepted: 12,
            focusScore: 0.78
        )
    }
}

// MARK: - Interactive Components

struct QuickWinsCard: View {
    @State private var tasks = [
        ("Save 3 arguments from yesterday", false),
        ("Tag recent arguments", false),
        ("Review completed matters", false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Wins")
                .genevieveSubtitle()

            VStack(alignment: .leading, spacing: 12) {
                ForEach($tasks, id: \.0) { $task in
                    Toggle(isOn: $task.1) {
                        Text(task.0)
                            .font(DesignSystem.Fonts.body)
                            .strikethrough(task.1)
                            .foregroundStyle(task.1 ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.textPrimary)
                    }
                    .toggleStyle(CheckboxToggleStyle())
                }
            }
        }
        .genevieveCardStyle(interactable: true)
    }
}

// MARK: - Supporting Views

struct StatView: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(DesignSystem.Fonts.headline)

            Text(label)
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
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
                    .font(DesignSystem.Fonts.body)
                    .fontWeight(.medium)

                if let client = matter.clientName {
                    Text(client)
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            Spacer()
        }
    }

    private var priorityColor: Color {
        switch matter.matterPriority {
        case .high: return DesignSystem.Colors.error
        case .medium: return DesignSystem.Colors.warning
        case .low: return DesignSystem.Colors.info
        case .none: return DesignSystem.Colors.textTertiary
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
                    .font(DesignSystem.Fonts.body)
                    .fontWeight(.medium)
                Text(matterName)
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(DesignSystem.Fonts.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(urgencyColor.opacity(0.1))
                .foregroundStyle(urgencyColor)
                .clipShape(Capsule())
        }
    }

    private var urgencyColor: Color {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return days <= 3 ? DesignSystem.Colors.error : DesignSystem.Colors.textSecondary
    }
}

struct InsightRow: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(DesignSystem.Fonts.body)
        }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundStyle(configuration.isOn ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary)
                .onTapGesture {
                    withAnimation { configuration.isOn.toggle() }
                }
            configuration.label
        }
    }
}

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