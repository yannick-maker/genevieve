import Foundation
import SwiftData

/// Represents a reusable legal argument stored in the argument library
@Model
final class Argument {
    // MARK: - Properties

    var id: UUID
    var createdAt: Date
    var updatedAt: Date

    // Content
    var title: String
    var content: String
    var summary: String?

    // Classification
    var category: String?
    var tags: [String]
    var jurisdiction: String?
    var practiceArea: String?

    // Legal context
    var legalBasis: String?
    var supportingCitations: [String]
    var opposingCitations: [String]
    var keyPrecedents: [String]

    // Source tracking
    var sourceType: String // user_created, ai_generated, imported, from_suggestion
    var sourceDocumentTitle: String?
    var sourceMatterName: String?
    var originalSuggestionID: UUID?

    // Usage tracking
    var usageCount: Int
    var lastUsedAt: Date?
    var successRate: Double? // How often this argument led to accepted suggestions

    // Quality signals
    var isFavorite: Bool
    var rating: Int? // 1-5 stars
    var notes: String?

    // Relationships
    var matter: Matter?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        summary: String? = nil,
        category: String? = nil,
        tags: [String] = [],
        jurisdiction: String? = nil,
        sourceType: SourceType = .userCreated
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.title = title
        self.content = content
        self.summary = summary
        self.category = category
        self.tags = tags
        self.jurisdiction = jurisdiction
        self.sourceType = sourceType.rawValue
        self.supportingCitations = []
        self.opposingCitations = []
        self.keyPrecedents = []
        self.usageCount = 0
        self.isFavorite = false
    }

    // MARK: - Computed Properties

    var source: SourceType {
        get { SourceType(rawValue: sourceType) ?? .userCreated }
        set {
            sourceType = newValue.rawValue
            updatedAt = Date()
        }
    }

    var argumentCategory: ArgumentCategory? {
        get { category.flatMap { ArgumentCategory(rawValue: $0) } }
        set {
            category = newValue?.rawValue
            updatedAt = Date()
        }
    }

    var wordCount: Int {
        content.split(separator: " ").count
    }

    var hasCitations: Bool {
        !supportingCitations.isEmpty || !keyPrecedents.isEmpty
    }

    var totalCitationCount: Int {
        supportingCitations.count + opposingCitations.count + keyPrecedents.count
    }

    var displayTags: String {
        tags.joined(separator: ", ")
    }

    // MARK: - Methods

    func recordUsage() {
        usageCount += 1
        lastUsedAt = Date()
        updatedAt = Date()
    }

    func toggleFavorite() {
        isFavorite.toggle()
        updatedAt = Date()
    }

    func setRating(_ stars: Int) {
        rating = max(1, min(5, stars))
        updatedAt = Date()
    }

    func addTag(_ tag: String) {
        let normalized = tag.lowercased().trimmingCharacters(in: .whitespaces)
        if !tags.contains(normalized) {
            tags.append(normalized)
            updatedAt = Date()
        }
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0.lowercased() == tag.lowercased() }
        updatedAt = Date()
    }

    func addCitation(_ citation: String, isSupporting: Bool = true) {
        if isSupporting {
            supportingCitations.append(citation)
        } else {
            opposingCitations.append(citation)
        }
        updatedAt = Date()
    }

    func addPrecedent(_ precedent: String) {
        keyPrecedents.append(precedent)
        updatedAt = Date()
    }

    /// Check if this argument matches a search query
    func matches(query: String) -> Bool {
        let lowercased = query.lowercased()

        if title.lowercased().contains(lowercased) { return true }
        if content.lowercased().contains(lowercased) { return true }
        if summary?.lowercased().contains(lowercased) == true { return true }
        if tags.contains(where: { $0.contains(lowercased) }) { return true }
        if category?.lowercased().contains(lowercased) == true { return true }

        return false
    }

    /// Check if argument matches filters
    func matches(
        category: ArgumentCategory? = nil,
        jurisdiction: String? = nil,
        practiceArea: String? = nil,
        tag: String? = nil
    ) -> Bool {
        if let cat = category, argumentCategory != cat { return false }
        if let jur = jurisdiction, self.jurisdiction != jur { return false }
        if let area = practiceArea, self.practiceArea != area { return false }
        if let t = tag, !tags.contains(t.lowercased()) { return false }
        return true
    }
}

// MARK: - Supporting Types

extension Argument {
    enum SourceType: String, Codable, CaseIterable {
        case userCreated = "user_created"
        case aiGenerated = "ai_generated"
        case imported
        case fromSuggestion = "from_suggestion"

        var displayName: String {
            switch self {
            case .userCreated: return "User Created"
            case .aiGenerated: return "AI Generated"
            case .imported: return "Imported"
            case .fromSuggestion: return "From Suggestion"
            }
        }

