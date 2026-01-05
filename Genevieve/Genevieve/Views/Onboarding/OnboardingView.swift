import SwiftUI

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @EnvironmentObject var aiService: AIProviderService
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep = 0

    private let steps = [
        OnboardingStep.welcome,
        OnboardingStep.apiKey,
        OnboardingStep.ready
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            // Content
            TabView(selection: $currentStep) {
                ForEach(0..<steps.count, id: \.self) { index in
                    stepView(for: steps[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.automatic)

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button("Next") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceed)
                } else {
                    Button("Get Started") {
                        isComplete = true
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!aiService.hasAnyProvider)
                }
            }
            .padding(20)
        }
        .frame(width: 500, height: 600)
    }

    private var canProceed: Bool {
        switch steps[currentStep] {
        case .welcome:
            return true
        case .apiKey:
            return aiService.hasAnyProvider
        case .ready:
            return true
        }
    }

    @ViewBuilder
    private func stepView(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            WelcomeStepView()
        case .apiKey:
            APIKeyStepView()
        case .ready:
            ReadyStepView()
        }
    }
}

// MARK: - Onboarding Steps

enum OnboardingStep {
    case welcome
    case apiKey
    case ready
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Icon
            Image(systemName: "brain.head.profile")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)

            // Title
            Text("Welcome to Genevieve")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Subtitle
            Text("Your AI Drafting Co-Pilot")
                .font(.title2)
                .foregroundStyle(.secondary)

            // Features
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "wand.and.stars",
                    title: "Proactive Suggestions",
                    description: "Get intelligent drafting alternatives as you write"
                )

                FeatureRow(
                    icon: "person.2.fill",
                    title: "Professional Peer",
                    description: "Like having a colleague review your work in real-time"
                )

                FeatureRow(
                    icon: "brain",
                    title: "Multi-Model AI",
                    description: "Choose from Claude, Gemini, or GPT for the best results"
                )

                FeatureRow(
                    icon: "lock.shield",
                    title: "Privacy First",
                    description: "Your documents stay on your device"
                )
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - API Key Step

struct APIKeyStepView: View {
    @EnvironmentObject var aiService: AIProviderService
    @State private var selectedProvider: AIProviderType = .claude
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var isValidating = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Icon
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)

            // Title
            Text("Add an API Key")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Genevieve needs at least one AI provider to work")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Provider selection
            Picker("Provider", selection: $selectedProvider) {
                ForEach(AIProviderType.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 60)

            // API Key input
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Group {
                        if showKey {
                            TextField("Paste your API key", text: $apiKey)
                        } else {
                            SecureField("Paste your API key", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button(action: { showKey.toggle() }) {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }

                // Error message
                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Help link
                Link(destination: providerURL) {
                    Text("Get \(selectedProvider.displayName) API key")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 60)

            // Save button
            Button(action: saveKey) {
                if isValidating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Validate & Save")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiKey.isEmpty || isValidating)

            // Configured providers
            if !aiService.configuredProviders.isEmpty {
                VStack(spacing: 8) {
                    Text("Configured:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        ForEach(Array(aiService.configuredProviders), id: \.self) { provider in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(provider.displayName)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    private var providerURL: URL {
        switch selectedProvider {
        case .claude:
            return URL(string: "https://console.anthropic.com/")!
        case .gemini:
            return URL(string: "https://aistudio.google.com/")!
        case .openAI:
            return URL(string: "https://platform.openai.com/")!
        }
    }

    private func saveKey() {
        guard !apiKey.isEmpty else { return }

        isValidating = true
        error = nil

        Task {
            do {
                let isValid = try await aiService.validateAPIKey(apiKey, for: selectedProvider)

                if isValid {
                    try await aiService.configureProvider(selectedProvider, apiKey: apiKey)
                    apiKey = ""

                    // Auto-advance to next provider if user wants to add more
                    if let nextProvider = AIProviderType.allCases.first(where: {
                        !aiService.configuredProviders.contains($0)
                    }) {
                        selectedProvider = nextProvider
                    }
                } else {
                    error = "Invalid API key. Please check and try again."
                }
            } catch {
                self.error = error.localizedDescription
            }

            isValidating = false
        }
    }
}

// MARK: - Ready Step

struct ReadyStepView: View {
    @EnvironmentObject var aiService: AIProviderService

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            // Title
            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Genevieve is ready to help you draft")
                .font(.title3)
                .foregroundStyle(.secondary)

            // Summary
            VStack(alignment: .leading, spacing: 16) {
                SummaryRow(
                    icon: "brain",
                    text: "Using \(aiService.defaultModel.displayName) by default"
                )

                SummaryRow(
                    icon: "keyboard",
                    text: "Toggle sidebar with Cmd + Shift + G"
                )

                SummaryRow(
                    icon: "menubar.rectangle",
                    text: "Access Genevieve from the menu bar"
                )
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 20)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }
}

struct SummaryRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            Text(text)
                .font(.body)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(isComplete: .constant(false))
        .environmentObject(AIProviderService())
}
