import SwiftUI
import SwiftData

struct MainWindowView: View {
    @EnvironmentObject var aiService: AIProviderService
    @Environment(\.modelContext) private var modelContext
    @StateObject private var argumentLibrary = ArgumentLibrary()
    @State private var selectedTab: MainTab = .dashboard
    @State private var showingSidebar = true

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

// MARK: - Placeholder Views

struct DashboardView: View {
    @EnvironmentObject var aiService: AIProviderService

    private let cardSpacing: CGFloat = 16
    private let horizontalPadding: CGFloat = 24

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Welcome Header
                VStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Welcome to Genevieve")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Your AI Legal Drafting Co-Pilot")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                // Status Cards - using GeometryReader for equal widths
                VStack(alignment: .leading, spacing: 12) {
                    Text("Status")
                        .font(.headline)

                    HStack(spacing: cardSpacing) {
                        StatusCard(
                            title: "AI Status",
                            value: aiService.hasAnyProvider ? "Ready" : "Setup Required",
                            icon: "cpu",
                            color: aiService.hasAnyProvider ? .green : .orange
                        )

                        StatusCard(
                            title: "Default Model",
                            value: aiService.defaultModel.displayName,
                            icon: "brain",
                            color: .blue
                        )

                        StatusCard(
                            title: "Providers",
                            value: "\(aiService.configuredProviders.count) configured",
                            icon: "server.rack",
                            color: .purple
                        )
                    }
                }
                .padding(.horizontal, horizontalPadding)

                // Quick Actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Actions")
                        .font(.headline)

                    HStack(spacing: cardSpacing) {
                        QuickActionButton(
                            title: "Start Drafting",
                            icon: "wand.and.stars",
                            color: .blue
                        ) {
                            // TODO: Open drafting
                        }

                        QuickActionButton(
                            title: "Browse Arguments",
                            icon: "books.vertical",
                            color: .purple
                        ) {
                            // TODO: Open arguments
                        }

                        QuickActionButton(
                            title: "Configure AI",
                            icon: "gear",
                            color: .gray
                        ) {
                            // TODO: Open settings
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Spacer()

            Text(value)
                .font(.headline)
                .lineLimit(1)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 100)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .padding(.horizontal)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct DraftingView: View {
    var body: some View {
        ContentUnavailableView(
            "Drafting Assistant",
            systemImage: "wand.and.stars",
            description: Text("Start writing and Genevieve will offer suggestions")
        )
    }
}

struct MattersView: View {
    var body: some View {
        ContentUnavailableView(
            "Matters",
            systemImage: "folder",
            description: Text("Track your legal matters and cases")
        )
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
        .frame(width: 900, height: 700)
}
