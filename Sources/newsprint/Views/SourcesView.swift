import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import newsprintCore

struct SourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.newsprintTheme) private var theme
    let sources: [Source]
    @ObservedObject var viewModel: SourcesViewModel
    let refresh: (Source) -> Void
    let sourceInserted: (Source) -> Void
    let sourceChanged: () -> Void
    let sourceContentChanged: () -> Void
    @State private var editingSource: Source?
    @State private var sourcesPendingDelete: [Source] = []

    var body: some View {
        SourcesPageShell(
            title: "Sources",
            caption: "Add feeds, manage active sources, and import or export your subscriptions.",
            headerActions: {
                HStack {
                    Button("Import OPML", systemImage: "square.and.arrow.down") {
                        viewModel.showingImporter = true
                    }
                    Button("Export OPML", systemImage: "square.and.arrow.up") {
                        viewModel.exportOPML(sources: sources)
                    }
                }
                .buttonStyle(.bordered)
            },
            builderContent: {
                builderContent
            },
            tableControls: {
                tableControls
            },
            tableContent: {
                tableContent
            }
        )
        .sheet(item: $editingSource) { source in
            SourceEditorSheet(
                source: source,
                updateTitle: { source, title in
                    viewModel.updateTitle(source, title: title, context: modelContext, onSourcesChanged: sourceChanged)
                },
                updateCategory: { source, category in
                    viewModel.updateCategory(source, category: category, context: modelContext, onSourcesChanged: sourceChanged)
                }
            )
        }
        .sheet(isPresented: importPreviewSheetBinding) {
            if let importPreview = viewModel.importPreview {
                OPMLPreviewSheet(
                    importPreview: importPreview,
                    importSources: {
                        viewModel.importSources(from: importPreview, context: modelContext, onSourcesChanged: sourceChanged)
                    },
                    cancel: {
                        viewModel.importPreview = nil
                    }
                )
            }
        }
        .fileImporter(isPresented: $viewModel.showingImporter, allowedContentTypes: [.opml, .xml]) { result in
            viewModel.importOPML(from: result)
        }
        .fileExporter(
            isPresented: $viewModel.showingExporter,
            document: viewModel.exportDocument,
            contentType: .opml,
            defaultFilename: "newsprint-sources.opml"
        ) { result in
            if case .failure(let error) = result {
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .onAppear {
            viewModel.configureSources(sources)
        }
        .onChange(of: sourceConfigurationToken) {
            viewModel.configureSourcesAfterExternalChange(sources)
        }
        .confirmationDialog(deleteConfirmationTitle, isPresented: sourceDeleteConfirmationBinding) {
            if !sourcesPendingDelete.isEmpty {
                Button(deleteConfirmationButtonTitle, role: .destructive) {
                    if viewModel.deleteSources(sourcesPendingDelete, context: modelContext, onSourcesChanged: sourceChanged) {
                        sourceContentChanged()
                    }
                    sourcesPendingDelete = []
                }
            }
        }
    }

    @ViewBuilder
    private var builderContent: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.callout)
                .foregroundStyle(.red)
        }

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                addSourceSurface
                hackerNewsSurface
            }

            VStack(alignment: .leading, spacing: 14) {
                addSourceSurface
                hackerNewsSurface
            }
        }

        youtubeSurface

        if !viewModel.discoveredFeeds.isEmpty {
            discoveredFeedsSection
        }

        if let importMessage = viewModel.importMessage {
            Text(importMessage)
                .font(.callout)
                .foregroundStyle(theme.metadata)
        }

        if let sourceMessage = viewModel.sourceMessage {
            Text(sourceMessage)
                .font(.callout)
                .foregroundStyle(theme.metadata)
        }
    }

    private var tableControls: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(viewModel.unifiedRows.count) sources and presets")
                .font(.callout)
                .foregroundStyle(theme.metadata)

            Spacer()

            selectedSourceActions
        }
    }

    @ViewBuilder
    private var selectedSourceActions: some View {
        let selectedRows = viewModel.selectedUnifiedRows
        let selectedAddRows = viewModel.selectedAddRows
        let selectedSources = viewModel.selectedSources(from: sources)

        if selectedRows.isEmpty {
            Button("Add Selected", systemImage: "plus.circle") {}
                .disabled(true)
            Button("Delete Selected", systemImage: "trash", role: .destructive) {}
                .disabled(true)
        } else {
            if !selectedAddRows.isEmpty {
                Button("Add Selected (\(selectedAddRows.count))", systemImage: "plus.circle") {
                    viewModel.addSelectedPresets(context: modelContext, onSourceInserted: sourceInserted)
                }
            }

            if selectedRows.count == 1, let source = selectedSource {
                Button("Edit", systemImage: "pencil") {
                    editingSource = source
                }
                Button(source.enabled ? "Pause" : "Enable", systemImage: source.enabled ? "pause.circle" : "checkmark.circle") {
                    viewModel.updateEnabled(source, enabled: !source.enabled, context: modelContext, onSourcesChanged: sourceChanged)
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    refresh(source)
                }
            }

            if !selectedSources.isEmpty {
                Button("Delete Selected (\(selectedSources.count))", systemImage: "trash", role: .destructive) {
                    sourcesPendingDelete = selectedSources
                }
            }
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        UnifiedSourcesTable(
            rows: viewModel.unifiedRows,
            selection: $viewModel.selectedUnifiedRowIDs,
            rowAction: handleUnifiedRowAction
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedSource: Source? {
        viewModel.selectedSource(from: sources)
    }

    private var importPreviewSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.importPreview != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.importPreview = nil
                }
            }
        )
    }

    private var sourceDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { !sourcesPendingDelete.isEmpty },
            set: { isPresented in
                if !isPresented {
                    sourcesPendingDelete = []
                }
            }
        )
    }

    private var deleteConfirmationTitle: String {
        if sourcesPendingDelete.count == 1 {
            return "Delete this source and its articles?"
        }
        return "Delete \(sourcesPendingDelete.count) sources and their articles?"
    }

    private var deleteConfirmationButtonTitle: String {
        sourcesPendingDelete.count == 1 ? "Delete Source" : "Delete \(sourcesPendingDelete.count) Sources"
    }

    private func handleUnifiedRowAction(_ row: SourcesUnifiedRowDisplayItem) {
        switch row.action {
        case .add:
            viewModel.addPreset(row, context: modelContext, onSourceInserted: sourceInserted)
        case .remove:
            guard let sourceID = row.sourceID,
                  let source = sources.first(where: { $0.id == sourceID }) else {
                return
            }
            sourcesPendingDelete = [source]
        }
    }

    private var sourceConfigurationToken: [SourceConfigurationToken] {
        sources.map(SourceConfigurationToken.init(source:))
    }

    private struct SourceConfigurationToken: Hashable {
        let id: UUID
        let title: String
        let url: URL
        let kindRawValue: String
        let enabled: Bool
        let category: String?
        let lastSuccessfulFetchAt: Date?
        let lastErrorMessage: String?

        init(source: Source) {
            id = source.id
            title = source.title
            url = source.url
            kindRawValue = source.kindRawValue
            enabled = source.enabled
            category = source.category
            lastSuccessfulFetchAt = source.lastSuccessfulFetchAt
            lastErrorMessage = source.lastErrorMessage
        }
    }

    private var addSourceSurface: some View {
        AdminSurface {
            VStack(alignment: .leading, spacing: 14) {
                AdminSectionHeader("Add Source", caption: "Paste a feed or website URL.")

                TextField("Title", text: $viewModel.title)
                    .textFieldStyle(.roundedBorder)
                TextField("Feed or Website URL", text: $viewModel.urlString)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Picker("Kind", selection: $viewModel.kind) {
                        ForEach(SourceKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Button(viewModel.isDiscovering ? "Checking..." : "Add Source", systemImage: "plus") {
                        Task {
                            await viewModel.addSource(context: modelContext, onSourcesChanged: sourceChanged)
                        }
                    }
                    .disabled(viewModel.isDiscovering)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var hackerNewsSurface: some View {
        AdminSurface {
            VStack(alignment: .leading, spacing: 14) {
                AdminSectionHeader("Hacker News", caption: "Build an official Hacker News feed.")

                Picker("Feed", selection: $viewModel.hackerNewsKind) {
                    ForEach(HackerNewsFeedKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        hackerNewsNumberField("Min points", text: $viewModel.hackerNewsMinimumPoints)
                        hackerNewsNumberField("Min comments", text: $viewModel.hackerNewsMinimumComments)
                        hackerNewsNumberField("Count", text: $viewModel.hackerNewsCount)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        hackerNewsNumberField("Min points", text: $viewModel.hackerNewsMinimumPoints)
                        hackerNewsNumberField("Min comments", text: $viewModel.hackerNewsMinimumComments)
                        hackerNewsNumberField("Count", text: $viewModel.hackerNewsCount)
                    }
                }

                if let previewURL = viewModel.hackerNewsPreviewURL {
                    Text(previewURL.absoluteString)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.metadata)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Button("Add Hacker News Feed", systemImage: "plus.circle") {
                    viewModel.addHackerNewsFeed(context: modelContext, onSourcesChanged: sourceChanged)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func hackerNewsNumberField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 92)
    }

    private var youtubeSurface: some View {
        AdminSurface {
            VStack(alignment: .leading, spacing: 14) {
                AdminSectionHeader("YouTube", caption: "Use a channel ID or feed URL.")

                TextField("Channel ID or feed URL", text: $viewModel.youtubeChannel)
                    .textFieldStyle(.roundedBorder)

                Button("Add YouTube Feed", systemImage: "play.rectangle") {
                    viewModel.addYouTubeFeed(context: modelContext, onSourcesChanged: sourceChanged)
                }
                .disabled(viewModel.youtubeChannel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var discoveredFeedsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            AdminSectionHeader("Discovered Feeds")
            LazyVStack(spacing: 10) {
                ForEach(viewModel.discoveredFeeds) { feed in
                    AdminSurface {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(feed.title ?? feed.url.host() ?? feed.url.absoluteString)
                                    .font(.headline)
                                Text(feed.url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(theme.metadata)
                                    .textSelection(.enabled)
                            }

                            Spacer()

                            PillTag(title: feed.type.displayName)

                            Button("Add", systemImage: "plus.circle") {
                                viewModel.addDiscoveredFeed(feed, context: modelContext, onSourcesChanged: sourceChanged)
                            }
                        }
                    }
                }
            }
        }
    }

    private func opmlPreviewSection(_ importPreview: OPMLImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AdminSectionHeader("OPML Preview", caption: "\(importPreview.sources.count) sources ready to import")
                Spacer()
                Button("Import \(importPreview.sources.count) Sources", systemImage: "tray.and.arrow.down") {
                    viewModel.importSources(from: importPreview, context: modelContext, onSourcesChanged: sourceChanged)
                }
                .buttonStyle(.borderedProminent)
            }

            LazyVStack(spacing: 10) {
                ForEach(importPreview.sources, id: \.feedURL) { source in
                    AdminSurface {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(source.title)
                                    .font(.headline)
                                Text(source.feedURL.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(theme.metadata)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            if let category = source.category {
                                PillTag(title: category)
                            }
                        }
                    }
                }
            }
        }
    }

}

struct SourcesPageShell<HeaderActions: View, BuilderContent: View, TableControls: View, TableContent: View>: View {
    @Environment(\.newsprintTheme) private var theme
    let title: String
    let caption: String
    @ViewBuilder let headerActions: HeaderActions
    @ViewBuilder let builderContent: BuilderContent
    @ViewBuilder let tableControls: TableControls
    @ViewBuilder let tableContent: TableContent

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                AdminSectionHeader(title, caption: caption)
                Spacer()
                headerActions
            }

            VStack(alignment: .leading, spacing: 14) {
                builderContent
            }
            .frame(maxWidth: 1120, alignment: .leading)

            Divider()

            tableControls
                .frame(maxWidth: 1120, alignment: .leading)

            tableContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.paneBackground)
        .navigationTitle(title)
    }
}

struct UnifiedSourcesTable: View {
    @Environment(\.newsprintTheme) private var theme
    let rows: [SourcesUnifiedRowDisplayItem]
    @Binding var selection: Set<String>
    let rowAction: (SourcesUnifiedRowDisplayItem) -> Void

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("Feed") { row in
                Image(systemName: row.iconName)
                    .foregroundStyle(theme.tint)
                    .help(row.preset == nil ? "Custom source" : "Preset source")
            }
            .width(48)

            TableColumn("Name") { row in
                Text(row.title)
                    .lineLimit(1)
            }

            TableColumn("Tags") { row in
                Text(row.tags.joined(separator: " · "))
                    .foregroundStyle(theme.metadata)
                    .lineLimit(1)
            }

            TableColumn("Status") { row in
                HStack(spacing: 6) {
                    Image(systemName: statusIconName(for: row))
                    Text(statusText(for: row))
                }
                .foregroundStyle(statusColor(for: row))
                .lineLimit(1)
                .help(row.lastErrorText ?? statusText(for: row))
            }
            .width(150)

            TableColumn("Action") { row in
                Button {
                    rowAction(row)
                } label: {
                    Image(systemName: row.action == .add ? "plus.circle" : "trash")
                        .font(.body.weight(.semibold))
                        .frame(width: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(row.action == .add ? theme.tint : .red)
                .help(row.action == .add ? "Add source" : "Remove source")
            }
            .width(72)
        }
        .alternatingRowBackgrounds(.enabled)
        .scrollContentBackground(.hidden)
        .background(theme.readerSurface.opacity(0.36), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.20))
        }
    }

    private func statusText(for row: SourcesUnifiedRowDisplayItem) -> String {
        switch row.action {
        case .add:
            "Available"
        case .remove:
            row.healthText
        }
    }

    private func statusIconName(for row: SourcesUnifiedRowDisplayItem) -> String {
        switch row.action {
        case .add:
            "plus.circle"
        case .remove:
            row.health == .healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(for row: SourcesUnifiedRowDisplayItem) -> Color {
        switch row.action {
        case .add:
            theme.metadata
        case .remove:
            row.health == .healthy ? theme.metadata : .red
        }
    }
}

struct OPMLPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.newsprintTheme) private var theme
    let importPreview: OPMLImportPreview
    let importSources: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                AdminSectionHeader("OPML Preview", caption: "\(importPreview.sources.count) sources ready to import")
                Spacer()
                Button("Cancel") {
                    cancel()
                    dismiss()
                }
                Button("Import \(importPreview.sources.count)", systemImage: "tray.and.arrow.down") {
                    importSources()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Table(rows) {
                TableColumn("Name") { row in
                    Text(row.source.title)
                        .lineLimit(1)
                }
                TableColumn("Feed URL") { row in
                    Text(row.source.feedURL.absoluteString)
                        .foregroundStyle(theme.metadata)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                TableColumn("Category") { row in
                    Text(row.source.category ?? "")
                        .foregroundStyle(theme.metadata)
                        .lineLimit(1)
                }
            }
            .alternatingRowBackgrounds(.enabled)
            .frame(minHeight: 360)
        }
        .padding(24)
        .frame(minWidth: 780, minHeight: 500)
    }

    private var rows: [OPMLPreviewRow] {
        importPreview.sources.map(OPMLPreviewRow.init(source:))
    }

    private struct OPMLPreviewRow: Identifiable {
        let source: OPMLImportedSource

        var id: URL {
            source.feedURL
        }
    }
}

private extension DiscoveredFeedType {
    var displayName: String {
        switch self {
        case .rss: "RSS"
        case .atom: "Atom"
        case .jsonFeed: "JSON Feed"
        }
    }
}

struct SourceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let source: Source
    let updateTitle: (Source, String) -> Void
    let updateCategory: (Source, String) -> Void
    @State private var draftTitle = ""
    @State private var draftCategory = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AdminSectionHeader("Edit Source", caption: source.url.absoluteString)

            TextField("Title", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
            TextField("Category", text: $draftCategory)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save", systemImage: "checkmark.circle") {
                    saveDrafts()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasDraftChanges)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            draftTitle = source.title
            draftCategory = source.category ?? ""
        }
    }

    private var hasDraftChanges: Bool {
        draftTitle != source.title || draftCategory != (source.category ?? "")
    }

    private func saveDrafts() {
        if draftTitle != source.title {
            updateTitle(source, draftTitle)
        }
        if draftCategory != (source.category ?? "") {
            updateCategory(source, draftCategory)
        }
    }
}
