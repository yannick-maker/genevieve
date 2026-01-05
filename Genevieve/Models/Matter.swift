import Foundation
import SwiftData

/// Represents a legal matter/case/project that the user is working on
@Model
final class Matter {
    // MARK: - Properties

    var id: UUID
    var createdAt: Date
    var updatedAt: Date

    // Basic info
    var name: String
    var clientName: String?
    var matterNumber: String?
    var descriptionText: String?

    // Classification
    var matterType: String?
    var jurisdiction: String?
    var practiceArea: String?

    // Status
    var status: String // active, completed, archived
    var priority: String? // high, medium, low

    // Key dates
    var filingDeadline: Date?
    var trialDate: Date?
    var customDeadlines: [String: Date]?

    // Time tracking
    var totalTimeSpent: TimeInterval
    var lastActivityAt: Date?

    // Relationships
    @Relationship(deleteRule: .nullify)
    var sessions: [WritingSession]?

    @Relationship(deleteRule: .cascade, inverse: \Argument.matter)
    var arguments: [Argument]?

    // Notes
    var notes: String?

    // Detection patterns (for auto-detection)
    var documentPatterns: [String]?
    var windowTitlePatterns: [String]?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        clientName: String? = nil,
        matterNumber: String? = nil,
        matterType: String? = nil
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.name = name
        self.clientName = clientName
        self.matterNumber = matterNumber
        self.matterType = matterType
        self.status = MatterStatus.active.rawValue
        self.totalTimeSpent = 0
    }

    // MARK: - Computed Properties

    var matterStatus: MatterStatus {
        get { MatterStatus(rawValue: status) ?? .active }
        set {
            status = newValue.rawValue
            updatedAt = Date()
        }
    }

    var matterPriority: MatterPriority? {
        get { priority.flatMap { MatterPriority(rawValue: $0) } }
        set {
            priority = newValue?.rawValue
            updatedAt = Date()
        }
    }

    var isActive: Bool {
        matterStatus == .active
    }

    var sessionCount: Int {
        sessions?.count ?? 0
    }

    var argumentCount: Int {
        arguments?.count ?? 0
    }

    var formattedTimeSpent: String {
        let hours = Int(totalTimeSpent) / 3600
        let minutes = (Int(totalTimeSpent) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var upcomingDeadline: Date? {
        var deadlines: [Date] = []

        if let filing = filingDeadline, filing > Date() {
            deadlines.append(filing)
        }
        if let trial = trialDate, trial > Date() {
            deadlines.append(trial)
        }
        if let custom = customDeadlines {
            deadlines.append(contentsOf: custom.values.filter { $0 > Date() })
        }

        return deadlines.sorted().first
    }

    var daysUntilDeadline: Int? {
        guard let deadline = upcomingDeadline else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: deadline)
        return components.day
    }

    // MARK: - Methods

    func addTime(_ duration: TimeInterval) {
        totalTimeSpent += duration
        lastActivityAt = Date()
        updatedAt = Date()
    }

    func complete() {
        matterStatus = .completed
    }

    func archive() {
        matterStatus = .archived
    }

    func reactivate() {
        matterStatus = .active
    }

    /// Check if a document belongs to this matter based on patterns
    func matches(documentTitle: String?, windowTitle: String?) -> Bool {
        let title = (documentTitle ?? "").lowercased()
        let window = (windowTitle ?? "").lowercased()

        // Check matter number
        if let number = matterNumber?.lowercased(),
           title.contains(number) || window.contains(number) {
            return true
        }

        // Check client name
        if let client = clientName?.lowercased(),
           title.contains(client) || window.contains(client) {
            return true
        }

        // Check matter name
        if title.contains(name.lowercased()) || window.contains(name.lowercased()) {
            return true
        }

        // Check custom patterns
        if let patterns = documentPatterns {
            for pattern in patterns {
                if title.contains(pattern.lowercased()) {
                    return true
                }
            }
        }

        if let patterns = windowTitlePatterns {
            for pattern in patterns {
                if window.contains(pattern.lowercased()) {
                    return true
                }
            }
        }

        return false
    }

    func addPattern(_ pattern: String, isWindowTitle: Bool = false) {
        if isWindowTitle {
            if windowTitlePatterns == nil {
                windowTitlePatterns = []
            }
            windowTitlePatterns?.append(pattern)
        } else {
            if documentPatterns == nil {
                documentPatterns = []
            }
            documentPatterns?.append(pattern)
        }
        updatedAt = Date()
    }
}

