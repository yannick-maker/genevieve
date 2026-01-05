import Foundation
import AppKit
import Combine

/// Higher-level detector for understanding writing context from focused elements
@MainActor
final class FocusedElementDetector: ObservableObject {
    // MARK: - Published State

    @Published private(set) var isWriting = false
    @Published private(set) var currentContext: WritingContext?
    @Published private(set) var lastActivityTime: Date?

    // MARK: - Types

    struct WritingContext: Equatable {
        let appName: String
        let appBundleID: String
        let windowTitle: String?
        let selectedText: String?
        let surroundingText: String?
        let cursorPosition: Int?
        let documentType: DocumentType?
        let timestamp: Date

        /// Check if context has changed significantly (requires re-analysis)
        func needsReanalysis(comparedTo other: WritingContext?) -> Bool {
            guard let other = other else { return true }

            // Different app
            if appBundleID != other.appBundleID { return true }

            // Different window
            if windowTitle != other.windowTitle { return true }

            // Selection changed significantly
            if selectedText != other.selectedText { return true }

            // Cursor moved significantly (more than 50 characters)
            if let pos = cursorPosition, let otherPos = other.cursorPosition {
                if abs(pos - otherPos) > 50 { return true }
            }

            return false
        }
    }

    enum DocumentType: String, Codable {
        case brief
        case motion
        case contract
        case memo
        case email
        case letter
        case pleading
        case discovery
        case research
        case notes
        case code
        case unknown

        var displayName: String {
            switch self {
            case .brief: return "Brief"
            case .motion: return "Motion"
            case .contract: return "Contract"
            case .memo: return "Memo"
            case .email: return "Email"
            case .letter: return "Letter"
            case .pleading: return "Pleading"
            case .discovery: return "Discovery"
            case .research: return "Research"
            case .notes: return "Notes"
            case .code: return "Code"
            case .unknown: return "Document"
            }
        }

        /// Infer document type from window title
        static func infer(from windowTitle: String?) -> DocumentType {
            guard let title = windowTitle?.lowercased() else { return .unknown }

            // Check for common patterns
            if title.contains("brief") { return .brief }
            if title.contains("motion") { return .motion }
            if title.contains("contract") || title.contains("agreement") { return .contract }
            if title.contains("memo") || title.contains("memorandum") { return .memo }
            if title.contains("mail") || title.contains("gmail") || title.contains("outlook") { return .email }
            if title.contains("letter") { return .letter }
            if title.contains("complaint") || title.contains("answer") || title.contains("petition") { return .pleading }
            if title.contains("discovery") || title.contains("interrogator") || title.contains("deposition") { return .discovery }
            if title.contains("research") { return .research }
            if title.contains("notes") || title.contains("note") { return .notes }

            // Check for code editors
            if title.contains(".swift") || title.contains(".py") || title.contains(".js") ||
               title.contains(".ts") || title.contains("xcode") || title.contains("vscode") {
                return .code
            }

            return .unknown
        }
    }

    // MARK: - Dependencies

    private let textService: AccessibilityTextService
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?

    // MARK: - Configuration

    private let updateInterval: TimeInterval = 0.5
    private let inactivityThreshold: TimeInterval = 30 // seconds before considered inactive

    // MARK: - Initialization

    init(textService: AccessibilityTextService = .shared) {
        self.textService = textService
        setupBindings()
    }

    private func setupBindings() {
        // React to text service updates
        textService.$focusedElementInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                self?.updateContext(from: info)
            }
            .store(in: &cancellables)
    }

    // MARK: - Detection

    /// Start detecting writing context
    func startDetecting() {
        textService.startPolling()

        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkWritingState()
            }
        }
    }

    /// Stop detecting
    func stopDetecting() {
        textService.stopPolling()
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateContext(from info: AccessibilityTextService.FocusedElementInfo?) {
        guard let info = info else {
            currentContext = nil
            isWriting = false
            return
        }

        let context = WritingContext(
            appName: info.appName,
            appBundleID: info.appBundleID,
            windowTitle: info.windowTitle,
            selectedText: info.selectedText,
            surroundingText: info.contextAroundCursor,
            cursorPosition: info.cursorPosition,
            documentType: DocumentType.infer(from: info.windowTitle),
            timestamp: Date()
        )

        currentContext = context
        lastActivityTime = Date()
    }

    private func checkWritingState() {
        // Check if we're in a text field
        let inTextField = textService.isTextFieldFocused

        // Check if there's been recent activity
        let recentActivity: Bool
        if let lastActivity = lastActivityTime {
            recentActivity = Date().timeIntervalSince(lastActivity) < inactivityThreshold
        } else {
            recentActivity = false
        }

        isWriting = inTextField && recentActivity
    }

    // MARK: - Context Helpers

    /// Get the text that should be analyzed for suggestions
    var textForAnalysis: String? {
        guard let context = currentContext else { return nil }

        // Prefer selected text if available
        if let selected = context.selectedText, !selected.isEmpty {
            return selected
        }

        // Fall back to surrounding text
        return context.surroundingText
    }

    /// Check if we have enough context for analysis
    var hasEnoughContext: Bool {
        guard let text = textForAnalysis else { return false }
        return text.count >= 10 // Minimum 10 characters
    }

    /// Get the focused application info
    var focusedApp: (name: String, bundleID: String)? {
        guard let context = currentContext else { return nil }
        return (context.appName, context.appBundleID)
    }

    /// Check if the current app is a known legal document app
    var isInLegalApp: Bool {
        guard let bundleID = currentContext?.appBundleID else { return false }

        let legalApps = [
            "com.microsoft.Word",
            "com.apple.iWork.Pages",
            "com.apple.TextEdit",
            "com.google.Chrome",  // For Google Docs
            "com.apple.Safari",   // For web-based editors
            "com.microsoft.Outlook",
            "com.apple.mail"
        ]

        return legalApps.contains(bundleID)
    }
}

// MARK: - Known Applications

extension FocusedElementDetector {
    /// Known application categories
    enum AppCategory {
        case wordProcessor
        case email
        case browser
        case codeEditor
        case notes
        case other

        static func categorize(bundleID: String) -> AppCategory {
            switch bundleID {
            case "com.microsoft.Word", "com.apple.iWork.Pages", "com.apple.TextEdit":
                return .wordProcessor
            case "com.microsoft.Outlook", "com.apple.mail":
                return .email
            case "com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox":
                return .browser
            case "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.sublimetext.4":
                return .codeEditor
            case "com.apple.Notes", "md.obsidian", "com.evernote.Evernote":
                return .notes
            default:
                return .other
            }
        }
    }

    var appCategory: AppCategory {
        guard let bundleID = currentContext?.appBundleID else { return .other }
        return AppCategory.categorize(bundleID: bundleID)
    }
}
