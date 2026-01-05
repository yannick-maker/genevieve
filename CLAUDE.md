# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run Commands

```bash
# Build using Xcode command line
xcodebuild -project screencoach.xcodeproj -scheme screencoach -configuration Debug -destination 'platform=macOS' build

# Run the app after building
open ~/Library/Developer/Xcode/DerivedData/screencoach-*/Build/Products/Debug/screencoach.app

# Build using Swift Package Manager (alternative, Package.swift is in project root)
swift build --package-path .
```

## Architecture Overview

ScreenCoach is a macOS menu bar application that monitors user screen activity and provides AI-powered productivity insights using Google's Gemini API.

### Core Flow
1. **ScreenCaptureManager** captures screenshots at 1 fps using ScreenCaptureKit
2. **ChangeDetector** identifies significant visual changes between frames
3. **GeminiService** analyzes screenshots to classify activity and generate insights
4. **SessionCoordinator** orchestrates the capture-analyze loop and manages SwiftData persistence
5. **NotificationManager** delivers productivity insights via macOS notifications

### Key Components

- **App/ScreenCoachApp.swift**: Main entry point. Menu bar app using `MenuBarExtra`, SwiftData container setup, onboarding flow
- **Services/SessionCoordinator.swift**: Central state manager (`@MainActor ObservableObject`). Controls capture sessions, rate-limits analysis to 30-second intervals, creates `ActivityNote` records from AI analysis
- **Core/AI/GeminiService.swift**: Handles Gemini API calls. Converts screenshots to JPEG, sends to `gemini-3-flash` model, parses JSON responses into `ScreenAnalysis`
- **Core/AI/RetrospectiveGenerator.swift**: Generates end-of-day summaries from accumulated `ActivityNote` records
- **Core/ScreenCapture/ScreenCaptureManager.swift**: SCStream wrapper, downsamples by 2x, delegates to `ChangeDetector`
- **Views/FloatingPanel/FloatingPanelController.swift**: Always-on-top NSPanel for displaying insights

### Data Models (SwiftData)

- **Session**: Work session with start/end times, contains notes and feedback
- **ActivityNote**: Individual activity record with category, focus level, timestamp
- **Feedback**: Milestone messages (e.g., "1 hour of focused work!")
- **Retrospective**: Daily summary with highlights, focus score, suggestions

### Activity Categories
`Coding`, `Writing`, `Communication`, `Browsing`, `Meeting`, `Design`, `Research`, `Other`

### Focus Levels
`high`, `medium`, `low`, `distracted`

## Key Patterns

- All UI-related classes are `@MainActor`
- API key stored in Keychain via `KeychainManager`
- Screen recording requires user permission (handled by `PermissionHandler`)
- App is sandboxed with network client entitlement