// MARK: - Supporting Types

extension Matter {
    enum MatterStatus: String, Codable, CaseIterable {
        case active
        case completed
        case archived

        var displayName: String {
            rawValue.capitalized
        }

        var icon: String {
            switch self {
            case .active: return "folder.fill"
            case .completed: return "checkmark.circle.fill"
            case .archived: return "archivebox.fill"
            }
        }
    }

    enum MatterPriority: String, Codable, CaseIterable {
        case high
        case medium
        case low

        var displayName: String {
            rawValue.capitalized
        }

        var icon: String {
            switch self {
            case .high: return "exclamationmark.circle.fill"
            case .medium: return "minus.circle.fill"
            case .low: return "arrow.down.circle.fill"
            }
        }

        var color: String {
            switch self {
            case .high: return "red"
            case .medium: return "orange"
            case .low: return "blue"
            }
        }
    }

    enum MatterType: String, Codable, CaseIterable {
        case litigation
        case transactional
        case regulatory
        case advisory
        case proBonoCase = "pro_bono"
        case other

        var displayName: String {
            switch self {
            case .litigation: return "Litigation"
            case .transactional: return "Transactional"
            case .regulatory: return "Regulatory"
            case .advisory: return "Advisory"
            case .proBonoCase: return "Pro Bono"
            case .other: return "Other"
            }
        }
    }

    enum PracticeArea: String, Codable, CaseIterable {
        case corporate
        case litigation
        case intellectualProperty = "ip"
        case employment
        case realEstate = "real_estate"
        case tax
        case bankruptcy
        case environmental
        case healthcare
        case criminalDefense = "criminal"
        case familyLaw = "family"
        case immigration
        case other

        var displayName: String {
            switch self {
            case .corporate: return "Corporate"
            case .litigation: return "Litigation"
            case .intellectualProperty: return "Intellectual Property"
            case .employment: return "Employment"
            case .realEstate: return "Real Estate"
            case .tax: return "Tax"
            case .bankruptcy: return "Bankruptcy"
            case .environmental: return "Environmental"
            case .healthcare: return "Healthcare"
            case .criminalDefense: return "Criminal Defense"
            case .familyLaw: return "Family Law"
            case .immigration: return "Immigration"
            case .other: return "Other"
            }
        }
    }
}

// MARK: - Matter Statistics

extension Matter {
    struct MatterStats {
        let totalSessions: Int
        let totalTime: TimeInterval
        let averageSessionLength: TimeInterval
        let suggestionsAccepted: Int
        let suggestionsTotal: Int
        let argumentsSaved: Int

        var acceptanceRate: Double {
            guard suggestionsTotal > 0 else { return 0 }
            return Double(suggestionsAccepted) / Double(suggestionsTotal)
        }
    }

    func calculateStats() -> MatterStats {
        let sessionList = sessions ?? []

        let totalTime = sessionList.reduce(0) { $0 + $1.duration }
        let avgLength = sessionList.isEmpty ? 0 : totalTime / Double(sessionList.count)
        let accepted = sessionList.reduce(0) { $0 + $1.suggestionsAccepted }
        let total = sessionList.reduce(0) { $0 + $1.suggestionsShown }

        return MatterStats(
            totalSessions: sessionList.count,
            totalTime: totalTime,
            averageSessionLength: avgLength,
            suggestionsAccepted: accepted,
            suggestionsTotal: total,
            argumentsSaved: arguments?.count ?? 0
        )
    }
}
