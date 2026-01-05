import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Service for exporting data to portable formats (JSON, CSV)
@MainActor
final class DataExportService: ObservableObject {
    // MARK: - Types

    enum ExportFormat: String, CaseIterable {
        case json
        case csv

        var fileExtension: String { rawValue }

        var contentType: UTType {
            switch self {
            case .json: return .json
            case .csv: return .commaSeparatedText
            }
        }
    }

    enum ExportError: LocalizedError {
        case noData
        case encodingFailed
        case writeFailed(Error)
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .noData:
                return "No data to export"
            case .encodingFailed:
                return "Failed to encode data"
            case .writeFailed(let error):
                return "Failed to write file: \(error.localizedDescription)"
            case .invalidFormat:
                return "Invalid export format for this data type"
            }
        }
    }

    struct ExportResult {
        let url: URL
        let format: ExportFormat
        let itemCount: Int
        let fileSize: Int64
    }

    // MARK: - Properties

    private var modelContext: ModelContext?

    // MARK: - Initialization

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    // MARK: - Argument Library Export

    /// Export all arguments to the specified format
    func exportArguments(
        to format: ExportFormat,
        destination: URL? = nil
    ) throws -> ExportResult {
        guard let modelContext = modelContext else {
            throw ExportError.noData
        }

        let descriptor = FetchDescriptor<Argument>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let arguments = try? modelContext.fetch(descriptor),
              !arguments.isEmpty else {
            throw ExportError.noData
        }

        let data: Data
        switch format {
        case .json:
            data = try encodeArgumentsToJSON(arguments)
        case .csv:
            data = try encodeArgumentsToCSV(arguments)
        }

        let url = try writeToFile(
            data: data,
            filename: "genevieve_arguments_\(timestamp)",
            format: format,
            destination: destination
        )

        return ExportResult(
            url: url,
            format: format,
            itemCount: arguments.count,
            fileSize: Int64(data.count)
        )
    }

    private func encodeArgumentsToJSON(_ arguments: [Argument]) throws -> Data {
        let exportData = arguments.map { arg -> [String: Any] in
            var dict: [String: Any] = [
                "id": arg.id.uuidString,
                "title": arg.title,
                "content": arg.content,
                "category": arg.category ?? "uncategorized",
                "createdAt": ISO8601DateFormatter().string(from: arg.createdAt),
                "updatedAt": ISO8601DateFormatter().string(from: arg.updatedAt),
                "useCount": arg.useCount,
                "isFavorite": arg.isFavorite
            ]

            if let tags = arg.tags, !tags.isEmpty {
                dict["tags"] = tags
            }
            if let jurisdiction = arg.jurisdiction {
                dict["jurisdiction"] = jurisdiction
            }
            if let sources = arg.sources, !sources.isEmpty {
                dict["sources"] = sources
            }
            if let notes = arg.notes {
                dict["notes"] = notes
            }

            return dict
        }

        let wrapper: [String: Any] = [
            "version": "1.0",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "count": arguments.count,
            "arguments": exportData
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: wrapper,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            throw ExportError.encodingFailed
        }

        return data
    }

    private func encodeArgumentsToCSV(_ arguments: [Argument]) throws -> Data {
        var csv = "id,title,category,content,tags,jurisdiction,sources,use_count,is_favorite,created_at,updated_at,notes\n"

        for arg in arguments {
            let row = [
                arg.id.uuidString,
                escapeCSV(arg.title),
                escapeCSV(arg.category ?? ""),
                escapeCSV(arg.content),
                escapeCSV((arg.tags ?? []).joined(separator: ";")),
                escapeCSV(arg.jurisdiction ?? ""),
                escapeCSV((arg.sources ?? []).joined(separator: ";")),
                String(arg.useCount),
                arg.isFavorite ? "true" : "false",
                ISO8601DateFormatter().string(from: arg.createdAt),
                ISO8601DateFormatter().string(from: arg.updatedAt),
                escapeCSV(arg.notes ?? "")
            ].joined(separator: ",")

            csv += row + "\n"
        }

        guard let data = csv.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }

        return data
    }

    // MARK: - Session History Export

    /// Export all writing sessions to the specified format
    func exportSessions(
        to format: ExportFormat,
        destination: URL? = nil
    ) throws -> ExportResult {
        guard let modelContext = modelContext else {
            throw ExportError.noData
        }

        let descriptor = FetchDescriptor<WritingSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )

        guard let sessions = try? modelContext.fetch(descriptor),
              !sessions.isEmpty else {
            throw ExportError.noData
        }

        let data: Data
        switch format {
        case .json:
            data = try encodeSessionsToJSON(sessions)
        case .csv:
            data = try encodeSessionsToCSV(sessions)
        }

        let url = try writeToFile(
            data: data,
            filename: "genevieve_sessions_\(timestamp)",
            format: format,
            destination: destination
        )

        return ExportResult(
            url: url,
            format: format,
            itemCount: sessions.count,
            fileSize: Int64(data.count)
        )
    }

    private func encodeSessionsToJSON(_ sessions: [WritingSession]) throws -> Data {
        let exportData = sessions.map { session -> [String: Any] in
            var dict: [String: Any] = [
                "id": session.id.uuidString,
                "startedAt": ISO8601DateFormatter().string(from: session.startedAt),
                "state": session.state,
                "duration": session.duration,
                "charactersTyped": session.charactersTyped,
                "wordsWritten": session.wordsWritten,
                "suggestionsShown": session.suggestionsShown,
                "suggestionsAccepted": session.suggestionsAccepted,
                "focusScore": session.focusScore,
                "productivityScore": session.productivityScore
            ]

            if let endedAt = session.endedAt {
                dict["endedAt"] = ISO8601DateFormatter().string(from: endedAt)
            }
            if let documentType = session.documentType {
                dict["documentType"] = documentType
            }
            if let appBundleID = session.appBundleID {
                dict["appBundleID"] = appBundleID
            }

            return dict
        }

        let wrapper: [String: Any] = [
            "version": "1.0",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "count": sessions.count,
            "sessions": exportData
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: wrapper,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            throw ExportError.encodingFailed
        }

        return data
    }

    private func encodeSessionsToCSV(_ sessions: [WritingSession]) throws -> Data {
        var csv = "id,started_at,ended_at,state,duration_seconds,characters_typed,words_written,suggestions_shown,suggestions_accepted,focus_score,productivity_score,document_type,app_bundle_id\n"

        for session in sessions {
            let row = [
                session.id.uuidString,
                ISO8601DateFormatter().string(from: session.startedAt),
                session.endedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                session.state,
                String(format: "%.0f", session.duration),
                String(session.charactersTyped),
                String(session.wordsWritten),
                String(session.suggestionsShown),
                String(session.suggestionsAccepted),
                String(format: "%.2f", session.focusScore),
                String(format: "%.2f", session.productivityScore),
                escapeCSV(session.documentType ?? ""),
                escapeCSV(session.appBundleID ?? "")
            ].joined(separator: ",")

            csv += row + "\n"
        }

        guard let data = csv.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }

        return data
    }

    // MARK: - Matters Export

    /// Export all matters to the specified format
    func exportMatters(
        to format: ExportFormat,
        destination: URL? = nil
    ) throws -> ExportResult {
        guard let modelContext = modelContext else {
            throw ExportError.noData
        }

        let descriptor = FetchDescriptor<Matter>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let matters = try? modelContext.fetch(descriptor),
              !matters.isEmpty else {
            throw ExportError.noData
        }

        let data: Data
        switch format {
        case .json:
            data = try encodeMattersToJSON(matters)
        case .csv:
            data = try encodeMattersToCSV(matters)
        }

        let url = try writeToFile(
            data: data,
            filename: "genevieve_matters_\(timestamp)",
            format: format,
            destination: destination
        )

        return ExportResult(
            url: url,
            format: format,
            itemCount: matters.count,
            fileSize: Int64(data.count)
        )
    }

    private func encodeMattersToJSON(_ matters: [Matter]) throws -> Data {
        let exportData = matters.map { matter -> [String: Any] in
            var dict: [String: Any] = [
                "id": matter.id.uuidString,
                "name": matter.name,
                "status": matter.status,
                "createdAt": ISO8601DateFormatter().string(from: matter.createdAt),
                "updatedAt": ISO8601DateFormatter().string(from: matter.updatedAt),
                "totalTimeSpent": matter.totalTimeSpent
            ]

            if let clientName = matter.clientName {
                dict["clientName"] = clientName
            }
            if let matterNumber = matter.matterNumber {
                dict["matterNumber"] = matterNumber
            }
            if let matterType = matter.matterType {
                dict["matterType"] = matterType
            }
            if let practiceArea = matter.practiceArea {
                dict["practiceArea"] = practiceArea
            }
            if let priority = matter.priority {
                dict["priority"] = priority
            }
            if let filingDeadline = matter.filingDeadline {
                dict["filingDeadline"] = ISO8601DateFormatter().string(from: filingDeadline)
            }
            if let trialDate = matter.trialDate {
                dict["trialDate"] = ISO8601DateFormatter().string(from: trialDate)
            }
            if let notes = matter.notes {
                dict["notes"] = notes
            }

            return dict
        }

        let wrapper: [String: Any] = [
            "version": "1.0",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "count": matters.count,
            "matters": exportData
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: wrapper,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            throw ExportError.encodingFailed
        }

        return data
    }

    private func encodeMattersToCSV(_ matters: [Matter]) throws -> Data {
        var csv = "id,name,client_name,matter_number,matter_type,practice_area,status,priority,filing_deadline,trial_date,total_time_spent,created_at,updated_at,notes\n"

        for matter in matters {
            let row = [
                matter.id.uuidString,
                escapeCSV(matter.name),
                escapeCSV(matter.clientName ?? ""),
                escapeCSV(matter.matterNumber ?? ""),
                escapeCSV(matter.matterType ?? ""),
                escapeCSV(matter.practiceArea ?? ""),
                escapeCSV(matter.status),
                escapeCSV(matter.priority ?? ""),
                matter.filingDeadline.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                matter.trialDate.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                String(format: "%.0f", matter.totalTimeSpent),
                ISO8601DateFormatter().string(from: matter.createdAt),
                ISO8601DateFormatter().string(from: matter.updatedAt),
                escapeCSV(matter.notes ?? "")
            ].joined(separator: ",")

            csv += row + "\n"
        }

        guard let data = csv.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }

        return data
    }

    // MARK: - Full Export

    /// Export all data to a directory
    func exportAll(
        to format: ExportFormat,
        directory: URL
    ) throws -> [ExportResult] {
        var results: [ExportResult] = []

        // Create export directory if needed
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        // Export each type
        if let result = try? exportArguments(to: format, destination: directory) {
            results.append(result)
        }

        if let result = try? exportSessions(to: format, destination: directory) {
            results.append(result)
        }

        if let result = try? exportMatters(to: format, destination: directory) {
            results.append(result)
        }

        return results
    }

    // MARK: - Import

    /// Import arguments from JSON file
    func importArguments(from url: URL) throws -> Int {
        guard let modelContext = modelContext else {
            throw ExportError.noData
        }

        let data = try Data(contentsOf: url)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arguments = json["arguments"] as? [[String: Any]] else {
            throw ExportError.encodingFailed
        }

        var importCount = 0

        for argData in arguments {
            guard let title = argData["title"] as? String,
                  let content = argData["content"] as? String else {
                continue
            }

            let argument = Argument(
                title: title,
                content: content,
                category: argData["category"] as? String
            )

            if let tags = argData["tags"] as? [String] {
                argument.tags = tags
            }
            if let jurisdiction = argData["jurisdiction"] as? String {
                argument.jurisdiction = jurisdiction
            }
            if let sources = argData["sources"] as? [String] {
                argument.sources = sources
            }
            if let notes = argData["notes"] as? String {
                argument.notes = notes
            }
            if let isFavorite = argData["isFavorite"] as? Bool {
                argument.isFavorite = isFavorite
            }

            modelContext.insert(argument)
            importCount += 1
        }

        try? modelContext.save()
        return importCount
    }

    // MARK: - Helpers

    private var timestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func writeToFile(
        data: Data,
        filename: String,
        format: ExportFormat,
        destination: URL?
    ) throws -> URL {
        let url: URL
        if let destination = destination {
            if destination.hasDirectoryPath {
                url = destination.appendingPathComponent("\(filename).\(format.fileExtension)")
            } else {
                url = destination
            }
        } else {
            let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first!
            url = documents.appendingPathComponent("\(filename).\(format.fileExtension)")
        }

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw ExportError.writeFailed(error)
        }
    }
}