        var icon: String {
            switch self {
            case .userCreated: return "person.fill"
            case .aiGenerated: return "brain"
            case .imported: return "square.and.arrow.down"
            case .fromSuggestion: return "lightbulb.fill"
            }
        }
    }

    enum ArgumentCategory: String, Codable, CaseIterable {
        // Procedural
        case jurisdiction
        case standingProcedural = "standing"
        case statueOfLimitations = "sol"
        case motionToDismiss = "mtd"
        case summaryJudgment = "msj"

        // Substantive
        case liability
        case damages
        case defenses
        case affirmativeDefenses = "aff_def"

        // Contract
        case breach
        case interpretation
        case formation
        case performance
        case remedies

        // Evidence
        case admissibility
        case authentication
        case hearsay
        case expertTestimony = "expert"

        // Constitutional
        case dueProcess = "due_process"
        case equalProtection = "equal_protection"
        case firstAmendment = "first_amendment"
        case fourthAmendment = "fourth_amendment"

        // General
        case standardOfReview = "std_review"
        case policyArgument = "policy"
        case other

        var displayName: String {
            switch self {
            case .jurisdiction: return "Jurisdiction"
            case .standingProcedural: return "Standing"
            case .statueOfLimitations: return "Statute of Limitations"
            case .motionToDismiss: return "Motion to Dismiss"
            case .summaryJudgment: return "Summary Judgment"
            case .liability: return "Liability"
            case .damages: return "Damages"
            case .defenses: return "Defenses"
            case .affirmativeDefenses: return "Affirmative Defenses"
            case .breach: return "Breach"
            case .interpretation: return "Contract Interpretation"
            case .formation: return "Contract Formation"
            case .performance: return "Performance"
            case .remedies: return "Remedies"
            case .admissibility: return "Admissibility"
            case .authentication: return "Authentication"
            case .hearsay: return "Hearsay"
            case .expertTestimony: return "Expert Testimony"
            case .dueProcess: return "Due Process"
            case .equalProtection: return "Equal Protection"
            case .firstAmendment: return "First Amendment"
            case .fourthAmendment: return "Fourth Amendment"
            case .standardOfReview: return "Standard of Review"
            case .policyArgument: return "Policy Argument"
            case .other: return "Other"
            }
        }

        var group: String {
            switch self {
            case .jurisdiction, .standingProcedural, .statueOfLimitations, .motionToDismiss, .summaryJudgment:
                return "Procedural"
            case .liability, .damages, .defenses, .affirmativeDefenses:
                return "Substantive"
            case .breach, .interpretation, .formation, .performance, .remedies:
                return "Contract"
            case .admissibility, .authentication, .hearsay, .expertTestimony:
                return "Evidence"
            case .dueProcess, .equalProtection, .firstAmendment, .fourthAmendment:
                return "Constitutional"
            case .standardOfReview, .policyArgument, .other:
                return "General"
            }
        }
    }
}

// MARK: - Argument Export

extension Argument {
    /// Export argument to dictionary for JSON serialization
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "title": title,
            "content": content,
            "tags": tags,
            "sourceType": sourceType,
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "usageCount": usageCount
        ]

        if let summary = summary { dict["summary"] = summary }
        if let category = category { dict["category"] = category }
        if let jurisdiction = jurisdiction { dict["jurisdiction"] = jurisdiction }
        if let practiceArea = practiceArea { dict["practiceArea"] = practiceArea }
        if let legalBasis = legalBasis { dict["legalBasis"] = legalBasis }
        if !supportingCitations.isEmpty { dict["supportingCitations"] = supportingCitations }
        if !opposingCitations.isEmpty { dict["opposingCitations"] = opposingCitations }
        if !keyPrecedents.isEmpty { dict["keyPrecedents"] = keyPrecedents }
        if let rating = rating { dict["rating"] = rating }
        if let notes = notes { dict["notes"] = notes }

        return dict
    }

    /// Create argument from dictionary
    static func fromDictionary(_ dict: [String: Any]) -> Argument? {
        guard let title = dict["title"] as? String,
              let content = dict["content"] as? String else {
            return nil
        }

        let argument = Argument(
            title: title,
            content: content,
            summary: dict["summary"] as? String,
            category: dict["category"] as? String,
            tags: dict["tags"] as? [String] ?? [],
            jurisdiction: dict["jurisdiction"] as? String,
            sourceType: .imported
        )

        argument.practiceArea = dict["practiceArea"] as? String
        argument.legalBasis = dict["legalBasis"] as? String
        argument.supportingCitations = dict["supportingCitations"] as? [String] ?? []
        argument.opposingCitations = dict["opposingCitations"] as? [String] ?? []
        argument.keyPrecedents = dict["keyPrecedents"] as? [String] ?? []
        argument.rating = dict["rating"] as? Int
        argument.notes = dict["notes"] as? String

        return argument
    }
}
