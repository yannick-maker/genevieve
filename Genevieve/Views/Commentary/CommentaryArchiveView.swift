import SwiftUI
import SwiftData

/// Searchable archive view for browsing past commentary entries
struct CommentaryArchiveView: View {
    @ObservedObject var commentaryService: CommentaryService
    @Environment(\.modelContext) private var modelContext

    @State private var searchQuery = ""
    @State private var selectedFilter: FilterType = .all
    @State private var selectedDateRange: DateRange = .allTime
    @State private var selectedMatter: Matter?
    @State private var searchResults: [CommentaryEntry] = []
    @State private var isSearching = false

    enum FilterType: String, CaseIterable, Identifiable {
        case all = "All"
        case genevieve = "Genevieve Only"
        case dialogue = "Dialogue Only"
        case withSuggestions = "With Suggestions"

        var id: String { rawValue }
    }

    enum DateRange: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case allTime = "All Time"

        var id: String { rawValue }

        var dateInterval: ClosedRange<Date>? {
            let calendar = Calendar.current
            let now = Date()

            switch self {
            case .today:
                let start = calendar.startOfDay(for: now)
                return start...now
            case .week:
                guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
                return start...now
            case .month:
                guard let start = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
                return start...now
            case .allTime:
                return nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search header
            searchHeader

            Divider()

            // Filter bar
            filterBar

            Divider()

            // Results
            if isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .onAppear {
            performSearch()
        }
        .onChange(of: searchQuery) { _, _ in
            performSearchDebounced()
        }
        .onChange(of: selectedFilter) { _, _ in
            performSearch()
        }
        .onChange(of: selectedDateRange) { _, _ in
            performSearch()
        }
    }

    // MARK: - Search Header

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            TextField("Search commentary...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(DesignSystem.Fonts.body)

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Metrics.padding)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Type filter
                Menu {
                    ForEach(FilterType.allCases) { filter in
                        Button(filter.rawValue) {
                            selectedFilter = filter
                        }
                    }
                } label: {
                    filterChip(
                        icon: "line.3.horizontal.decrease.circle",
                        text: selectedFilter.rawValue,
                        isActive: selectedFilter != .all
                    )
                }

                // Date range filter
                Menu {
                    ForEach(DateRange.allCases) { range in
                        Button(range.rawValue) {
                            selectedDateRange = range
                        }
                    }
                } label: {
                    filterChip(
                        icon: "calendar",
                        text: selectedDateRange.rawValue,
                        isActive: selectedDateRange != .allTime
                    )
                }

                Spacer()

                // Result count
                Text("\(searchResults.count) entries")
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, DesignSystem.Metrics.padding)
            .padding(.vertical, 8)
        }
    }

    private func filterChip(icon: String, text: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(DesignSystem.Fonts.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? DesignSystem.Colors.accent.opacity(0.2) : Color.clear)
        .foregroundStyle(isActive ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(DesignSystem.Colors.textTertiary.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(groupedResults.keys.sorted().reversed(), id: \.self) { dateKey in
                    if let entries = groupedResults[dateKey] {
                        Section {
                            ForEach(entries) { entry in
                                ArchiveEntryRow(entry: entry, searchQuery: searchQuery)
                            }
                        } header: {
                            Text(dateKey)
                                .font(DesignSystem.Fonts.caption)
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DesignSystem.Metrics.padding)
                                .padding(.vertical, 8)
                                .background(Color(nsColor: .windowBackgroundColor))
                        }
                    }
                }
            }
        }
    }

    private var groupedResults: [String: [CommentaryEntry]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"

        return Dictionary(grouping: searchResults) { entry in
            formatter.string(from: entry.timestamp)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: searchQuery.isEmpty ? "archivebox" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text(searchQuery.isEmpty ? "No Commentary Yet" : "No Results")
                .font(DesignSystem.Fonts.title)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text(searchQuery.isEmpty
                 ? "Start a writing session with Genevieve to build your commentary history."
                 : "Try adjusting your search or filters.")
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Search

    @State private var searchTask: Task<Void, Never>?

    private func performSearchDebounced() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            performSearch()
        }
    }

    private func performSearch() {
        isSearching = true

        var results = commentaryService.searchEntries(
            query: searchQuery,
            dateRange: selectedDateRange.dateInterval,
            matterId: selectedMatter?.id,
            limit: 200
        )

        // Apply type filter
        switch selectedFilter {
        case .all:
            break
        case .genevieve:
            results = results.filter { !$0.isUserMessage }
        case .dialogue:
            results = results.filter { $0.isUserMessage }
        case .withSuggestions:
            results = results.filter { $0.hasSuggestion }
        }

        searchResults = results
        isSearching = false
    }
}

// MARK: - Archive Entry Row

struct ArchiveEntryRow: View {
    let entry: CommentaryEntry
    let searchQuery: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: entry.isUserMessage ? "person.fill" : "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(entry.isUserMessage ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.accent)

                Text(entry.senderName)
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(entry.isUserMessage ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.accent)

                if entry.hasSuggestion {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                Spacer()

                Text(entry.formattedTimestamp)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            // Content preview or full content
            Text(isExpanded ? entry.content : String(entry.content.prefix(150)) + (entry.content.count > 150 ? "..." : ""))
                .font(DesignSystem.Fonts.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(isExpanded ? nil : 3)

            // Context badges
            if let docType = entry.documentType {
                HStack(spacing: 6) {
                    Text(docType)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.accent.opacity(0.1))
                        .clipShape(Capsule())

                    if let matter = entry.matter {
                        Text(matter.name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(DesignSystem.Metrics.padding)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CommentaryArchiveView(
        commentaryService: CommentaryService(
            aiService: AIProviderService()
        )
    )
    .frame(width: 400, height: 600)
}
