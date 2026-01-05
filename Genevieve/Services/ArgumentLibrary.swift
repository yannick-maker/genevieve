import Foundation
import SwiftData
import Combine

/// Service for managing the argument library - storing and retrieving reusable legal arguments
@MainActor
final class ArgumentLibrary: ObservableObject {
    // MARK: - Published State

    @Published private(set) var arguments: [Argument] = []
    @Published private(set) var favorites: [Argument] = []
    @Published private(set) var recentlyUsed: [Argument] = []
    @Published var searchQuery: String = ""
    @Published var selectedCategory: Argument.ArgumentCategory?
    @Published var selectedJurisdiction: String?

    // MARK: - Computed Properties

    var filteredArguments: [Argument] {
        var results = arguments

        // Apply search filter
        if !searchQuery.isEmpty {
            results = results.filter { $0.matches(query: searchQuery) }
        }

        // Apply category filter
        if let category = selectedCategory {
            results = results.filter { $0.argumentCategory == category }
        }

        // Apply jurisdiction filter
        if let jurisdiction = selectedJurisdiction {
            results = results.filter { $0.jurisdiction == jurisdiction }
        }

        return results
    }

    var categories: [Argument.ArgumentCategory] {
        let usedCategories = Set(arguments.compactMap { $0.argumentCategory })
        return Array(usedCategories).sorted { $0.rawValue < $1.rawValue }
    }

    var jurisdictions: [String] {
        let usedJurisdictions = Set(arguments.compactMap { $0.jurisdiction })
        return Array(usedJurisdictions).sorted()
    }

    var argumentsByCategory: [String: [Argument]] {
        var grouped: [String: [Argument]] = [:]

        for argument in filteredArguments {
            let category = argument.argumentCategory?.group ?? "Other"
            if grouped[category] == nil {
                grouped[category] = []
            }
            grouped[category]?.append(argument)
        }

        return grouped
    }

    // MARK: - Storage

    private var modelContext: ModelContext?

    // MARK: - Initialization

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    // MARK: - CRUD Operations

    /// Load arguments from storage
    func loadArguments() {
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<Argument>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        guard let fetched = try? modelContext.fetch(descriptor) else { return }

        arguments = fetched
        favorites = arguments.filter { $0.isFavorite }
        recentlyUsed = Array(
            arguments
                .filter { $0.lastUsedAt != nil }
                .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
                .prefix(10)
        )
    }

    /// Create a new argument
    @discardableResult
    func createArgument(
        title: String,
        content: String,
        summary: String? = nil,
        category: Argument.ArgumentCategory? = nil,
        tags: [String] = [],
        jurisdiction: String? = nil,
        practiceArea: String? = nil,
        sourceType: Argument.SourceType = .userCreated
    ) -> Argument {
        let argument = Argument(
            title: title,
            content: content,
            summary: summary,
            category: category?.rawValue,
            tags: tags,
            jurisdiction: jurisdiction,
            sourceType: sourceType
        )

        argument.practiceArea = practiceArea

        modelContext?.insert(argument)
        try? modelContext?.save()

        arguments.insert(argument, at: 0)

        return argument
    }

    /// Create argument from an accepted suggestion
    @discardableResult
    func createFromSuggestion(_ suggestion: DraftSuggestion) -> Argument? {
        let argument = Argument(
            title: "Saved from suggestion",
            content: suggestion.suggestedText,
            summary: suggestion.explanation,
            sourceType: .fromSuggestion
        )

        argument.originalSuggestionID = suggestion.id
        argument.sourceDocumentTitle = suggestion.session?.documentTitle
        argument.sourceMatterName = suggestion.matter?.name

        modelContext?.insert(argument)
        try? modelContext?.save()

        arguments.insert(argument, at: 0)

        return argument
    }

    /// Update an existing argument
    func updateArgument(_ argument: Argument) {
        argument.updatedAt = Date()
        try? modelContext?.save()

        // Update local arrays
        if argument.isFavorite && !favorites.contains(where: { $0.id == argument.id }) {
            favorites.insert(argument, at: 0)
        } else if !argument.isFavorite {
            favorites.removeAll { $0.id == argument.id }
        }
    }

    /// Delete an argument
    func deleteArgument(_ argument: Argument) {
        modelContext?.delete(argument)
        try? modelContext?.save()

        arguments.removeAll { $0.id == argument.id }
        favorites.removeAll { $0.id == argument.id }
        recentlyUsed.removeAll { $0.id == argument.id }
    }

    /// Toggle favorite status
    func toggleFavorite(_ argument: Argument) {
        argument.toggleFavorite()
        updateArgument(argument)
    }

    // MARK: - Usage Tracking

    /// Record usage of an argument
    func recordUsage(_ argument: Argument) {
        argument.recordUsage()
        try? modelContext?.save()

        // Update recently used
        recentlyUsed.removeAll { $0.id == argument.id }
        recentlyUsed.insert(argument, at: 0)
        if recentlyUsed.count > 10 {
            recentlyUsed = Array(recentlyUsed.prefix(10))
        }
    }

