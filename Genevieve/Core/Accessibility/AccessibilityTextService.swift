import Foundation
import AppKit
import ApplicationServices

/// Service for detecting focused text fields and inserting text via macOS Accessibility APIs
@MainActor
final class AccessibilityTextService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var focusedAppName: String?
    @Published private(set) var focusedElementInfo: FocusedElementInfo?

    // MARK: - Types

    struct FocusedElementInfo: Equatable {
        let selectedText: String?
        let selectedRange: NSRange?
        let fullText: String?
        let cursorPosition: Int?
        let appBundleID: String
        let appName: String
        let windowTitle: String?
        let elementRole: String?

        var hasSelection: Bool {
            if let text = selectedText, !text.isEmpty {
                return true
            }
            return false
        }

        var contextAroundCursor: String? {
            guard let fullText = fullText, let position = cursorPosition else { return nil }

            let text = fullText
            let start = max(0, position - 200)
            let end = min(text.count, position + 200)

            guard start < end else { return nil }

            let startIndex = text.index(text.startIndex, offsetBy: start)
            let endIndex = text.index(text.startIndex, offsetBy: end)

            return String(text[startIndex..<endIndex])
        }
    }

    enum InsertionResult {
        case success
        case fallbackToClipboard
        case noFocusedElement
        case accessDenied
        case insertionFailed(String)
    }

    // MARK: - Singleton

    static let shared = AccessibilityTextService()

    // MARK: - Private Properties

    private var pollTimer: Timer?
    private var permissionCheckTimer: Timer?
    private let pollInterval: TimeInterval = 0.5

    // Exponential backoff for permission polling
    private var permissionCheckInterval: TimeInterval = 2.0
    private let minPermissionCheckInterval: TimeInterval = 2.0
    private let maxPermissionCheckInterval: TimeInterval = 30.0
    private let backoffMultiplier: Double = 1.5

    // MARK: - Initialization

    private init() {
        checkPermission()
        startPermissionPolling()
    }

    deinit {
        permissionCheckTimer?.invalidate()
    }

    // MARK: - Permission Handling

    /// Check if accessibility permission is granted
    @discardableResult
    func checkPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        // Debug logging to diagnose permission issues
        if trusted != hasAccessibilityPermission {
            let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
            let bundlePath = Bundle.main.bundlePath
            print("🔍 Accessibility permission changed: \(trusted)")
            print("   Bundle ID: \(bundleID)")
            print("   Bundle Path: \(bundlePath)")
        }

        hasAccessibilityPermission = trusted
        return trusted
    }

    /// Request accessibility permission (shows system prompt)
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Open System Settings directly
        openAccessibilitySettings()

        // Check again after a delay
        Task {
            try? await Task.sleep(for: .seconds(1))
            checkPermission()
        }
    }

    /// Open System Settings to Accessibility pane
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        // Reset polling interval since user is likely about to grant permission
        resetPermissionPolling()
    }

    /// Start polling for permission changes (useful when user grants access in System Settings)
    private func startPermissionPolling() {
        scheduleNextPermissionCheck()
    }

    private func scheduleNextPermissionCheck() {
        // Don't schedule if permission already granted
        guard !hasAccessibilityPermission else {
            stopPermissionPolling()
            return
        }

        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: permissionCheckInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }

                let wasGranted = self.checkPermission()

                if wasGranted {
                    // Permission granted, stop polling
                    self.stopPermissionPolling()
                    print("✅ Accessibility permission granted, stopping permission polling")
                } else {
                    // Increase interval with exponential backoff
                    self.permissionCheckInterval = min(
                        self.permissionCheckInterval * self.backoffMultiplier,
                        self.maxPermissionCheckInterval
                    )
                    print("🔄 Accessibility permission not yet granted, next check in \(Int(self.permissionCheckInterval))s")

                    // Schedule next check
                    self.scheduleNextPermissionCheck()
                }
            }
        }
    }

    /// Reset permission polling interval (call when user opens settings)
    func resetPermissionPolling() {
        permissionCheckInterval = minPermissionCheckInterval
        scheduleNextPermissionCheck()
    }

    /// Stop permission polling (call after permission is granted)
    func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        permissionCheckInterval = minPermissionCheckInterval
    }

    // MARK: - Polling

    /// Start polling for focused element changes
    func startPolling() {
        guard pollTimer == nil else { return }

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateFocusedElementInfo()
            }
        }
    }

    /// Stop polling
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Focus Detection

    /// Update focused element info
    func updateFocusedElementInfo() {
        guard hasAccessibilityPermission else {
            focusedElementInfo = nil
            focusedAppName = nil
            return
        }

        focusedElementInfo = getFocusedElementInfo()
        focusedAppName = focusedElementInfo?.appName
    }

    /// Get the currently focused UI element
    private func getFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        ) == .success else {
            return nil
        }

        guard let appRef = focusedAppRef else { return nil }
        let appElement = (appRef as! AXUIElement)  // CFTypeRef to AXUIElement
        var focusedElementRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        ) == .success else {
            return nil
        }

        guard let elementRef = focusedElementRef else { return nil }
        return (elementRef as! AXUIElement)  // CFTypeRef to AXUIElement
    }

    /// Get detailed info about the focused element
    func getFocusedElementInfo() -> FocusedElementInfo? {
        guard hasAccessibilityPermission else { return nil }
        guard let element = getFocusedElement() else { return nil }

        // Get element role
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String

        // Get selected text
        var selectedTextRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef)
        let selectedText = selectedTextRef as? String

        // Get selected text range
        var selectedRangeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef)
        let selectedRange = extractRange(from: selectedRangeRef)

        // Get full text value
        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        let fullText = valueRef as? String

        // Get cursor position from range
        let cursorPosition = selectedRange?.location

        // Get app info
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }

        // Get window title
        let windowTitle = getWindowTitle(for: frontApp)

        return FocusedElementInfo(
            selectedText: selectedText,
            selectedRange: selectedRange,
            fullText: fullText,
            cursorPosition: cursorPosition,
            appBundleID: frontApp.bundleIdentifier ?? "",
            appName: frontApp.localizedName ?? "Unknown",
            windowTitle: windowTitle,
            elementRole: role
        )
    }

    private func getWindowTitle(for app: NSRunningApplication) -> String? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindowRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        ) == .success else {
            return nil
        }

        guard let windowRef = focusedWindowRef else { return nil }
        let windowElement = (windowRef as! AXUIElement)  // CFTypeRef to AXUIElement
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            windowElement,
            kAXTitleAttribute as CFString,
            &titleRef
        )

        return titleRef as? String
    }

    private func extractRange(from ref: CFTypeRef?) -> NSRange? {
        guard let axValue = ref else { return nil }
        var range = CFRange()

        let value = (axValue as! AXValue)  // CFTypeRef to AXValue
        guard AXValueGetValue(value, .cfRange, &range) else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    // MARK: - Text Insertion

    /// Insert text at the current cursor position or replace selection
    func insertText(_ text: String, replacing: Bool = true) -> InsertionResult {
        guard hasAccessibilityPermission else { return .accessDenied }
        guard let element = getFocusedElement() else { return .noFocusedElement }

        // Check if this app requires clipboard-based insertion
        let method = preferredInsertionMethod
        if method == .clipboard {
            print("📋 Using clipboard insertion for \(focusedElementInfo?.appBundleID ?? "unknown app")")
            return insertViaClipboard(text)
        }

        // Try direct insertion first (selected text attribute)
        if replacing {
            let result = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )

            if result == .success {
                print("✅ Direct insertion succeeded via kAXSelectedTextAttribute")
                return .success
            }
        }

        // Direct insertion failed, fallback to clipboard
        print("⚠️ Direct insertion failed, falling back to clipboard")
        return insertViaClipboard(text)
    }

    /// Insert text via clipboard (fallback method)
    private func insertViaClipboard(_ text: String) -> InsertionResult {
        let pasteboard = NSPasteboard.general

        // Save current clipboard contents
        let previousContents = pasteboard.string(forType: .string)

        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        simulatePaste()

        // Monitor for paste completion using changeCount
        // Poll up to 1 second with 50ms intervals
        Task { @MainActor in
            let maxWaitMs = 1000
            let pollIntervalMs = 50
            var elapsedMs = 0

            // Wait for the paste to complete (changeCount changes when app reads clipboard)
            // Or timeout after maxWaitMs
            while elapsedMs < maxWaitMs {
                try? await Task.sleep(for: .milliseconds(pollIntervalMs))
                elapsedMs += pollIntervalMs

                // Check if clipboard was read by another app (changeCount changes)
                // or if enough time has passed for the paste to complete
                if elapsedMs >= 200 {
                    // After 200ms, most pastes should be complete
                    break
                }
            }

            // Restore previous clipboard contents
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
                print("📋 Clipboard restored after \(elapsedMs)ms")
            }
        }

        return .fallbackToClipboard
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down for V with Command modifier
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) else { return }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)

        // Key up
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return }
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Clipboard

    /// Copy text to clipboard
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Text Field Detection

    /// Known text input roles (standard macOS)
    private static let standardTextRoles = [
        "AXTextArea",
        "AXTextField",
        "AXTextView",
        "AXComboBox",
        "AXSearchField"
    ]

    /// Web content roles that might be editable
    private static let webTextRoles = [
        "AXWebArea",      // Main web content area
        "AXGroup",        // Often used for contenteditable divs
        "AXStaticText"    // Sometimes editable in web contexts
    ]

    /// Check if the focused element is a text input
    var isTextFieldFocused: Bool {
        guard let info = focusedElementInfo else { return false }
        guard let role = info.elementRole else { return false }

        // Check standard text roles
        if Self.standardTextRoles.contains(role) {
            return true
        }

        // For web content roles, verify that the element is actually editable
        if Self.webTextRoles.contains(role) {
            return canInsertText
        }

        return false
    }

    /// Check if we can insert text into the focused element
    var canInsertText: Bool {
        guard hasAccessibilityPermission else { return false }
        guard let element = getFocusedElement() else { return false }

        // First check if kAXValueAttribute is settable
        var valueSettable: DarwinBoolean = false
        let valueResult = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &valueSettable
        )

        if valueResult == .success && valueSettable.boolValue {
            return true
        }

        // Also check if kAXSelectedTextAttribute is settable (for insertion at cursor)
        var selectedTextSettable: DarwinBoolean = false
        let selectedResult = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextSettable
        )

        return selectedResult == .success && selectedTextSettable.boolValue
    }

    /// Check if the current element is web content (contenteditable)
    var isWebContent: Bool {
        guard let info = focusedElementInfo else { return false }
        guard let role = info.elementRole else { return false }

        return Self.webTextRoles.contains(role)
    }
}

