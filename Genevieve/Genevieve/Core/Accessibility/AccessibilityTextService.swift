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
    private let pollInterval: TimeInterval = 0.5

    // MARK: - Initialization

    private init() {
        checkPermission()
    }

    // MARK: - Permission Handling

    /// Check if accessibility permission is granted
    @discardableResult
    func checkPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        hasAccessibilityPermission = trusted
        return trusted
    }

    /// Request accessibility permission (shows system prompt)
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

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
        var focusedApp: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        ) == .success else {
            return nil
        }

        let appElement = focusedApp as! AXUIElement
        var focusedElement: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success else {
            return nil
        }

        return focusedElement as! AXUIElement
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

    private func extractRange(from ref: CFTypeRef?) -> NSRange? {
        guard let axValue = ref else { return nil }
        var range = CFRange()

        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    // MARK: - Text Insertion

    /// Insert text at the current cursor position or replace selection
    func insertText(_ text: String, replacing: Bool = true) -> InsertionResult {
        guard hasAccessibilityPermission else { return .accessDenied }
        guard let element = getFocusedElement() else { return .noFocusedElement }

        // Try direct insertion first
        if replacing {
            // Set the selected text attribute (replaces selection or inserts at cursor)
            let result = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )

            if result == .success {
                return .success
            }
        }

        // Try setting the value directly (less precise but works for more apps)
        if let info = getFocusedElementInfo(),
           let fullText = info.fullText,
           let position = info.cursorPosition {

            var newText = fullText
            let insertIndex = fullText.index(fullText.startIndex, offsetBy: min(position, fullText.count))

            if replacing, let range = info.selectedRange, range.length > 0 {
                // Replace selection
                let startIndex = fullText.index(fullText.startIndex, offsetBy: range.location)
                let endIndex = fullText.index(startIndex, offsetBy: range.length)
                newText.replaceSubrange(startIndex..<endIndex, with: text)
            } else {
                // Insert at cursor
                newText.insert(contentsOf: text, at: insertIndex)
            }

            let result = AXUIElementSetAttributeValue(
                element,
                kAXValueAttribute as CFString,
                newText as CFTypeRef
            )

            if result == .success {
                return .success
            }
        }

        // Fallback to clipboard
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

        // Restore clipboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
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

    /// Check if the focused element is a text input
    var isTextFieldFocused: Bool {
        guard let info = focusedElementInfo else { return false }

        let textRoles = [
            "AXTextArea",
            "AXTextField",
            "AXTextView",
            "AXComboBox",
            "AXSearchField"
        ]

        return textRoles.contains(info.elementRole ?? "")
    }

    /// Check if we can insert text into the focused element
    var canInsertText: Bool {
        guard hasAccessibilityPermission else { return false }
        guard let element = getFocusedElement() else { return false }

        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        )

        return result == .success && settable.boolValue
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
            "com.microsoft.Word": AppTextHandler(
                bundleID: "com.microsoft.Word",
                supportsDirectInsertion: false,
                requiresClipboard: true
            ),
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
            "com.apple.TextEdit": AppTextHandler(
                bundleID: "com.apple.TextEdit",
                supportsDirectInsertion: true,
                requiresClipboard: false
            ),
            "com.apple.iWork.Pages": AppTextHandler(
                bundleID: "com.apple.iWork.Pages",
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
