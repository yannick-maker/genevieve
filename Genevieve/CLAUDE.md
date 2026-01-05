# CLAUDE.md - Genevieve

This file provides guidance to Claude Code when working with the Genevieve codebase.

## Build & Run Commands

```bash
# Build using Swift Package Manager
swift build

# Build for release
swift build -c release

# Run the app (from Genevieve directory)
swift run Genevieve
```

## Architecture Overview

Genevieve is a macOS menu bar application that serves as an AI legal drafting co-pilot. It observes the user's screen, detects writing context, and proactively offers drafting suggestions.

### Core Concept
- **Screen-aware AI** that observes writing activity across any text field
- **Proactive suggestions** via floating sidebar - like a professional peer looking over your shoulder
- **Multi-model support** - Claude, Gemini, and OpenAI with automatic task-based routing

### Key Components

#### App Layer (`App/`)
- **GenevieveApp.swift**: Main entry point. Menu bar app using `MenuBarExtra`, SwiftData container setup, onboarding flow

#### Core/AI (`Core/AI/`)
- **AIProvider.swift**: Protocol and types for AI providers, task categories, model definitions
- **ClaudeProvider.swift**: Anthropic Claude API implementation with streaming
- **GeminiProvider.swift**: Google Gemini API implementation
- **OpenAIProvider.swift**: OpenAI API implementation with streaming
- **AIProviderService.swift**: Unified routing service with automatic model selection
- **PromptTemplates.swift**: Legal-specific prompts for different document types

#### Core/Accessibility (`Core/Accessibility/`)
- **AccessibilityTextService.swift**: macOS Accessibility API wrapper for text detection and insertion
- **FocusedElementDetector.swift**: Higher-level writing context detection

#### Core/Observation (`Core/Observation/`)
- **ScreenObserver.swift**: App/window tracking, distraction detection
- **ContextAnalyzer.swift**: AI-powered document type classification
- **StuckDetector.swift**: Multi-signal detection (pause, distraction, rewriting, navigation)

#### Core/Storage (`Core/Storage/`)
- **KeychainManager.swift**: Secure API key storage for multiple providers

#### Services (`Services/`)
- **DraftingCoordinator.swift**: Central orchestrator connecting all services
- **DraftingAssistant.swift**: Suggestion generation engine
- **ArgumentLibrary.swift**: Reusable argument storage and retrieval
- **MatterTracker.swift**: Legal matter/case tracking

#### Models (`Models/`)
- **WritingSession.swift**: SwiftData model for session tracking
- **DraftSuggestion.swift**: SwiftData model for suggestions
- **Matter.swift**: SwiftData model for legal matters
- **Argument.swift**: SwiftData model for argument library

#### Views (`Views/`)
- **Sidebar/**: Floating suggestion panel components
  - `GenevieveSidebarController.swift`: NSPanel controller
  - `SuggestionPanelView.swift`: Main sidebar view
  - `SuggestionCardView.swift`: Individual suggestion cards
- **Settings/**: Settings window
- **Onboarding/**: First-launch flow
- **ArgumentLibrary/**: Argument library browser

### Data Flow

1. **ScreenObserver** monitors active app/window
2. **FocusedElementDetector** detects text fields via Accessibility API
3. **ContextAnalyzer** classifies document type and section
4. **StuckDetector** monitors for user struggle signals
5. **DraftingAssistant** generates AI suggestions when triggered
6. **GenevieveSidebarController** displays suggestions in floating panel
7. **AccessibilityTextService** inserts accepted suggestions

### AI Task Routing

```swift
enum AITaskCategory {
    case draftSuggestion    // Premium tier (Claude Opus, GPT-5)
    case contextAnalysis    // Premium tier (vision capable)
    case quickEdit          // Standard tier (faster, cheaper)
}
```

### Stuck Detection Signals

| Signal | Weight | Description |
|--------|--------|-------------|
| Pause | 35% | Time without typing |
| Distraction | 30% | Non-work app usage |
| Rewriting | 25% | Repeated deletions/edits |
| Navigation | 10% | Rapid scrolling |

### Key Patterns

- All UI-related classes are `@MainActor`
- API keys stored in Keychain via `KeychainManager`
- Accessibility permission required for text detection/insertion
- SwiftData for persistent storage
- Combine for reactive data flow

### Privacy Model

- Screen observations are ephemeral (process and discard)
- Document text kept only for current session
- Activity patterns stored anonymized
- All AI calls require explicit API keys

### Keyboard Shortcuts

- `Cmd+Shift+G`: Toggle suggestion sidebar
- `Tab`: Accept current suggestion
- `Esc`: Dismiss suggestion
- `↑/↓`: Navigate suggestions