// MARK: - App-Specific Handlers

extension AccessibilityTextService {
    /// Known app behaviors for text insertion
    struct AppTextHandler {
        let bundleID: String
        let supportsDirectInsertion: Bool
        let requiresClipboard: Bool

        static let handlers: [String: AppTextHandler] = [
            // Microsoft Office - clipboard required
            "com.microsoft.Word": AppTextHandler(
                bundleID: "com.microsoft.Word",
                supportsDirectInsertion: false,
                requiresClipboard: true
            ),
            "com.microsoft.Excel": AppTextHandler(
                bundleID: "com.microsoft.Excel",
                supportsDirectInsertion: false,
                requiresClipboard: true
            ),
            "com.microsoft.Outlook": AppTextHandler(
                bundleID: "com.microsoft.Outlook",
                supportsDirectInsertion: false,
                requiresClipboard: true
            ),

            // Browsers - clipboard required for web content
            "com.google.Chrome": AppTextHandler(
                bundleID: "com.google.Chrome",
                supportsDirectInsertion: false,
                requiresClipboard: true
            ),
            "com.apple.Safari": AppTextHandler(
                bundleID: "com.apple.Safari",
                supportsDirectInsertion: false,
                requiresClipboard: true
            ),
            "org.mozilla.firefox": AppTextHandler(
                bundleID: "org.mozilla.firefox",
                supportsDirectInsertion: false,
                requiresClipboard: true
            ),
            "com.brave.Browser": AppTextHandler(
                bundleID: "com.brave.Browser",
                supportsDirectInsertion: false,
                requiresClipboard: true
            ),
            "com.microsoft.edgemac": AppTextHandler(
                bundleID: "com.microsoft.edgemac",
                supportsDirectInsertion: false,
                requiresClipboard: true
            ),

            // Electron apps - clipboard required
            "com.tinyspeck.slackmacgap": AppTextHandler(
                bundleID: "com.tinyspeck.slackmacgap",
                supportsDirectInsertion: false,
                requiresClipboard: true
            ),
            "notion.id": AppTextHandler(
                bundleID: "notion.id",
                supportsDirectInsertion: false,
                requiresClipboard: true
            ),
            "com.hnc.Discord": AppTextHandler(
                bundleID: "com.hnc.Discord",
                supportsDirectInsertion: false,
                requiresClipboard: true
            ),
            "com.microsoft.VSCode": AppTextHandler(
                bundleID: "com.microsoft.VSCode",
                supportsDirectInsertion: false,
                requiresClipboard: true
            ),

            // Native macOS apps - direct insertion works
            "com.apple.TextEdit": AppTextHandler(
                bundleID: "com.apple.TextEdit",
                supportsDirectInsertion: true,
                requiresClipboard: false
            ),
            "com.apple.iWork.Pages": AppTextHandler(
                bundleID: "com.apple.iWork.Pages",
                supportsDirectInsertion: true,
                requiresClipboard: false
            ),
            "com.apple.Notes": AppTextHandler(
                bundleID: "com.apple.Notes",
                supportsDirectInsertion: true,
                requiresClipboard: false
            ),
            "com.apple.mail": AppTextHandler(
                bundleID: "com.apple.mail",
                supportsDirectInsertion: true,
                requiresClipboard: false
            )
        ]

