import Foundation
import SwiftData
import Combine

/// Service for tracking and managing legal matters
@MainActor
final class MatterTracker: ObservableObject {
    // MARK: - Published State

    @Published private(set) var matters: [Matter] = []
    @Published private(set) var activeMatters: [Matter] = []
    @Published private(set) var currentMatter: Matter?
    @Published var searchQuery: String = ""

    // MARK: - Computed Properties

    var filteredMatters: [Matter] {
        if searchQuery.isEmpty {
            return matters
        }
        return matters.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery) ||
            $0.clientName?.localizedCaseInsensitiveContains(searchQuery) == true ||
            $0.matterNumber?.localizedCaseInsensitiveContains(searchQuery) == true
        }
    }

    var mattersWithDeadlines: [Matter] {
        matters.filter { $0.upcomingDeadline != nil }
            .sorted { ($0.upcomingDeadline ?? .distantFuture) < ($1.upcomingDeadline ?? .distantFuture) }
    }

    var recentlyActiveMaters: [Matter] {
        matters
            .filter { $0.lastActivityAt != nil }
            .sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Storage

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    // MARK: - Loading

    /// Load matters from storage
    func loadMatters() {
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<Matter>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        guard let fetched = try? modelContext.fetch(descriptor) else { return }

        matters = fetched
        activeMatters = matters.filter { $0.isActive }
    }

    // MARK: - CRUD Operations

    /// Create a new matter
    @discardableResult
    func createMatter(
        name: String,
        clientName: String? = nil,
        matterNumber: String? = nil,
        matterType: Matter.MatterType? = nil,
        practiceArea: Matter.PracticeArea? = nil
    ) -> Matter {
        let matter = Matter(
            name: name,
            clientName: clientName,
            matterNumber: matterNumber,
            matterType: matterType?.rawValue
        )

        matter.practiceArea = practiceArea?.rawValue

        modelContext?.insert(matter)
        try? modelContext?.save()

        matters.insert(matter, at: 0)
        if matter.isActive {
            activeMatters.insert(matter, at: 0)
        }

        return matter
    }

    /// Update a matter
    func updateMatter(_ matter: Matter) {
        matter.updatedAt = Date()
        try? modelContext?.save()

        // Update active matters list
        if matter.isActive && !activeMatters.contains(where: { $0.id == matter.id }) {
            activeMatters.insert(matter, at: 0)
        } else if !matter.isActive {
            activeMatters.removeAll { $0.id == matter.id }
        }
    }

    /// Delete a matter
    func deleteMatter(_ matter: Matter) {
        modelContext?.delete(matter)
        try? modelContext?.save()

        matters.removeAll { $0.id == matter.id }
        activeMatters.removeAll { $0.id == matter.id }

        if currentMatter?.id == matter.id {
            currentMatter = nil
        }
    }

    /// Archive a matter
    func archiveMatter(_ matter: Matter) {
        matter.archive()
        updateMatter(matter)
    }

    /// Complete a matter
    func completeMatter(_ matter: Matter) {
        matter.complete()
        updateMatter(matter)
    }

    /// Reactivate a matter
    func reactivateMatter(_ matter: Matter) {
        matter.reactivate()
        updateMatter(matter)
    }

    // MARK: - Time Tracking

    /// Record time spent on a matter
    func recordTime(_ duration: TimeInterval, for matter: Matter) {
        matter.addTime(duration)
        try? modelContext?.save()
    }

    // MARK: - Auto Detection

    /// Detect matter from document context
    func detectMatter(
        documentTitle: String?,
        windowTitle: String?,
        appBundleID: String?
    ) -> Matter? {
        for matter in activeMatters {
            if matter.matches(documentTitle: documentTitle, windowTitle: windowTitle) {
                setCurrentMatter(matter)
                return matter
            }
        }
        return nil
    }

    /// Set the current active matter
    func setCurrentMatter(_ matter: Matter?) {
        currentMatter = matter
    }

    /// Add a detection pattern to a matter
    func addPattern(to matter: Matter, pattern: String, isWindowTitle: Bool = false) {
        matter.addPattern(pattern, isWindowTitle: isWindowTitle)
        try? modelContext?.save()
    }

    // MARK: - Deadline Management

    /// Set filing deadline for a matter
    func setFilingDeadline(_ date: Date, for matter: Matter) {
        matter.filingDeadline = date
        matter.updatedAt = Date()
        try? modelContext?.save()
    }

    /// Set trial date for a matter
    func setTrialDate(_ date: Date, for matter: Matter) {
        matter.trialDate = date
        matter.updatedAt = Date()
        try? modelContext?.save()
    }

    /// Add custom deadline
    func addCustomDeadline(_ name: String, date: Date, for matter: Matter) {
        if matter.customDeadlines == nil {
            matter.customDeadlines = [:]
        }
        matter.customDeadlines?[name] = date
        matter.updatedAt = Date()
        try? modelContext?.save()
    }

    /// Get all upcoming deadlines across all matters
    func getUpcomingDeadlines(within days: Int = 30) -> [(matter: Matter, deadline: Date, name: String)] {
        var deadlines: [(Matter, Date, String)] = []
        let cutoff = Date().addingTimeInterval(TimeInterval(days * 86400))

        for matter in activeMatters {
            if let filing = matter.filingDeadline, filing <= cutoff && filing > Date() {
                deadlines.append((matter, filing, "Filing Deadline"))
            }
            if let trial = matter.trialDate, trial <= cutoff && trial > Date() {
                deadlines.append((matter, trial, "Trial Date"))
            }
            if let custom = matter.customDeadlines {
                for (name, date) in custom where date <= cutoff && date > Date() {
                    deadlines.append((matter, date, name))
                }
            }
        }

        return deadlines.sorted { $0.1 < $1.1 }
    }

    // MARK: - Statistics

    /// Get time statistics across all matters
    func getTimeStatistics() -> TimeStatistics {
        var totalTime: TimeInterval = 0
        var byMatter: [UUID: TimeInterval] = [:]

        for matter in matters {
            totalTime += matter.totalTimeSpent
            byMatter[matter.id] = matter.totalTimeSpent
        }

        let topMatters = byMatter
            .sorted { $0.value > $1.value }
            .prefix(5)
            .compactMap { id, time -> (Matter, TimeInterval)? in
                guard let matter = matters.first(where: { $0.id == id }) else { return nil }
                return (matter, time)
            }

        return TimeStatistics(
            totalTime: totalTime,
            matterCount: matters.count,
            activeCount: activeMatters.count,
            topMatters: topMatters
        )
    }

    struct TimeStatistics {
        var totalTime: TimeInterval
        var matterCount: Int
        var activeCount: Int
        var topMatters: [(matter: Matter, time: TimeInterval)]

        var formattedTotalTime: String {
            let hours = Int(totalTime) / 3600
            let minutes = (Int(totalTime) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }

    // MARK: - Morning Briefing Data

    /// Get data for morning briefing
    func getMorningBriefing() -> MorningBriefing {
        let upcomingDeadlines = getUpcomingDeadlines(within: 7)
        let recentMatters = recentlyActiveMaters

        // Calculate focus recommendations
        var focusRecommendations: [Matter] = []

        // Priority: matters with imminent deadlines
        for (matter, _, _) in upcomingDeadlines.prefix(3) {
            if !focusRecommendations.contains(where: { $0.id == matter.id }) {
                focusRecommendations.append(matter)
            }
        }

        // Also add high priority matters
        for matter in activeMatters.filter({ $0.matterPriority == .high }) {
            if !focusRecommendations.contains(where: { $0.id == matter.id }) {
                focusRecommendations.append(matter)
            }
        }

        return MorningBriefing(
            upcomingDeadlines: upcomingDeadlines,
            recentMatters: Array(recentMatters),
            focusRecommendations: Array(focusRecommendations.prefix(3)),
            totalActiveMatters: activeMatters.count
        )
    }

    struct MorningBriefing {
        var upcomingDeadlines: [(matter: Matter, deadline: Date, name: String)]
        var recentMatters: [Matter]
        var focusRecommendations: [Matter]
        var totalActiveMatters: Int

        var hasUrgentDeadlines: Bool {
            guard let first = upcomingDeadlines.first else { return false }
            return first.deadline.timeIntervalSince(Date()) < 86400 * 3 // Within 3 days
        }
    }
}

// MARK: - Matter Suggestions

extension MatterTracker {
    /// Suggest matter name from document title
    func suggestMatterName(from documentTitle: String?) -> String? {
        guard let title = documentTitle else { return nil }

        // Try to extract matter name patterns
        let patterns = [
            // "Smith v. Jones" pattern
            #"([A-Z][a-z]+ v\. [A-Z][a-z]+)"#,
            // "In re Smith" pattern
            #"(In re [A-Z][a-z]+)"#,
            // "Matter: Name" pattern
            #"Matter:\s*([^\-\–]+)"#,
            // "Client - Description" pattern
            #"^([A-Z][a-z]+)\s*[-–]"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range(at: 1), in: title) {
                return String(title[range]).trimmingCharacters(in: .whitespaces)
            }
        }

        return nil
    }

    /// Suggest client name from document title
    func suggestClientName(from documentTitle: String?) -> String? {
        guard let title = documentTitle else { return nil }

        // Try common patterns
        let patterns = [
            #"([A-Z][a-z]+)\s+v\."#,  // Plaintiff in case name
            #"^([A-Z][a-z]+)\s*[-–]"#  // First word before dash
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range(at: 1), in: title) {
                return String(title[range])
            }
        }

        return nil
    }
}
