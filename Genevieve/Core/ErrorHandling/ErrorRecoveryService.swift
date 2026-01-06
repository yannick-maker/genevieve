import Foundation
import SwiftUI
import Combine

/// Centralized error handling and recovery service
@MainActor
final class ErrorRecoveryService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var currentError: AppError?
    @Published private(set) var errorHistory: [ErrorRecord] = []
    @Published var showErrorAlert = false

    // MARK: - Types

    enum AppError: LocalizedError, Identifiable {
        case apiKeyMissing(provider: String)
        case apiError(provider: String, message: String)
        case networkError(Error)
        case accessibilityPermissionDenied
        case screenRecordingPermissionDenied
        case textInsertionFailed
        case dataCorruption(String)
        case exportFailed(Error)
        case importFailed(Error)
        case unknownError(Error)

        var id: String {
            switch self {
            case .apiKeyMissing(let provider): return "apiKeyMissing_\(provider)"
            case .apiError(let provider, _): return "apiError_\(provider)"
            case .networkError: return "networkError"
            case .accessibilityPermissionDenied: return "accessibilityPermission"
            case .screenRecordingPermissionDenied: return "screenRecordingPermission"
            case .textInsertionFailed: return "textInsertionFailed"
            case .dataCorruption(let detail): return "dataCorruption_\(detail)"
            case .exportFailed: return "exportFailed"
            case .importFailed: return "importFailed"
            case .unknownError: return "unknownError"
            }
        }

        var errorDescription: String? {
            switch self {
            case .apiKeyMissing(let provider):
                return "API key for \(provider) is not configured"
            case .apiError(let provider, let message):
                return "\(provider) API error: \(message)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .accessibilityPermissionDenied:
                return "Accessibility permission is required"
            case .screenRecordingPermissionDenied:
                return "Screen recording permission is required"
            case .textInsertionFailed:
                return "Failed to insert text into the application"
            case .dataCorruption(let detail):
                return "Data corruption detected: \(detail)"
            case .exportFailed(let error):
                return "Export failed: \(error.localizedDescription)"
            case .importFailed(let error):
                return "Import failed: \(error.localizedDescription)"
            case .unknownError(let error):
                return "An unexpected error occurred: \(error.localizedDescription)"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .apiKeyMissing:
                return "Go to Settings and enter your API key"
            case .apiError:
                return "Check your API key and try again"
            case .networkError:
                return "Check your internet connection and try again"
            case .accessibilityPermissionDenied:
                return "Open System Settings > Privacy & Security > Accessibility and enable Genevieve"
            case .screenRecordingPermissionDenied:
                return "Open System Settings > Privacy & Security > Screen Recording and enable Genevieve"
            case .textInsertionFailed:
                return "Try copying the suggestion manually using the copy button"
            case .dataCorruption:
                return "Some data may need to be reset. Contact support if the issue persists"
            case .exportFailed:
                return "Check that you have write permissions to the selected location"
            case .importFailed:
                return "Ensure the file is in the correct format"
            case .unknownError:
                return "Try restarting the application"
            }
        }

        var severity: ErrorSeverity {
            switch self {
            case .apiKeyMissing: return .warning
            case .apiError: return .error
            case .networkError: return .warning
            case .accessibilityPermissionDenied: return .critical
            case .screenRecordingPermissionDenied: return .warning
            case .textInsertionFailed: return .warning
            case .dataCorruption: return .critical
            case .exportFailed: return .error
            case .importFailed: return .error
            case .unknownError: return .error
            }
        }

        var recoveryAction: RecoveryAction? {
            switch self {
            case .apiKeyMissing:
                return .openSettings
            case .accessibilityPermissionDenied:
                return .openSystemSettings
            case .screenRecordingPermissionDenied:
                return .openSystemSettings
            case .textInsertionFailed:
                return .copyToClipboard
            default:
                return nil
            }
        }
    }

    enum ErrorSeverity {
        case info
        case warning
        case error
        case critical

        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            case .critical: return .red
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .critical: return "exclamationmark.octagon.fill"
            }
        }
    }

    enum RecoveryAction {
        case openSettings
        case openSystemSettings
        case copyToClipboard
        case retry
        case reset

        var buttonTitle: String {
            switch self {
            case .openSettings: return "Open Settings"
            case .openSystemSettings: return "Open System Settings"
            case .copyToClipboard: return "Copy to Clipboard"
            case .retry: return "Try Again"
            case .reset: return "Reset"
            }
        }
    }

    struct ErrorRecord: Identifiable {
        let id = UUID()
        let error: AppError
        let timestamp: Date
        var wasRecovered: Bool = false

        init(error: AppError) {
            self.error = error
            self.timestamp = Date()
        }
    }

    // MARK: - Configuration

    private let maxHistorySize = 50

    // MARK: - Callbacks

    var onOpenSettings: (() -> Void)?
    var onCopyToClipboard: ((String) -> Void)?

    // MARK: - Public API

    /// Report an error
    func report(_ error: AppError) {
        currentError = error
        showErrorAlert = true

        // Add to history
        let record = ErrorRecord(error: error)
        errorHistory.insert(record, at: 0)

        // Trim history
        if errorHistory.count > maxHistorySize {
            errorHistory = Array(errorHistory.prefix(maxHistorySize))
        }

        // Log error
        logError(error)
    }

    /// Attempt automatic recovery
    func attemptRecovery(for error: AppError) -> Bool {
        switch error {
        case .textInsertionFailed:
            // Fall back to clipboard
            return true

        case .networkError:
            // Could implement retry logic
            return false

        default:
            return false
        }
    }

    /// Perform recovery action
    func performRecoveryAction(_ action: RecoveryAction, for error: AppError) {
        switch action {
        case .openSettings:
            onOpenSettings?()

        case .openSystemSettings:
            openSystemSettings()

        case .copyToClipboard:
            // The calling code should handle this
            break

        case .retry:
            // The calling code should handle this
            break

        case .reset:
            resetErrorState()
        }

        // Mark as recovered in history
        if let index = errorHistory.firstIndex(where: { $0.error.id == error.id }) {
            errorHistory[index].wasRecovered = true
        }
    }

    /// Clear current error
    func dismiss() {
        currentError = nil
        showErrorAlert = false
    }

    /// Clear error history
    func clearHistory() {
        errorHistory.removeAll()
    }

    // MARK: - Private Methods

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    private func resetErrorState() {
        currentError = nil
        showErrorAlert = false
    }

    private func logError(_ error: AppError) {
        // In production, this would send to a logging service
        print("[Genevieve Error] \(error.id): \(error.errorDescription ?? "Unknown")")
    }

    // MARK: - Convenience Methods

    /// Wrap an async operation with error handling
    func withErrorHandling<T>(
        operation: () async throws -> T,
        fallback: T? = nil
    ) async -> T? {
        do {
            return try await operation()
        } catch let error as AppError {
            report(error)
            return fallback
        } catch {
            report(.unknownError(error))
            return fallback
        }
    }

    /// Convert common errors to AppError
    static func mapError(_ error: Error, context: String? = nil) -> AppError {
        if let urlError = error as? URLError {
            return .networkError(urlError)
        }

        // Check for common API error patterns
        let description = error.localizedDescription.lowercased()
        if description.contains("api key") || description.contains("unauthorized") {
            return .apiKeyMissing(provider: context ?? "Unknown")
        }

        return .unknownError(error)
    }
}