// MARK: - Export View

import SwiftUI

struct DataExportView: View {
    @ObservedObject var exportService: DataExportService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: DataExportService.ExportFormat = .json
    @State private var isExporting = false
    @State private var exportResults: [DataExportService.ExportResult] = []
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Export Data")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Format Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Export Format")
                    .font(.headline)

                Picker("Format", selection: $selectedFormat) {
                    ForEach(DataExportService.ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Export Options
            VStack(alignment: .leading, spacing: 12) {
                Text("Data to Export")
                    .font(.headline)

                ExportOptionRow(
                    icon: "doc.text",
                    title: "Arguments",
                    description: "Your saved legal arguments and templates"
                )

                ExportOptionRow(
                    icon: "clock",
                    title: "Sessions",
                    description: "Writing session history and metrics"
                )

                ExportOptionRow(
                    icon: "folder",
                    title: "Matters",
                    description: "Legal matters and case information"
                )
            }

            Spacer()

            // Error Message
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Success Message
            if showSuccess {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)

                    Text("Export Complete!")
                        .font(.headline)

                    ForEach(exportResults, id: \.url) { result in
                        Text("\(result.itemCount) items → \(result.url.lastPathComponent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Export Button
            Button(action: performExport) {
                HStack {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(isExporting ? "Exporting..." : "Export All Data")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isExporting)
        }
        .padding(24)
        .frame(width: 400, height: 500)
    }

    private func performExport() {
        isExporting = true
        errorMessage = nil
        showSuccess = false

        Task {
            do {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.message = "Choose a location to save exported data"
                panel.prompt = "Export"

                let response = await panel.begin()

                if response == .OK, let url = panel.url {
                    let results = try exportService.exportAll(to: selectedFormat, directory: url)
                    exportResults = results
                    showSuccess = true
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isExporting = false
        }
    }
}

struct ExportOptionRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DataExportView(exportService: DataExportService())
}
