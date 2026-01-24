import SwiftUI

/// View showing matter/case context
struct MatterContextView: View {
    @ObservedObject var contextAnalyzer: ContextAnalyzer

    var body: some View {
        if let analysis = contextAnalyzer.currentAnalysis {
            matterDetailView(analysis)
        } else {
            noMatterView
        }
    }

    // MARK: - No Matter State

    private var noMatterView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            VStack(spacing: 12) {
                Text("No Matter Detected")
                    .font(DesignSystem.Fonts.title)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Open a document and I'll try to detect the matter or case context.")
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Matter Detail View

    private func matterDetailView(_ analysis: ContextAnalyzer.DocumentAnalysis) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Document Type Section
                contextSection(
                    title: "Document Type",
                    icon: "doc.text",
                    content: {
                        Text(analysis.documentType.displayName)
                            .font(DesignSystem.Fonts.body)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                )

                // Section if detected
                if let section = analysis.section, section != .unknown {
                    contextSection(
                        title: "Current Section",
                        icon: "list.bullet",
                        content: {
                            Text(section.displayName)
                                .font(DesignSystem.Fonts.body)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                        }
                    )
                }

                // Writing Tone
                contextSection(
                    title: "Writing Tone",
                    icon: "text.bubble",
                    content: {
                        Text(analysis.tone.displayName)
                            .font(DesignSystem.Fonts.body)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                )

                // Confidence
                contextSection(
                    title: "Analysis Confidence",
                    icon: "gauge",
                    content: {
                        HStack(spacing: 8) {
                            ProgressView(value: analysis.confidence)
                                .tint(confidenceColor(for: analysis.confidence))

                            Text("\(Int(analysis.confidence * 100))%")
                                .font(DesignSystem.Fonts.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                    }
                )

                Divider()
                    .padding(.vertical, 8)

                // Tips for this document type
                documentTypeTips(for: analysis.documentType)
            }
            .padding(DesignSystem.Metrics.padding)
        }
    }

    // MARK: - Context Section

    private func contextSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            content()
        }
        .padding(DesignSystem.Metrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius))
    }

    // MARK: - Document Type Tips

    private func documentTypeTips(for type: ContextAnalyzer.DocumentType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips for \(type.displayName)")
                .font(DesignSystem.Fonts.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(tips(for: type), id: \.self) { tip in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.accent)

                        Text(tip)
                            .font(DesignSystem.Fonts.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(DesignSystem.Metrics.padding)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Metrics.cornerRadius))
    }

    private func tips(for type: ContextAnalyzer.DocumentType) -> [String] {
        switch type {
        case .brief, .motion:
            return [
                "Use strong topic sentences",
                "Cite legal standards precisely",
                "Include specific factual support"
            ]
        case .contract:
            return [
                "Define key terms clearly",
                "Specify obligations precisely",
                "Address risk allocation"
            ]
        case .memo:
            return [
                "State issues clearly",
                "Provide balanced analysis",
                "Include practical recommendations"
            ]
        case .email:
            return [
                "Be concise and direct",
                "Use professional tone",
                "Clear call-to-action"
            ]
        default:
            return [
                "Focus on clarity",
                "Be precise with language",
                "Review for consistency"
            ]
        }
    }

    private func confidenceColor(for confidence: Double) -> Color {
        switch confidence {
        case 0.8...1.0:
            return .green
        case 0.5..<0.8:
            return .orange
        default:
            return .red
        }
    }
}
