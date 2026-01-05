import Foundation
import AppKit
import Combine

/// Observes screen state including active application, window changes, and user activity patterns
@MainActor
final class ScreenObserver: ObservableObject {
    // MARK: - Published State

    @Published private(set) var activeApp: AppInfo?
    @Published private(set) var recentApps: [AppInfo] = []
    @Published private(set) var windowTitle: String?
    @Published private(set) var isUserActive = true
    @Published private(set) var appSwitchCount = 0

    // MARK: - Types

    struct AppInfo: Equatable, Identifiable {
        let bundleID: String
        let name: String
        let activatedAt: Date

        var id: String { bundleID }

        var isDistraction: Bool {
            DistractionDetector.isDistraction(bundleID: bundleID, windowTitle: nil)
        }
    }

    struct WindowChange {
        let fromApp: AppInfo?
        let toApp: AppInfo
        let timestamp: Date
    }

    // MARK: - Callbacks

    var onAppSwitch: ((WindowChange) -> Void)?
    var onDistractionDetected: ((AppInfo, TimeInterval) -> Void)?
    var onReturnToWork: ((AppInfo) -> Void)?

    // MARK: - Private Properties

    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var distractionStartTime: Date?
    private var lastWorkApp: AppInfo?
    private var appSwitchHistory: [(from: String?, to: String, timestamp: Date)] = []

    // MARK: - Configuration

    private let maxRecentApps = 10
    private let distractionThreshold: TimeInterval = 120 // 2 minutes

    // MARK: - Initialization

    init() {
        setupWorkspaceObservers()
    }

    deinit {
        // Clean up timer and observers directly to avoid MainActor call from deinit
        pollTimer?.invalidate()
        pollTimer = nil
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    // MARK: - Observation

    /// Start observing screen changes
    func startObserving() {
        updateActiveApp()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateActiveApp()
                self?.checkDistractionState()
            }
        }
    }

    /// Stop observing
    func stopObserving() {
        pollTimer?.invalidate()
        pollTimer = nil

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    private func setupWorkspaceObservers() {
        // App activation
        let activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAppActivation(notification)
            }
        }
        workspaceObservers.append(activationObserver)

        // App deactivation
        let deactivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAppDeactivation(notification)
            }
        }
        workspaceObservers.append(deactivationObserver)
    }

    private func handleAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              let name = app.localizedName else {
            return
        }

        let previousApp = activeApp
        let newApp = AppInfo(bundleID: bundleID, name: name, activatedAt: Date())

        // Track app switch
        if previousApp?.bundleID != newApp.bundleID {
            appSwitchCount += 1

            appSwitchHistory.append((
                from: previousApp?.bundleID,
                to: newApp.bundleID,
                timestamp: Date()
            ))

            // Keep only recent history
            if appSwitchHistory.count > 50 {
                appSwitchHistory.removeFirst()
            }

            // Callback
            onAppSwitch?(WindowChange(
                fromApp: previousApp,
                toApp: newApp,
                timestamp: Date()
            ))

            // Track distraction
            if newApp.isDistraction {
                if distractionStartTime == nil {
                    distractionStartTime = Date()
                    lastWorkApp = previousApp
                }
            } else {
                if distractionStartTime != nil {
                    // Returning from distraction
                    onReturnToWork?(newApp)
                    distractionStartTime = nil
                }
            }
        }

        activeApp = newApp
        updateRecentApps(newApp)
    }

    private func handleAppDeactivation(_ notification: Notification) {
        // Could track time spent in app here
    }

    private func updateActiveApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              let name = app.localizedName else {
            return
        }

        // Update window title
        windowTitle = getActiveWindowTitle()

        // Only update if different
        if activeApp?.bundleID != bundleID {
            let newApp = AppInfo(bundleID: bundleID, name: name, activatedAt: Date())
            activeApp = newApp
            updateRecentApps(newApp)
        }
    }

    private func updateRecentApps(_ app: AppInfo) {
        // Remove if already present
        recentApps.removeAll { $0.bundleID == app.bundleID }

        // Add to front
        recentApps.insert(app, at: 0)

        // Trim
        if recentApps.count > maxRecentApps {
            recentApps = Array(recentApps.prefix(maxRecentApps))
        }
    }

    private func getActiveWindowTitle() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success else {
            return nil
        }

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            focusedWindow as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleRef
        )

        return titleRef as? String
    }

    private func checkDistractionState() {
        guard let startTime = distractionStartTime else { return }

        let duration = Date().timeIntervalSince(startTime)

        if duration >= distractionThreshold, let app = activeApp {
            onDistractionDetected?(app, duration)
        }
    }

    // MARK: - Analysis

    /// Get rapid app switching count in the last N seconds
    func rapidSwitchCount(inLast seconds: TimeInterval) -> Int {
        let cutoff = Date().addingTimeInterval(-seconds)
        return appSwitchHistory.filter { $0.timestamp > cutoff }.count
    }

    /// Check if user is rapidly switching between apps (sign of being stuck)
    var isRapidSwitching: Bool {
        rapidSwitchCount(inLast: 30) >= 3
    }

    /// Check if currently in a distraction app
    var isInDistraction: Bool {
        activeApp?.isDistraction ?? false
    }

    /// Get time spent in current distraction
    var distractionDuration: TimeInterval? {
        guard let startTime = distractionStartTime else { return nil }
        return Date().timeIntervalSince(startTime)
    }

    /// Reset app switch counter
    func resetAppSwitchCount() {
        appSwitchCount = 0
    }
}

