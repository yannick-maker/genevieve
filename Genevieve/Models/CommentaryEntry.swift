import Foundation
import SwiftData

/// Represents a single entry in the commentary stream - either from Genevieve or the user
@Model
final class CommentaryEntry: Identifiable {
    // MARK: - Properties

    var id: UUID
    var timestamp: Date
    var content: String

    /// Whether this message is from the user (dialogue) or from Genevieve
    var isUserMessage: Bool

    /// Document context at time of generation
    var documentType: String?
    var documentSection: String?
    var appName: String?
    var windowTitle: String?

    /// Inline suggestion extracted from commentary (if any)
    var hasSuggestion: Bool
    var suggestionText: String?
    var suggestionAccepted: Bool?
    var suggestionAcceptedAt: Date?

    /// Stuck state at time of generation
    var stuckType: String?
    var stuckScore: Double?

    /// Analytics metadata (JSON-encoded)
    var metadataJSON: Data?

    // MARK: - Relationships

    @Relationship(inverse: \Matter.commentaryEntries)
    var matter: Matter?

    @Relationship(inverse: \WritingSession.commentaryEntries)
    var session: WritingSession?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        content: String,
        isUserMessage: Bool = false,
        documentType: String? = nil,
        documentSection: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.isUserMessage = isUserMessage
        self.documentType = documentType
        self.documentSection = documentSection
        self.appName = appName
        self.windowTitle = windowTitle
        self.hasSuggestion = false
    }

    // MARK: - Computed Properties

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(timestamp) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInYesterday(timestamp) {
            formatter.dateFormat = "'Yesterday' h:mm a"
        } else if calendar.isDate(timestamp, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }

        return formatter.string(from: timestamp)
    }

    var shortTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: timestamp)
    }

    /// Returns the sender name for display
    var senderName: String {
        isUserMessage ? "You" : "Genevieve"
    }

    // MARK: - Metadata Handling

    struct Metadata: Codable {
        var writingSpeedWPM: Double?
        var documentProgress: Double?
        var moodIndicator: String?
        var focusScore: Double?
        var wordCountAtTime: Int?
        var revisionCount: Int?
        var teachingPrincipleReferenced: String?
    }

    var metadata: Metadata? {
        get {
            guard let data = metadataJSON else { return nil }
            return try? JSONDecoder().decode(Metadata.self, from: data)
        }
        set {
            metadataJSON = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: - Suggestion Handling

    /// Extract and store suggestion from content if present
    func extractSuggestion() {
        // Look for [SUGGESTION: ...] pattern
        let pattern = #"\[SUGGESTION:\s*(.+?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return
        }

        let range = NSRange(content.startIndex..., in: content)
        if let match = regex.firstMatch(in: content, options: [], range: range),
           let suggestionRange = Range(match.range(at: 1), in: content) {
            hasSuggestion = true
            suggestionText = String(content[suggestionRange]).trimmingCharacters(in: .whitespaces)
        }
    }

    /// Mark the inline suggestion as accepted
    func acceptSuggestion() {
        guard hasSuggestion else { return }
        suggestionAccepted = true
        suggestionAcceptedAt = Date()
    }

    /// Mark the inline suggestion as rejected
    func rejectSuggestion() {
        guard hasSuggestion else { return }
        suggestionAccepted = false
    }

    /// Returns content with suggestion markers replaced by styled text (for display)
    var displayContent: String {
        // Remove [SUGGESTION: ...] markers for cleaner display
        // The UI will handle highlighting separately
        content
    }

    /// Returns ranges of suggestions in the content for highlighting
    var suggestionRanges: [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        let pattern = #"\[SUGGESTION:\s*(.+?)\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return ranges
        }

        let nsRange = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: nsRange)

        for match in matches {
            if let range = Range(match.range, in: content) {
                ranges.append(range)
            }
        }

        return ranges
    }
}

// MARK: - Search Support

extension CommentaryEntry {
    /// Check if entry matches a search query
    func matches(query: String) -> Bool {
        let lowercaseQuery = query.lowercased()
        return content.lowercased().contains(lowercaseQuery) ||
               (suggestionText?.lowercased().contains(lowercaseQuery) ?? false)
    }
}

// MARK: - Stuck Type Enum

extension CommentaryEntry {
    enum StuckType: String, Codable {
        case pause = "pause"
        case distraction = "distraction"
        case rewriting = "rewriting"
        case navigation = "navigation"

        var displayName: String {
            switch self {
            case .pause: return "Pausing"
            case .distraction: return "Distracted"
            case .rewriting: return "Rewriting"
            case .navigation: return "Navigating"
            }
        }

        var genevieveObservation: String {
            switch self {
            case .pause:
                return "taking a moment to think"
            case .distraction:
                return "stepping away briefly"
            case .rewriting:
                return "refining the phrasing"
            case .navigation:
                return "reviewing earlier sections"
            }
        }
    }

    var stuckTypeEnum: StuckType? {
        get { stuckType.flatMap { StuckType(rawValue: $0) } }
        set { stuckType = newValue?.rawValue }
    }
}