    // MARK: - Search

    /// Search arguments by query
    func search(query: String) -> [Argument] {
        guard !query.isEmpty else { return arguments }
        return arguments.filter { $0.matches(query: query) }
    }

    /// Search by tag
    func findByTag(_ tag: String) -> [Argument] {
        arguments.filter { $0.tags.contains(tag.lowercased()) }
    }

    /// Search by category
    func findByCategory(_ category: Argument.ArgumentCategory) -> [Argument] {
        arguments.filter { $0.argumentCategory == category }
    }

    /// Find related arguments (same matter, similar tags)
    func findRelated(to argument: Argument) -> [Argument] {
        let relatedByMatter = arguments.filter {
            $0.id != argument.id &&
            $0.matter?.id == argument.matter?.id &&
            argument.matter != nil
        }

        let relatedByTags = arguments.filter {
            $0.id != argument.id &&
            !Set($0.tags).intersection(argument.tags).isEmpty
        }

        // Combine and dedupe
        var related = relatedByMatter
        for arg in relatedByTags {
            if !related.contains(where: { $0.id == arg.id }) {
                related.append(arg)
            }
        }

        return Array(related.prefix(5))
    }

    // MARK: - Smart Suggestions

    /// Get suggested arguments based on current context
    func suggestArguments(
        for documentType: ContextAnalyzer.DocumentType,
        section: ContextAnalyzer.DocumentSection?,
        matter: Matter?
    ) -> [Argument] {
        var scored: [(argument: Argument, score: Double)] = []

        for argument in arguments {
            var score = 0.0

            // Boost for same matter
            if let matter = matter, argument.matter?.id == matter.id {
                score += 50
            }

            // Boost for matching document type
            if argument.practiceArea == documentType.rawValue {
                score += 20
            }

            // Boost for favorites
            if argument.isFavorite {
                score += 15
            }

            // Boost for frequently used
            score += min(Double(argument.usageCount) * 2, 20)

            // Boost for recently used
            if let lastUsed = argument.lastUsedAt {
                let daysSinceUse = Date().timeIntervalSince(lastUsed) / 86400
                if daysSinceUse < 7 {
                    score += 10 * (1 - daysSinceUse / 7)
                }
            }

            if score > 0 {
                scored.append((argument, score))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map { $0.argument }
    }

    // MARK: - Import/Export

    /// Export all arguments to JSON
    func exportToJSON() -> Data? {
        let exportData = arguments.map { $0.toDictionary() }
        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }

    /// Import arguments from JSON
    func importFromJSON(_ data: Data) -> Int {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return 0
        }

        var importCount = 0

        for dict in jsonArray {
            if let argument = Argument.fromDictionary(dict) {
                modelContext?.insert(argument)
                arguments.append(argument)
                importCount += 1
            }
        }

        try? modelContext?.save()

        return importCount
    }

    /// Export to CSV
    func exportToCSV() -> String {
        var csv = "Title,Content,Category,Tags,Jurisdiction,Created,Usage Count\n"

        for argument in arguments {
            let title = argument.title.replacingOccurrences(of: ",", with: ";")
            let content = argument.content.replacingOccurrences(of: ",", with: ";")
                .replacingOccurrences(of: "\n", with: " ")
            let category = argument.category ?? ""
            let tags = argument.tags.joined(separator: ";")
            let jurisdiction = argument.jurisdiction ?? ""
            let created = ISO8601DateFormatter().string(from: argument.createdAt)

            csv += "\"\(title)\",\"\(content)\",\"\(category)\",\"\(tags)\",\"\(jurisdiction)\",\"\(created)\",\(argument.usageCount)\n"
        }

        return csv
    }

    // MARK: - Filters

    /// Clear all filters
    func clearFilters() {
        searchQuery = ""
        selectedCategory = nil
        selectedJurisdiction = nil
    }
}

// MARK: - Argument Detection

extension ArgumentLibrary {
    /// Detect if text contains a strong argument worth saving
    func detectStrongArgument(in text: String) -> Bool {
        let indicators = [
            "therefore", "consequently", "as established",
            "pursuant to", "under the standard", "applies because",
            "court held", "precedent", "controlling authority"
        ]

        let lowercased = text.lowercased()
        let matchCount = indicators.filter { lowercased.contains($0) }.count

        return matchCount >= 2 && text.count >= 100
    }

    /// Extract potential argument from text
    func extractArgument(from text: String) -> (title: String, content: String)? {
        guard detectStrongArgument(in: text) else { return nil }

        // Find a good title (first sentence or key phrase)
        let sentences = text.components(separatedBy: ". ")
        let title: String

        if let first = sentences.first, first.count < 100 {
            title = first
        } else {
            title = String(text.prefix(80)) + "..."
        }

        return (title: title, content: text)
    }
}
