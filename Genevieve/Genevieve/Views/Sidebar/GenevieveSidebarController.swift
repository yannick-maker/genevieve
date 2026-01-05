import AppKit
import SwiftUI
import Combine

/// Controller for the floating suggestion sidebar panel
@MainActor
final class GenevieveSidebarController: NSObject, ObservableObject {
    // MARK: - Published State

    @Published private(set) var isVisible = false
    @Published private(set) var isPinned = false
    @Published var position: SidebarPosition = .right

    // MARK: - Panel

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    // MARK: - Configuration

    private let defaultWidth: CGFloat = 300
    private let minWidth: CGFloat = 250
    private let maxWidth: CGFloat = 400
    private let edgeMargin: CGFloat = 12

    // MARK: - Types

    enum SidebarPosition: String, CaseIterable {
        case left
        case right

        var displayName: String {
            rawValue.capitalized
        }
    }

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - Panel Setup

    /// Setup the sidebar panel with the given content view
    func setup<Content: View>(with content: Content) {
        guard panel == nil else { return }

        // Get screen dimensions
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // Calculate panel frame
        let panelHeight = screenFrame.height - (edgeMargin * 2)
        let panelX: CGFloat
        switch position {
        case .right:
            panelX = screenFrame.maxX - defaultWidth - edgeMargin
        case .left:
            panelX = screenFrame.minX + edgeMargin
        }
        let panelY = screenFrame.minY + edgeMargin

        let panelFrame = NSRect(
            x: panelX,
            y: panelY,
            width: defaultWidth,
            height: panelHeight
        )

        // Create panel with non-activating behavior
        let newPanel = NSPanel(
            contentRect: panelFrame,
            styleMask: [
                .nonactivatingPanel,
                .titled,
                .closable,
                .resizable,
                .utilityWindow
            ],
            backing: .buffered,
            defer: false
        )

        // Configure panel behavior
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isMovableByWindowBackground = true
        newPanel.hidesOnDeactivate = false
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true

        // Set minimum/maximum size
        newPanel.minSize = NSSize(width: minWidth, height: 400)
        newPanel.maxSize = NSSize(width: maxWidth, height: screenFrame.height)

        // Create hosting view for SwiftUI content
        let wrappedContent = AnyView(content)
        let hosting = NSHostingView(rootView: wrappedContent)
        hosting.frame = newPanel.contentRect(forFrameRect: panelFrame)

        newPanel.contentView = hosting

        // Store references
        panel = newPanel
        hostingView = hosting

        // Setup delegate for tracking
        newPanel.delegate = self
    }

    /// Update the content view
    func updateContent<Content: View>(with content: Content) {
        hostingView?.rootView = AnyView(content)
    }

    // MARK: - Visibility

    /// Show the sidebar
    func show() {
        guard let panel = panel else { return }

        if !panel.isVisible {
            panel.orderFront(nil)
            withAnimation(.easeInOut(duration: 0.2)) {
                isVisible = true
            }
        }
    }

    /// Hide the sidebar
    func hide() {
        guard let panel = panel, !isPinned else { return }

        panel.orderOut(nil)
        withAnimation(.easeInOut(duration: 0.2)) {
            isVisible = false
        }
    }

    /// Toggle sidebar visibility
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Pin the sidebar (prevents auto-hide)
    func togglePin() {
        isPinned.toggle()
    }

    // MARK: - Position

    /// Move sidebar to the specified position
    func moveTo(_ newPosition: SidebarPosition) {
        guard newPosition != position, let panel = panel, let screen = NSScreen.main else {
            return
        }

        position = newPosition
        let screenFrame = screen.visibleFrame
        var panelFrame = panel.frame

        switch newPosition {
        case .right:
            panelFrame.origin.x = screenFrame.maxX - panelFrame.width - edgeMargin
        case .left:
            panelFrame.origin.x = screenFrame.minX + edgeMargin
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(panelFrame, display: true)
        }
    }

    /// Adjust panel position after screen changes
    func adjustToScreen() {
        guard let panel = panel, let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        var panelFrame = panel.frame

        // Ensure panel is within screen bounds
        let maxX = screenFrame.maxX - panelFrame.width - edgeMargin
        let minX = screenFrame.minX + edgeMargin

        switch position {
        case .right:
            panelFrame.origin.x = maxX
        case .left:
            panelFrame.origin.x = minX
        }

        // Adjust height if needed
        if panelFrame.height > screenFrame.height - (edgeMargin * 2) {
            panelFrame.size.height = screenFrame.height - (edgeMargin * 2)
            panelFrame.origin.y = screenFrame.minY + edgeMargin
        }

        panel.setFrame(panelFrame, display: true, animate: false)
    }

    // MARK: - Focus

    /// Bring panel to front without activating
    func bringToFront() {
        panel?.orderFront(nil)
    }

    /// Check if panel contains the mouse
    var containsMouse: Bool {
        guard let panel = panel else { return false }
        let mouseLocation = NSEvent.mouseLocation
        return panel.frame.contains(mouseLocation)
    }
}

// MARK: - NSWindowDelegate

extension GenevieveSidebarController: NSWindowDelegate {
    nonisolated func windowDidMove(_ notification: Notification) {
        // Track position changes
    }

    nonisolated func windowDidResize(_ notification: Notification) {
        // Track size changes
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.isVisible = false
        }
    }

    nonisolated func windowDidChangeScreen(_ notification: Notification) {
        Task { @MainActor in
            self.adjustToScreen()
        }
    }
}

// MARK: - Keyboard Shortcuts

extension GenevieveSidebarController {
    /// Register global keyboard shortcuts
    func registerGlobalShortcuts() {
        // Cmd+Shift+G to toggle sidebar
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }

            if event.modifierFlags.contains([.command, .shift]) &&
               event.charactersIgnoringModifiers == "g" {
                Task { @MainActor in
                    self.toggle()
                }
            }
        }

        // Also monitor local events for when app is focused
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            if event.modifierFlags.contains([.command, .shift]) &&
               event.charactersIgnoringModifiers == "g" {
                Task { @MainActor in
                    self.toggle()
                }
                return nil // Consume the event
            }
            return event
        }
    }
}

// MARK: - Animation Helpers

extension GenevieveSidebarController {
    /// Pulse animation to draw attention
    func pulseAttention() {
        guard let panel = panel else { return }

        let originalFrame = panel.frame
        let expandedFrame = originalFrame.insetBy(dx: -4, dy: -4)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(expandedFrame, display: true)
        } completionHandler: { [weak panel] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel?.animator().setFrame(originalFrame, display: true)
            }
        }
    }

    /// Subtle bounce animation for new suggestions
    func bounceForNewSuggestion() {
        guard let panel = panel else { return }

        let originalFrame = panel.frame
        let bounceFrame = NSRect(
            x: originalFrame.origin.x,
            y: originalFrame.origin.y + 8,
            width: originalFrame.width,
            height: originalFrame.height
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().setFrame(bounceFrame, display: true)
        } completionHandler: { [weak panel] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel?.animator().setFrame(originalFrame, display: true)
            }
        }
    }
}