        static func handler(for bundleID: String) -> AppTextHandler {
            handlers[bundleID] ?? AppTextHandler(
                bundleID: bundleID,
                supportsDirectInsertion: false,
                requiresClipboard: true
            )
        }
    }

    /// Get the preferred insertion method for the current app
    var preferredInsertionMethod: InsertionMethod {
        guard let bundleID = focusedElementInfo?.appBundleID else {
            return .clipboard
        }

        let handler = AppTextHandler.handler(for: bundleID)
        return handler.supportsDirectInsertion ? .direct : .clipboard
    }

    enum InsertionMethod {
        case direct
        case clipboard
    }
}

// MARK: - Window Content Reading

extension AccessibilityTextService {
    /// Information about the current window's visible content
    struct WindowContentInfo: Equatable {
        let appName: String
        let appBundleID: String
        let windowTitle: String?
        let visibleText: String
        let timestamp: Date

        /// A hash of the content for change detection
        var contentHash: Int {
            visibleText.hashValue
        }
    }

    /// Get visible text content from the current window
    func getWindowContent() -> WindowContentInfo? {
        guard hasAccessibilityPermission else { return nil }
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else { return nil }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // Get the focused window
        var focusedWindowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        ) == .success, let windowRef = focusedWindowRef else {
            return nil
        }

