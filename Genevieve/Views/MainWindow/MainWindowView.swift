import SwiftUI
import SwiftData
import Darwin

struct MainWindowView: View {
    @EnvironmentObject var aiService: AIProviderService
    @EnvironmentObject var coordinator: DraftingCoordinator
    @Environment(\.modelContext) private var modelContext
    @StateObject private var argumentLibrary = ArgumentLibrary()
    @State private var selectedTab: MainTab = .dashboard
    @State private var showingSidebar = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var hasAutoStarted = false

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedTab) {
                Section("Overview") {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                        .tag(MainTab.dashboard)
                }

                Section("Tools") {
                    Label("Drafting Assistant", systemImage: "wand.and.stars")
                        .tag(MainTab.drafting)
                    Label("Argument Library", systemImage: "books.vertical")
                        .tag(MainTab.arguments)
                    Label("Matters", systemImage: "folder")
                        .tag(MainTab.matters)
                }

                Section("AI") {
                    Label("Model Settings", systemImage: "cpu")
                        .tag(MainTab.models)
                }

                Section("History") {
                    Label("Sessions", systemImage: "clock")
                        .tag(MainTab.sessions)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            // Main Content
            switch selectedTab {
            case .dashboard:
                DashboardView()
            case .drafting:
                DraftingView()
            case .arguments:
                ArgumentLibraryView(library: argumentLibrary)
            case .matters:
                MattersView()
            case .models:
                ModelSettingsView()
            case .sessions:
                SessionsView()
            }
        }
        .navigationTitle(selectedTab.title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    // Status indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(aiService.hasAnyProvider ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(aiService.hasAnyProvider ? aiService.defaultModel.displayName : "No API Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    SettingsLink {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .task {
            // Auto-start coordinator if ready
            guard !hasAutoStarted else { return }
            guard hasCompletedOnboarding else { return }
            guard aiService.hasAnyProvider else { return }

            hasAutoStarted = true
            await coordinator.start()
        }
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
}

// MARK: - Tab Enum

enum MainTab: String, CaseIterable {
    case dashboard
    case drafting
    case arguments
    case matters
    case models
    case sessions

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .drafting: return "Drafting Assistant"
        case .arguments: return "Argument Library"
        case .matters: return "Matters"
        case .models: return "Model Settings"
        case .sessions: return "Sessions"
        }
    }
}

// MARK: - Dashboard Views

struct DashboardView: View {
    @EnvironmentObject var aiService: AIProviderService
    @Environment(\.openWindow) private var openWindow

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 400), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Welcome Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Good Morning")
                        .font(DesignSystem.Fonts.display)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    
                    Text("Ready to draft your next masterpiece?")
                        .font(DesignSystem.Fonts.title)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .padding(.top, 20)
                .padding(.horizontal, DesignSystem.Metrics.padding)

                // Status Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("System Status")
                        .genevieveSubtitle()
                        .padding(.horizontal, DesignSystem.Metrics.padding)

                    LazyVGrid(columns: columns, spacing: 20) {
                        StatusCard(
                            title: "AI Engine",
                            value: aiService.hasAnyProvider ? "Online" : "Offline",
                            subtitle: aiService.hasAnyProvider ? "Ready to process" : "Configuration required",
                            icon: "brain.head.profile",
                            color: aiService.hasAnyProvider ? DesignSystem.Colors.success : DesignSystem.Colors.warning
                        )

                        StatusCard(
                            title: "Active Model",
                            value: aiService.defaultModel.displayName,
                            subtitle: "Current provider",
                            icon: "cpu",
                            color: DesignSystem.Colors.info
                        )

                        StatusCard(
                            title: "Providers",
                            value: "\(aiService.configuredProviders.count)",
                            subtitle: "Configured services",
                            icon: "server.rack",
                            color: .purple
                        )
                    }
                    .padding(.horizontal, DesignSystem.Metrics.padding)
                }

                // Quick Actions Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quick Actions")
                        .genevieveSubtitle()
                        .padding(.horizontal, DesignSystem.Metrics.padding)

                    LazyVGrid(columns: columns, spacing: 20) {
                        QuickActionButton(
                            title: "Start Drafting",
                            description: "Open the assistant",
                            icon: "wand.and.stars",
                            gradient: LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        ) {
                            // TODO: Navigate to drafting
                        }

                        QuickActionButton(
                            title: "Argument Library",
                            description: "Browse saved arguments",
                            icon: "books.vertical",
                            gradient: LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                        ) {
                            // TODO: Navigate to arguments
                        }

                        QuickActionButton(
                            title: "Settings",
                            description: "Configure AI models",
                            icon: "gear",
                            gradient: LinearGradient(colors: [.gray, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                        ) {
                            // TODO: Open settings
                        }
                    }
                    .padding(.horizontal, DesignSystem.Metrics.padding)
                }
                
                Spacer()
            }
            .padding(.bottom, 40)
        }
        .background(DesignSystem.Colors.background)
    }
}

