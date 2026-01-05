import SwiftUI

/// Main view for the argument library
struct ArgumentLibraryView: View {
    @ObservedObject var library: ArgumentLibrary
    var onInsert: ((Argument) -> Void)?

    @State private var selectedArgument: Argument?
    @State private var showingNewArgumentSheet = false
    @State private var showingExportSheet = false

    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            if let argument = selectedArgument {
                ArgumentDetailView(
                    argument: argument,
                    library: library,
                    onInsert: onInsert
                )
            } else {
                emptyDetailView
            }
        }
        .navigationTitle("Argument Library")
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showingNewArgumentSheet) {
            NewArgumentSheet(library: library)
        }
        .onAppear {
            library.loadArguments()
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        List(selection: $selectedArgument) {
            // Search field
            SearchField(text: $library.searchQuery)
                .padding(.vertical, 4)

            // Favorites section
            if !library.favorites.isEmpty && library.searchQuery.isEmpty {
                Section("Favorites") {
                    ForEach(library.favorites) { argument in
                        ArgumentRowView(argument: argument)
                            .tag(argument)
                    }
                }
            }

            // Recently used section
            if !library.recentlyUsed.isEmpty && library.searchQuery.isEmpty {
                Section("Recently Used") {
                    ForEach(library.recentlyUsed) { argument in
                        ArgumentRowView(argument: argument)
                            .tag(argument)
                    }
                }
            }

            // Categories
            ForEach(Array(library.argumentsByCategory.keys.sorted()), id: \.self) { category in
                Section(category) {
                    ForEach(library.argumentsByCategory[category] ?? []) { argument in
                        ArgumentRowView(argument: argument)
                            .tag(argument)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Empty State

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)

            Text("Select an Argument")
                .font(.title2)

            Text("Choose an argument from the sidebar to view its details")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if library.arguments.isEmpty {
                Divider()
                    .padding(.vertical)

                Text("Your library is empty")
                    .font(.headline)

                Text("Save arguments from your drafts or create new ones to build your library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Create New Argument") {
                    showingNewArgumentSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showingNewArgumentSheet = true }) {
                Label("New Argument", systemImage: "plus")
            }
        }

        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button("Export as JSON") {
                    exportJSON()
                }
                Button("Export as CSV") {
                    exportCSV()
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }

        ToolbarItem(placement: .secondaryAction) {
            if let category = library.selectedCategory {
                Button(action: { library.selectedCategory = nil }) {
                    Label("Clear filter: \(category.displayName)", systemImage: "xmark.circle")
                }
            }
        }
    }

    // MARK: - Export

    private func exportJSON() {
        guard let data = library.exportToJSON(),
              let string = String(data: data, encoding: .utf8) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func exportCSV() {
        let csv = library.exportToCSV()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(csv, forType: .string)
    }
}

// MARK: - Search Field

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search arguments...", text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Argument Row

struct ArgumentRowView: View {
    let argument: Argument

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(argument.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if argument.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            if let summary = argument.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 4) {
                if let category = argument.argumentCategory {
                    Text(category.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }

                if argument.usageCount > 0 {
                    Text("\(argument.usageCount) uses")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Argument Detail View

struct ArgumentDetailView: View {
    let argument: Argument
    @ObservedObject var library: ArgumentLibrary
    var onInsert: ((Argument) -> Void)?

    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerView

                Divider()

                // Content
                contentView

                // Citations
                if argument.hasCitations {
                    citationsView
                }

                // Tags
                if !argument.tags.isEmpty {
                    tagsView
                }

                // Metadata
                metadataView
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { onInsert?(argument) }) {
                    Label("Insert", systemImage: "text.insert")
                }
                .disabled(onInsert == nil)
            }

            ToolbarItem {
                Button(action: { library.toggleFavorite(argument) }) {
                    Label(
                        argument.isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: argument.isFavorite ? "star.fill" : "star"
                    )
                }
            }

            ToolbarItem {
                Button(action: copyToClipboard) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(argument.title)
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                if argument.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }

            HStack(spacing: 12) {
                if let category = argument.argumentCategory {
                    Label(category.displayName, systemImage: "folder")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let jurisdiction = argument.jurisdiction {
                    Label(jurisdiction, systemImage: "building.columns")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Label("\(argument.usageCount) uses", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Argument")
                .font(.headline)

            Text(argument.content)
                .font(.body)
                .textSelection(.enabled)
                .padding()
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if let summary = argument.summary {
                Text("Summary")
                    .font(.headline)
                    .padding(.top)

                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var citationsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Citations")
                .font(.headline)

            if !argument.supportingCitations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Supporting")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(argument.supportingCitations, id: \.self) { citation in
                        Text("• \(citation)")
                            .font(.caption)
                    }
                }
            }

            if !argument.keyPrecedents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Key Precedents")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(argument.keyPrecedents, id: \.self) { precedent in
                        Text("• \(precedent)")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var tagsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(argument.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var metadataView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Created")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(argument.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                }

                if let lastUsed = argument.lastUsedAt {
                    VStack(alignment: .leading) {
                        Text("Last Used")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(lastUsed.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                    }
                }

                VStack(alignment: .leading) {
                    Text("Source")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(argument.source.displayName)
                        .font(.caption)
                }
            }
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(argument.content, forType: .string)
    }
}

// MARK: - New Argument Sheet

struct NewArgumentSheet: View {
    @ObservedObject var library: ArgumentLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var content = ""
    @State private var summary = ""
    @State private var selectedCategory: Argument.ArgumentCategory?
    @State private var tags = ""
    @State private var jurisdiction = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Title", text: $title)
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                    TextField("Summary (optional)", text: $summary)
                }

                Section("Classification") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("None").tag(nil as Argument.ArgumentCategory?)
                        ForEach(Argument.ArgumentCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category as Argument.ArgumentCategory?)
                        }
                    }

                    TextField("Jurisdiction", text: $jurisdiction)
                    TextField("Tags (comma separated)", text: $tags)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Argument")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveArgument() }
                        .disabled(title.isEmpty || content.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 500)
    }

    private func saveArgument() {
        let tagArray = tags.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        library.createArgument(
            title: title,
            content: content,
            summary: summary.isEmpty ? nil : summary,
            category: selectedCategory,
            tags: tagArray,
            jurisdiction: jurisdiction.isEmpty ? nil : jurisdiction
        )

        dismiss()
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)

        for (index, frame) in result.frames.enumerated() {
            let position = CGPoint(x: bounds.minX + frame.origin.x, y: bounds.minY + frame.origin.y)
            subviews[index].place(at: position, proposal: ProposedViewSize(frame.size))
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// MARK: - Preview

#Preview {
    ArgumentLibraryView(library: ArgumentLibrary())
}