// MARK: - Error Alert View

struct ErrorAlertView: View {
    @ObservedObject var errorService: ErrorRecoveryService

    var body: some View {
        if let error = errorService.currentError {
            VStack(spacing: 16) {
                // Icon
                Image(systemName: error.severity.icon)
                    .font(.largeTitle)
                    .foregroundStyle(error.severity.color)

                // Title
                Text(error.errorDescription ?? "An error occurred")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                // Recovery suggestion
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Actions
                HStack(spacing: 12) {
                    Button("Dismiss") {
                        errorService.dismiss()
                    }
                    .buttonStyle(.bordered)

                    if let action = error.recoveryAction {
                        Button(action.buttonTitle) {
                            errorService.performRecoveryAction(action, for: error)
                            errorService.dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 400)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 20)
        }
    }
}

// MARK: - Error Banner View

struct ErrorBannerView: View {
    let error: ErrorRecoveryService.AppError
    let onDismiss: () -> Void
    let onAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: error.severity.icon)
                .foregroundStyle(error.severity.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "Error")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let action = error.recoveryAction {
                Button(action.buttonTitle) {
                    onAction?()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(error.severity.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Error History View

struct ErrorHistoryView: View {
    @ObservedObject var errorService: ErrorRecoveryService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Error History")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if !errorService.errorHistory.isEmpty {
                    Button("Clear All") {
                        errorService.clearHistory()
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if errorService.errorHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.green)

                    Text("No errors recorded")
                        .font(.headline)

                    Text("Any errors that occur will appear here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(errorService.errorHistory) { record in
                            ErrorHistoryRow(record: record)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }
}

struct ErrorHistoryRow: View {
    let record: ErrorRecoveryService.ErrorRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.error.severity.icon)
                .foregroundStyle(record.wasRecovered ? .green : record.error.severity.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.error.errorDescription ?? "Error")
                    .font(.subheadline)

                Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if record.wasRecovered {
                Text("Recovered")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    ErrorAlertView(errorService: ErrorRecoveryService())
}