struct StatusCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                
                Text(value)
                    .font(DesignSystem.Fonts.title)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text(subtitle)
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            
            Spacer()
        }
        .genevieveCardStyle()
    }
}

struct QuickActionButton: View {
    let title: String
    let description: String
    let icon: String
    let gradient: LinearGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(gradient)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignSystem.Fonts.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    
                    Text(description)
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .contentShape(Rectangle()) // Make entire area clickable
        }
        .buttonStyle(.plain)
        .genevieveCardStyle(interactable: true)
    }
}

struct DraftingView: View {
    @EnvironmentObject var coordinator: DraftingCoordinator

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 64))
                .foregroundStyle(DesignSystem.Colors.primaryGradient)
                .symbolEffect(.pulse, isActive: coordinator.isActive)

            VStack(spacing: 12) {
                Text("Drafting Assistant")
                    .font(DesignSystem.Fonts.display)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                if coordinator.isActive {
                    Text("Genevieve is watching your writing.\nPress Cmd+Shift+G to toggle the suggestion sidebar.")
                        .font(DesignSystem.Fonts.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                } else {
                    Text("Start writing in any text editor and Genevieve will follow along,\nor create a dedicated session here.")
                        .font(DesignSystem.Fonts.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
            }

            if coordinator.isActive {
                HStack(spacing: 16) {
                    Button(action: {
                        coordinator.toggleSidebar()
                    }) {
                        Label("Toggle Sidebar", systemImage: "sidebar.right")
                            .font(DesignSystem.Fonts.headline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(action: {
                        coordinator.stop()
                    }) {
                        Label("End Session", systemImage: "stop.fill")
                            .font(DesignSystem.Fonts.headline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.red)
                }

                // Status panel
                StatusPanelView(coordinator: coordinator)
                    .padding(.top, 16)

            } else {
                Button(action: {
                    Task {
                        await coordinator.start()
                    }
                }) {
                    Label("Start New Session", systemImage: "plus")
                        .font(DesignSystem.Fonts.headline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(DesignSystem.Colors.accent)
            }

            if !coordinator.textService.hasAccessibilityPermission {
                PermissionStatusView(textService: coordinator.textService)
                    .padding(.top, 16)
            }

            // Session info
            if coordinator.isActive, let session = coordinator.currentSession {
                VStack(spacing: 8) {
                    Divider()
                        .padding(.vertical)

                    HStack(spacing: 24) {
                        SessionStatView(title: "Duration", value: session.formattedDuration)
                        SessionStatView(title: "Suggestions", value: "\(session.suggestionsShown)")
                        SessionStatView(title: "Accepted", value: "\(session.suggestionsAccepted)")
                    }
                }
                .padding(.top, 20)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - Permission Status View

struct PermissionStatusView: View {
    let textService: AccessibilityTextService
    private var appBundleURL: URL? {
        if let url = appBundleURL(from: Bundle.main.bundleURL) {
            return url
        }

        if let executableURL = Bundle.main.executableURL,
           let url = appBundleURL(from: executableURL) {
            return url
        }

        if let runningURL = NSRunningApplication.current.bundleURL,
           let url = appBundleURL(from: runningURL) {
            return url
        }

        if let executablePath = resolvedExecutablePath {
            let url = URL(fileURLWithPath: executablePath)
            if let appURL = appBundleURL(from: url) {
                return appURL
            }
        }

        if let argumentPath = ProcessInfo.processInfo.arguments.first {
            let url = URL(fileURLWithPath: argumentPath)
            if let appURL = appBundleURL(from: url) {
                return appURL
            }
        }

        return nil
    }

    private var bundlePathText: String {
        if let appURL = appBundleURL {
            return appURL.path
        }

        let bundlePath = Bundle.main.bundlePath
        if bundlePath != "/" {
            return bundlePath
        }

        return Bundle.main.executableURL?.path
            ?? resolvedExecutablePath
            ?? ProcessInfo.processInfo.arguments.first
            ?? "/"
    }

    private var bundlePathNote: String? {
        guard appBundleURL == nil else { return nil }
        return "Bundle path not resolved. If running from Xcode, use Product > Show Build Folder and add Genevieve.app from Build/Products/Debug."
    }

    private var productsFolderURL: URL? {
        let candidates = [
            appBundleURL,
            Bundle.main.executableURL,
            Bundle.main.bundleURL,
            NSRunningApplication.current.bundleURL
        ].compactMap { $0 }

        for candidate in candidates {
            if let url = productsFolderURL(from: candidate) {
                return url
            }
        }

        return nil
    }

    private var productsFolderPathText: String? {
        productsFolderURL?.path
    }

    var body: some View {
        VStack(spacing: 12) {
            let isGranted = textService.hasAccessibilityPermission

            HStack(spacing: 12) {
                Image(systemName: isGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isGranted ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isGranted ? "Accessibility Permission Granted" : "Accessibility Permission Required")
                        .font(DesignSystem.Fonts.headline)
                    Text(isGranted
                         ? "Genevieve can detect text fields and insert suggestions."
                         : "Genevieve needs accessibility access to detect text fields and insert suggestions.")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("In System Settings > Privacy & Security > Accessibility, click + and select:")
                            .font(DesignSystem.Fonts.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)

                        Text(bundlePathText)
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let note = bundlePathNote {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }

                        HStack(spacing: 8) {
                            Button("Copy") {
                                copyBundlePath()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Button("Show in Finder") {
                                revealAppInFinder()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(appBundleURL == nil && Bundle.main.executableURL == nil)

                            Button("Open Build Folder") {
                                revealBuildProducts()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(productsFolderURL == nil)
                        }
                    }
                    .padding(.top, 6)
                }

                Spacer()

                Button("Open Settings") {
                    if isGranted {
                        textService.openAccessibilitySettings()
                    } else {
                        textService.requestPermission()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Refresh") {
                    _ = textService.checkPermission()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            .background(isGranted ? Color.green.opacity(0.08) : Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: 500)
    }

    private func copyBundlePath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(bundlePathText, forType: .string)
    }

    private func revealAppInFinder() {
        if let appURL = appBundleURL {
            NSWorkspace.shared.activateFileViewerSelecting([appURL])
            return
        }

        if let executableURL = Bundle.main.executableURL {
            NSWorkspace.shared.activateFileViewerSelecting([executableURL])
        }
    }

    private func appBundleURL(from url: URL) -> URL? {
        var current = url

        if current.pathExtension == "app" {
            return current
        }

        while current.pathExtension != "app" && current.pathComponents.count > 1 {
            current.deleteLastPathComponent()
        }

        return current.pathExtension == "app" ? current : nil
    }

    private var resolvedExecutablePath: String? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: Int(size))
        let result = _NSGetExecutablePath(&buffer, &size)
        guard result == 0 else { return nil }

        return String(cString: buffer)
    }

    private func productsFolderURL(from url: URL) -> URL? {
        let components = url.pathComponents
        guard let productsIndex = components.lastIndex(of: "Products") else { return nil }
        guard productsIndex + 1 < components.count else { return nil }

        let configIndex = productsIndex + 1
        let path = NSString.path(withComponents: Array(components.prefix(configIndex + 1)))
        return URL(fileURLWithPath: path)
    }

    private func revealBuildProducts() {
        if let productsURL = productsFolderURL {
            NSWorkspace.shared.open(productsURL)
        } else if let path = productsFolderPathText {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}

// MARK: - Status Panel View

struct StatusPanelView: View {
    @ObservedObject var coordinator: DraftingCoordinator

    var body: some View {
        VStack(spacing: 12) {
            // State indicator
            HStack(spacing: 16) {
                StatusIndicator(
                    title: "State",
                    value: stateText,
                    color: stateColor
                )

                StatusIndicator(
                    title: "Accessibility",
                    value: coordinator.textService.hasAccessibilityPermission ? "Granted" : "Denied",
                    color: coordinator.textService.hasAccessibilityPermission ? .green : .red
                )

                StatusIndicator(
                    title: "AI Service",
                    value: coordinator.aiService.hasAnyProvider ? "Ready" : "No API Key",
                    color: coordinator.aiService.hasAnyProvider ? .green : .orange
                )

                if let appName = coordinator.textService.focusedAppName {
                    StatusIndicator(
                        title: "Focused App",
                        value: appName,
                        color: .blue
                    )
                }
            }

            // Writing detection status
            if coordinator.focusedElementDetector.isWriting {
                HStack {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.green)
                    Text("Writing detected in text field")
                        .font(DesignSystem.Fonts.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 600)
    }

    private var stateText: String {
        switch coordinator.state {
        case .idle: return "Idle"
        case .observing: return "Observing"
        case .analyzing: return "Analyzing"
        case .generating: return "Generating"
        case .displaying: return "Displaying"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var stateColor: Color {
        switch coordinator.state {
        case .idle: return .gray
        case .observing: return .green
        case .analyzing: return .blue
        case .generating: return .purple
        case .displaying: return .green
        case .error: return .red
        }
    }
}

struct StatusIndicator: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(value)
                    .font(DesignSystem.Fonts.caption)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }
}

struct SessionStatView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(DesignSystem.Fonts.title)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text(title)
                .font(DesignSystem.Fonts.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }
}

struct MattersView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: 12) {
                Text("No Matters Found")
                    .font(DesignSystem.Fonts.display)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text("Organize your work by Matter to get context-aware suggestions\nbased on specific clients and case laws.")
                    .font(DesignSystem.Fonts.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            Button(action: {
                // TODO: Create matter action
            }) {
                Label("Create New Matter", systemImage: "plus.circle.fill")
                    .font(DesignSystem.Fonts.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.background)
    }
}

struct ModelSettingsView: View {
    @EnvironmentObject var aiService: AIProviderService

    var body: some View {
        Form {
            Section("Configured Providers") {
                ForEach(Array(aiService.configuredProviders), id: \.self) { provider in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(provider.displayName)
                        Spacer()
                    }
                }

                if aiService.configuredProviders.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("No providers configured")
                        Spacer()
                        SettingsLink {
                            Text("Add API Key")
                        }
                    }
                }
            }

            Section("Default Model") {
                Picker("Model", selection: .constant(aiService.defaultModel)) {
                    ForEach(aiService.availableModels, id: \.id) { model in
                        Text(model.displayName).tag(model)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct SessionsView: View {
    @Query(sort: \WritingSession.startTime, order: .reverse) private var sessions: [WritingSession]

    var body: some View {
        if sessions.isEmpty {
            ContentUnavailableView(
                "No Sessions",
                systemImage: "clock",
                description: Text("Your writing sessions will appear here")
            )
        } else {
            List(sessions) { session in
                VStack(alignment: .leading) {
                    Text(session.documentTitle ?? "Untitled Session")
                        .font(.headline)
                    Text(session.startTime.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MainWindowView()
        .environmentObject(AIProviderService())
        .environmentObject(DraftingCoordinator())
        .frame(width: 900, height: 700)
}
