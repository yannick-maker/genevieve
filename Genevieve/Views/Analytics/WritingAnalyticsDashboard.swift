import SwiftUI
import Charts

/// Dashboard view showing writing progress and analytics
struct WritingAnalyticsDashboard: View {
    @ObservedObject var metricsCollector: WritingMetricsCollector
    @ObservedObject var commentaryService: CommentaryService

    @State private var selectedTimeRange: TimeRange = .session

    enum TimeRange: String, CaseIterable {
        case session = "This Session"
        case today = "Today"
        case week = "This Week"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with time range picker
                headerView

                // Real-time metrics cards
                metricsGrid

                // Focus and mood section
                focusMoodSection

                // Writing speed chart (if enough data)
                if metricsCollector.currentMetrics.activeWritingTime > 60 {
                    speedChartSection
                }

                // Commentary insights
                commentaryInsights
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Writing Analytics")
                    .font(DesignSystem.Fonts.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Track your writing progress and patterns")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Picker("Time Range", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            MetricCard(
                title: "Active Time",
                value: metricsCollector.currentMetrics.formattedActiveTime,
                icon: "clock.fill",
                color: .blue
            )

            MetricCard(
                title: "Words Written",
                value: "\(metricsCollector.currentMetrics.totalWordsWritten)",
                icon: "text.word.spacing",
                color: .green
            )

            MetricCard(
                title: "Speed",
                value: String(format: "%.0f WPM", metricsCollector.currentMetrics.wordsPerMinute),
                icon: "speedometer",
                color: .orange
            )

            MetricCard(
                title: "Focus Score",
                value: "\(metricsCollector.currentMetrics.focusPercentage)%",
                icon: "target",
                color: focusColor
            )

            MetricCard(
                title: "Pauses",
                value: "\(metricsCollector.currentMetrics.pauseCount)",
                icon: "pause.circle.fill",
                color: .purple
            )

            MetricCard(
                title: "Revisions",
                value: "\(metricsCollector.currentMetrics.revisionCount)",
                icon: "arrow.triangle.2.circlepath",
                color: .teal
            )
        }
    }

    private var focusColor: Color {
        let score = metricsCollector.currentMetrics.focusScore
        if score > 0.7 { return .green }
        if score > 0.4 { return .yellow }
        return .red
    }

    // MARK: - Focus and Mood Section

    private var focusMoodSection: some View {
        VStack(spacing: 12) {
            // Focus progress bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Focus Level")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Spacer()

                    Text(moodEmoji)
                        .font(.title2)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.Colors.surfaceHighlight)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(focusGradient)
                            .frame(width: geometry.size.width * metricsCollector.currentMetrics.focusScore, height: 8)
                    }
                }
                .frame(height: 8)
            }
            .padding()
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius))

            // Mood indicator
            HStack {
                Image(systemName: moodIcon)
                    .font(.title2)
                    .foregroundStyle(moodColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Current State")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text(metricsCollector.currentMetrics.estimatedMood.rawValue)
                        .font(DesignSystem.Fonts.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }

                Spacer()

                if metricsCollector.currentMetrics.isInFlowState {
                    Label("In Flow", systemImage: "flame.fill")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding()
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius))
        }
    }

    private var focusGradient: LinearGradient {
        let score = metricsCollector.currentMetrics.focusScore
        if score > 0.7 {
            return LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        } else if score > 0.4 {
            return LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
        }
    }

    private var moodEmoji: String {
        switch metricsCollector.currentMetrics.estimatedMood {
        case .focused: return "🎯"
        case .flowing: return "🔥"
        case .struggling: return "😓"
        case .distracted: return "🤔"
        case .fatigued: return "😴"
        }
    }

    private var moodIcon: String {
        switch metricsCollector.currentMetrics.estimatedMood {
        case .focused: return "target"
        case .flowing: return "flame.fill"
        case .struggling: return "exclamationmark.triangle"
        case .distracted: return "arrow.triangle.branch"
        case .fatigued: return "moon.zzz.fill"
        }
    }

    private var moodColor: Color {
        switch metricsCollector.currentMetrics.estimatedMood {
        case .focused: return .blue
        case .flowing: return .orange
        case .struggling: return .red
        case .distracted: return .yellow
        case .fatigued: return .purple
        }
    }

    // MARK: - Speed Chart

    private var speedChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Writing Performance")
                .font(DesignSystem.Fonts.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            HStack(spacing: 24) {
                // Current WPM
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text(String(format: "%.0f", metricsCollector.currentMetrics.wordsPerMinute))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignSystem.Colors.accent)

                    Text("words/min")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }

                Divider()
                    .frame(height: 50)

                // Peak WPM
                VStack(alignment: .leading, spacing: 4) {
                    Text("Peak")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text(String(format: "%.0f", metricsCollector.currentMetrics.peakWordsPerMinute))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)

                    Text("words/min")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }

                Spacer()

                // Deletion rate gauge
                VStack(alignment: .center, spacing: 4) {
                    Text("Revision Rate")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    ZStack {
                        Circle()
                            .stroke(DesignSystem.Colors.surfaceHighlight, lineWidth: 6)
                            .frame(width: 50, height: 50)

                        Circle()
                            .trim(from: 0, to: min(metricsCollector.currentMetrics.deletionRate / 100, 1))
                            .stroke(deletionRateColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 50, height: 50)
                            .rotationEffect(.degrees(-90))

                        Text(String(format: "%.0f%%", metricsCollector.currentMetrics.deletionRate))
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                }
            }
            .padding()
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius))
        }
    }

    private var deletionRateColor: Color {
        let rate = metricsCollector.currentMetrics.deletionRate
        if rate < 20 { return .green }
        if rate < 40 { return .yellow }
        return .orange
    }

    // MARK: - Commentary Insights

    private var commentaryInsights: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Insights")
                .font(DesignSystem.Fonts.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            VStack(spacing: 8) {
                InsightRow(
                    icon: "bubble.left.and.bubble.right",
                    title: "Commentary Entries",
                    value: "\(commentaryService.currentSessionEntries.count)"
                )

                InsightRow(
                    icon: "lightbulb.fill",
                    title: "Suggestions Offered",
                    value: "\(commentaryService.currentSessionEntries.filter { $0.hasSuggestion }.count)"
                )

                InsightRow(
                    icon: "clock.arrow.circlepath",
                    title: "Session Duration",
                    value: metricsCollector.currentMetrics.formattedSessionTime
                )

                InsightRow(
                    icon: "arrow.left.arrow.right",
                    title: "App Switches",
                    value: "\(metricsCollector.currentMetrics.appSwitchCount)"
                )
            }
            .padding()
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius))
        }
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)

                Spacer()
            }

            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text(title)
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding()
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.smallCornerRadius))
    }
}

// MARK: - Insight Row

private struct InsightRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 20)

            Text(title)
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Spacer()

            Text(value)
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }
}

// MARK: - Preview

#Preview {
    WritingAnalyticsDashboard(
        metricsCollector: WritingMetricsCollector(),
        commentaryService: CommentaryService(aiService: AIProviderService())
    )
    .frame(width: 400, height: 600)
}
