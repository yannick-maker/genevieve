import SwiftUI
import SwiftData

@main
struct GenevieveApp: App {
    // MARK: - State

    @StateObject private var aiService = AIProviderService()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // MARK: - SwiftData

    let modelContainer: ModelContainer

    // MARK: - Initialization

    init() {
        do {
            let schema = Schema([
                WritingSession.self,
                DraftSuggestion.self,
                Matter.self,
                Argument.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    // MARK: - Body

    var body: some Scene {
        // Menu Bar
        MenuBarExtra {
            GenevieveMenuView()
                .environmentObject(aiService)
        } label: {
            MenuBarIcon(isProcessing: aiService.isProcessing)
        }
        .menuBarExtraStyle(.window)

        // Settings Window
        Settings {
            SettingsView()
                .environmentObject(aiService)
        }

        // Onboarding Window
        Window("Welcome to Genevieve", id: "onboarding") {
            OnboardingView(isComplete: $hasCompletedOnboarding)
                .environmentObject(aiService)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 600)
    }
}

// MARK: - Menu Bar Icon

struct MenuBarIcon: View {
    let isProcessing: Bool

    var body: some View {
        Image(systemName: isProcessing ? "brain.head.profile.fill" : "brain.head.profile")
            .symbolRenderingMode(.hierarchical)
    }
}

// MARK: - Menu View

struct GenevieveMenuView: View {
    @EnvironmentObject var aiService: AIProviderService
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            headerView

            Divider()

            // Status
            statusView

            Divider()

            // Quick Actions
            quickActionsView

            Divider()

            // Bottom Actions
            bottomActionsView
        }
        .padding()
        .frame(width: 280)
        .task {
            await aiService.initialize()

            // Show onboarding if not completed
            if !hasCompletedOnboarding {
                openWindow(id: "onboarding")
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Genevieve")
                    .font(.headline)
                Text("AI Drafting Co-Pilot")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status indicator
            Circle()
                .fill(aiService.hasAnyProvider ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
        }
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if aiService.hasAnyProvider {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Ready")
                        .font(.subheadline)
                    Spacer()
                    Text(aiService.defaultModel.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Configured providers
                HStack(spacing: 8) {
                    ForEach(Array(aiService.configuredProviders), id: \.self) { provider in
                        ProviderBadge(provider: provider)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("No API keys configured")
                        .font(.subheadline)
                }

                Button("Add API Key") {
                    openSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var quickActionsView: some View {
        VStack(spacing: 8) {
            Button(action: {
                // TODO: Toggle sidebar
            }) {
                HStack {
                    Image(systemName: "sidebar.right")
                    Text("Toggle Sidebar")
                    Spacer()
                    Text("Cmd+Shift+G")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!aiService.hasAnyProvider)

            Button(action: {
                // TODO: Analyze current context
            }) {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Analyze Selection")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .disabled(!aiService.hasAnyProvider)
        }
    }

    private var bottomActionsView: some View {
        HStack {
            SettingsLink {
                Label("Settings", systemImage: "gear")
            }

            Spacer()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Provider Badge

struct ProviderBadge: View {
    let provider: AIProviderType

    var body: some View {
        Text(provider.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    GenevieveMenuView()
        .environmentObject(AIProviderService())
        .frame(width: 280)
}
