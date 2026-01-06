import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            APIKeysSettingsTab()
                .tabItem {
                    Label("API Keys", systemImage: "key")
                }

            ModelsSettingsTab()
                .tabItem {
                    Label("Models", systemImage: "brain")
                }

            ShortcutsSettingsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 550, height: 400)
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInDock") private var showInDock = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Show in Dock", isOn: $showInDock)
            } header: {
                Text("Startup")
            }

            Section {
                LabeledContent("Version") {
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Build") {
                    Text("1")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - API Keys Settings

struct APIKeysSettingsTab: View {
    @EnvironmentObject var aiService: AIProviderService

    var body: some View {
        Form {
            Section {
                APIKeyField(
                    provider: .claude,
                    isConfigured: aiService.configuredProviders.contains(.claude)
                )

                APIKeyField(
                    provider: .gemini,
                    isConfigured: aiService.configuredProviders.contains(.gemini)
                )

                APIKeyField(
                    provider: .openAI,
                    isConfigured: aiService.configuredProviders.contains(.openAI)
                )
            } header: {
                Text("API Keys")
            } footer: {
                Text("Your API keys are stored securely in the macOS Keychain.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct APIKeyField: View {
    let provider: AIProviderType
    let isConfigured: Bool

    @EnvironmentObject var aiService: AIProviderService
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var isValidating = false
    @State private var validationResult: ValidationResult?

    enum ValidationResult {
        case success
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.displayName)
                    .font(.headline)

                Spacer()

                if isConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            HStack {
                Group {
                    if showKey {
                        TextField("API Key", text: $apiKey)
                    } else {
                        SecureField("API Key", text: $apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button(action: { showKey.toggle() }) {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)

                Button(action: saveKey) {
                    if isValidating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(apiKey.isEmpty || isValidating)
            }

            // Validation result
            if let result = validationResult {
                HStack {
                    switch result {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("API key validated successfully")
                            .foregroundStyle(.green)
                    case .failure(let message):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
            }

            // Provider-specific instructions
            Text(instructionText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var instructionText: String {
        switch provider {
        case .claude:
            return "Get your API key at console.anthropic.com"
        case .gemini:
            return "Get your API key at aistudio.google.com"
        case .openAI:
            return "Get your API key at platform.openai.com"
        }
    }

    private func saveKey() {
        guard !apiKey.isEmpty else { return }

        isValidating = true
        validationResult = nil

        Task {
            do {
                let isValid = try await aiService.validateAPIKey(apiKey, for: provider)

                if isValid {
                    try await aiService.configureProvider(provider, apiKey: apiKey)
                    validationResult = .success
                    apiKey = ""  // Clear after successful save
                } else {
                    validationResult = .failure("Invalid API key")
                }
            } catch {
                validationResult = .failure(error.localizedDescription)
            }

            isValidating = false
        }
    }
}

// MARK: - Models Settings

struct ModelsSettingsTab: View {
    @EnvironmentObject var aiService: AIProviderService

    var body: some View {
        Form {
            Section {
                Picker("Default Model", selection: Binding(
                    get: { aiService.defaultModel },
                    set: { aiService.setDefaultModel($0) }
                )) {
                    ForEach(aiService.availableModels) { model in
                        Text(model.displayName).tag(model)
                    }
                }
            } header: {
                Text("Default Model")
            } footer: {
                Text("This model will be used for most tasks. Higher-tier models produce better results but may be slower.")
            }

            Section {
                ForEach(aiService.availableModels) { model in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                                .font(.headline)
                            Text(model.provider.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Quality tier badge
                        Text(model.qualityTier == .smart ? "Smart" : "Fast")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(model.qualityTier == .smart ? Color.purple.opacity(0.2) : Color.blue.opacity(0.2))
                            .clipShape(Capsule())

                        // Vision support badge
                        if model.supportsVision {
                            Image(systemName: "eye")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Available Models")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Shortcuts Settings

struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            Section {
                ShortcutRow(action: "Toggle Sidebar", shortcut: "Cmd + Shift + G")
                ShortcutRow(action: "Accept Suggestion", shortcut: "Tab")
                ShortcutRow(action: "Dismiss Suggestion", shortcut: "Esc")
                ShortcutRow(action: "Next Suggestion", shortcut: "Down Arrow")
                ShortcutRow(action: "Previous Suggestion", shortcut: "Up Arrow")
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Keyboard shortcuts work globally when Genevieve is running.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutRow: View {
    let action: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(shortcut)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AIProviderService())
}