// MARK: - Distraction Detection

struct DistractionDetector {
    /// Known distraction patterns (domains/apps)
    static let distractionPatterns: [String] = [
        // Social media
        "twitter.com", "x.com", "facebook.com", "instagram.com",
        "tiktok.com", "reddit.com", "linkedin.com/feed",

        // Entertainment
        "youtube.com", "netflix.com", "twitch.tv", "hulu.com",

        // News (can be distracting)
        "news.ycombinator.com", "cnn.com", "bbc.com", "nytimes.com"
    ]

    /// Known distraction app bundle IDs
    static let distractionApps: Set<String> = [
        "com.twitter.twitter-mac",
        "com.facebook.Facebook",
        "com.tinyspeck.slackmacgap", // Slack can be a distraction
    ]

    /// Work-related apps (never distractions)
    static let workApps: Set<String> = [
        "com.microsoft.Word",
        "com.microsoft.Excel",
        "com.microsoft.Outlook",
        "com.apple.iWork.Pages",
        "com.apple.iWork.Numbers",
        "com.apple.mail",
        "com.apple.TextEdit",
        "com.apple.Preview",
        "com.apple.finder"
    ]

    /// Check if an app/window is a distraction
    static func isDistraction(bundleID: String, windowTitle: String?) -> Bool {
        // Work apps are never distractions
        if workApps.contains(bundleID) {
            return false
        }

        // Check known distraction apps
        if distractionApps.contains(bundleID) {
            return true
        }

        // Check window title for browser tabs
        if let title = windowTitle?.lowercased() {
            for pattern in distractionPatterns {
                if title.contains(pattern) {
                    return true
                }
            }
        }

        return false
    }

    /// Categorize distraction type
    static func categorize(bundleID: String, windowTitle: String?) -> DistractionType {
        let title = windowTitle?.lowercased() ?? ""

        if title.contains("twitter") || title.contains("x.com") ||
           title.contains("facebook") || title.contains("instagram") ||
           title.contains("linkedin") || title.contains("reddit") {
            return .socialMedia
        }

        if title.contains("youtube") || title.contains("netflix") ||
           title.contains("twitch") || title.contains("hulu") {
            return .entertainment
        }

        if title.contains("news") || title.contains("cnn") ||
           title.contains("bbc") || title.contains("nytimes") {
            return .news
        }

        if bundleID.contains("slack") || bundleID.contains("teams") ||
           bundleID.contains("discord") {
            return .communication
        }

        return .unknown
    }

    enum DistractionType {
        case socialMedia
        case entertainment
        case news
        case communication
        case unknown
    }
}