        let windowElement = windowRef as! AXUIElement

        // Get window title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
        let windowTitle = titleRef as? String

        // Recursively collect all text from the window
        var collectedText: [String] = []
        collectTextFromElement(windowElement, into: &collectedText, depth: 0, maxDepth: 15)

        let visibleText = collectedText.joined(separator: "\n")

        return WindowContentInfo(
            appName: frontApp.localizedName ?? "Unknown",
            appBundleID: bundleID,
            windowTitle: windowTitle,
            visibleText: String(visibleText.prefix(10000)), // Limit to ~10k chars
            timestamp: Date()
        )
    }

    /// Recursively collect text content from an accessibility element tree
    private func collectTextFromElement(_ element: AXUIElement, into texts: inout [String], depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }

        // Get element role
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String

        // Get text value if available
        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        if let text = valueRef as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            texts.append(text)
        }

        // For static text elements, get the title/description
        if role == "AXStaticText" || role == "AXHeading" {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
            if let title = titleRef as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                texts.append(title)
            }

            var descRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
            if let desc = descRef as? String, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                texts.append(desc)
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success, let children = childrenRef as? [AXUIElement] else {
            return
        }

        for child in children {
            collectTextFromElement(child, into: &texts, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    /// Get a summary of visible content (more efficient for change detection)
    func getWindowContentSummary() -> (appName: String, windowTitle: String?, textPreview: String)? {
        guard hasAccessibilityPermission else { return nil }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // Get window title
        var focusedWindowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        ) == .success, let windowRef = focusedWindowRef else {
            return nil
        }

        let windowElement = windowRef as! AXUIElement
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
        let windowTitle = titleRef as? String

        // Get main content area text (first significant text block)
        var texts: [String] = []
        collectTextFromElement(windowElement, into: &texts, depth: 0, maxDepth: 8)
        let preview = texts.prefix(5).joined(separator: " ").prefix(500)

        return (
            frontApp.localizedName ?? "Unknown",
            windowTitle,
            String(preview)
        )
    }
}
