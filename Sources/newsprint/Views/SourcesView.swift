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
    @State private var sourcePendingDelete: Source?
    @State private var renderedTableSections = Set<SourcesPageSection>()
    @State private var didScheduleTablePrewarm = false

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
            prewarmTables()
        }
        .onChange(of: sourceConfigurationToken) {
            viewModel.configureSourcesAfterExternalChange(sources)
        }
        .onChange(of: viewModel.selectedSection) {
            renderedTableSections.insert(viewModel.selectedSection)
        }
        .confirmationDialog("Delete this source and its articles?", isPresented: sourceDeleteConfirmationBinding) {
            if let source = sourcePendingDelete {
                Button("Delete Source", role: .destructive) {
                    if viewModel.deleteSource(source, context: modelContext, onSourcesChanged: sourceChanged) {
                        sourceContentChanged()
                    }
                    sourcePendingDelete = nil
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
            Picker("Section", selection: $viewModel.selectedSection) {
                ForEach(SourcesPageSection.allCases, id: \.self) { section in
                    Text(section.displayName).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Text(selectedSectionCaption)
                .font(.callout)
                .foregroundStyle(theme.metadata)

            Spacer()

            switch viewModel.selectedSection {
            case .presets:
                if let preset = viewModel.selectedPresetRow {
                    Button(preset.isAdded ? "Added" : "Add Preset", systemImage: preset.isAdded ? "checkmark.circle.fill" : "plus.circle") {
                        addPreset(preset)
                    }
                    .disabled(preset.isAdded)
                    .buttonStyle(.borderedProminent)
                }
            case .addedSources:
                selectedSourceActions
            }
        }
    }

    @ViewBuilder
    private var selectedSourceActions: some View {
        if let source = selectedSource {
            Button("Edit", systemImage: "pencil") {
                editingSource = source
            }
            Button(source.enabled ? "Pause" : "Enable", systemImage: source.enabled ? "pause.circle" : "checkmark.circle") {
                viewModel.updateEnabled(source, enabled: !source.enabled, context: modelContext, onSourcesChanged: sourceChanged)
            }
            Button("Refresh", systemImage: "arrow.clockwise") {
                refresh(source)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                sourcePendingDelete = source
            }
        } else {
            Button("Edit", systemImage: "pencil") {}
                .disabled(true)
            Button("Refresh", systemImage: "arrow.clockwise") {}
                .disabled(true)
        }
    }

    private var selectedSectionCaption: String {
        switch viewModel.selectedSection {
        case .presets:
            "\(viewModel.presetRows.count) presets"
        case .addedSources:
            "\(viewModel.sourceRows.count) active records"
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        let sections = renderedTableSections.union([viewModel.selectedSection])
        ZStack {
            if sections.contains(.presets) {
                PresetsTable(
                    rows: viewModel.presetRows,
                    selection: $viewModel.selectedPresetID,
                    addPreset: addPreset
                )
                .opacity(viewModel.selectedSection == .presets ? 1 : 0)
                .allowsHitTesting(viewModel.selectedSection == .presets)
            }

            if sections.contains(.addedSources) {
                AddedSourcesTable(
                    rows: viewModel.sourceRows,
                    selection: $viewModel.selectedSourceID,
                    selectedSource: { id in
                        sources.first { $0.id == id }
                    },
                    refresh: refresh,
                    edit: { source in
                        editingSource = source
                    },
                    updateEnabled: { source, enabled in
                        viewModel.updateEnabled(source, enabled: enabled, context: modelContext, onSourcesChanged: sourceChanged)
                    },
                    deleteSource: { source in
                        sourcePendingDelete = source
                    }
                )
                .opacity(viewModel.selectedSection == .addedSources ? 1 : 0)
                .allowsHitTesting(viewModel.selectedSection == .addedSources)
            }
        }
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
            get: { sourcePendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    sourcePendingDelete = nil
                }
            }
        )
    }

    private func addPreset(_ row: PresetRowDisplayItem) {
        viewModel.addPreset(row, context: modelContext, onSourceInserted: sourceInserted)
    }

    private func prewarmTables() {
        renderedTableSections.insert(viewModel.selectedSection)
        guard !didScheduleTablePrewarm else {
            return
        }
        didScheduleTablePrewarm = true
        Task { @MainActor in
            await Task.yield()
            renderedTableSections = Set(SourcesPageSection.allCases)
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
                AdminSectionHeader("Hacker News", caption: "Build a tuned HNRSS feed.")

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

                TextField("Search query", text: $viewModel.hackerNewsSearchQuery)
                    .textFieldStyle(.roundedBorder)

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

struct PresetsTable: View {
    @Environment(\.newsprintTheme) private var theme
    let rows: [PresetRowDisplayItem]
    @Binding var selection: String?
    let addPreset: (PresetRowDisplayItem) -> Void

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("Feed") { row in
                Image(systemName: row.iconName)
                    .foregroundStyle(theme.tint)
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
                Button {
                    if !row.isAdded {
                        addPreset(row)
                    }
                } label: {
                    Label(row.isAdded ? "Added" : "Add", systemImage: row.isAdded ? "checkmark.circle.fill" : "plus.circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(row.isAdded ? theme.metadata : theme.tint)
                .disabled(row.isAdded)
            }
            .width(96)
        }
        .alternatingRowBackgrounds(.enabled)
        .scrollContentBackground(.hidden)
        .background(theme.readerSurface.opacity(0.36), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.20))
        }
    }
}

struct AddedSourcesTable: View {
    @Environment(\.newsprintTheme) private var theme
    let rows: [SourceRowDisplayItem]
    @Binding var selection: UUID?
    let selectedSource: (UUID) -> Source?
    let refresh: (Source) -> Void
    let edit: (Source) -> Void
    let updateEnabled: (Source, Bool) -> Void
    let deleteSource: (Source) -> Void

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("Enabled") { row in
                Image(systemName: row.enabled ? "checkmark.circle.fill" : "pause.circle")
                    .foregroundStyle(row.enabled ? theme.tint : theme.metadata)
                    .help(row.enabled ? "Enabled" : "Paused")
            }
            .width(72)

            TableColumn("Name") { row in
                Label(row.title, systemImage: row.iconName)
                    .lineLimit(1)
            }

            TableColumn("Kind") { row in
                Text(sourceKindText(row))
                    .foregroundStyle(theme.metadata)
                    .lineLimit(1)
            }

            TableColumn("Last Success") { row in
                Text(row.successText.replacingOccurrences(of: "Success: ", with: ""))
                    .foregroundStyle(theme.metadata)
                    .lineLimit(1)
            }

            TableColumn("Error") { row in
                Text(row.errorMessage == nil ? "OK" : "Error")
                    .foregroundStyle(row.errorMessage == nil ? theme.metadata : .red)
                    .help(row.errorMessage ?? "No recent error")
            }
        }
        .alternatingRowBackgrounds(.enabled)
        .scrollContentBackground(.hidden)
        .background(theme.readerSurface.opacity(0.36), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.20))
        }
        .contextMenu(forSelectionType: UUID.self) { selectedIDs in
            if let id = selectedIDs.first, let source = selectedSource(id) {
                Button("Edit", systemImage: "pencil") {
                    edit(source)
                }
                Button(source.enabled ? "Pause" : "Enable", systemImage: source.enabled ? "pause.circle" : "checkmark.circle") {
                    updateEnabled(source, !source.enabled)
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    refresh(source)
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    deleteSource(source)
                }
            }
        }
    }

    private func sourceKindText(_ row: SourceRowDisplayItem) -> String {
        if let category = row.category {
            "\(row.kindTitle) · \(category)"
        } else {
            row.kindTitle
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

struct PresetListRow: View {
    @Environment(\.newsprintTheme) private var theme
    let row: PresetRowDisplayItem
    let add: () -> Void

    var body: some View {
        Button {
            if !row.isAdded {
                add()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: row.iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.tint)
                    .frame(width: 28, alignment: .leading)

                Text(row.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    ForEach(row.tags, id: \.self) { tag in
                        PillTag(title: tag)
                    }
                }
                .frame(width: 360, alignment: .leading)

                Image(systemName: row.isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(row.isAdded ? theme.tint : theme.metadata)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(row.isAdded)
    }

    private var rowBackground: Color {
        row.isAdded ? theme.tint.opacity(0.10) : Color.clear
    }
}

private struct SourceListRow: View {
    @Environment(\.newsprintTheme) private var theme
    let source: Source
    let displayItem: SourceRowDisplayItem
    let refresh: (Source) -> Void
    let edit: () -> Void
    let updateEnabled: (Source, Bool) -> Void
    let deleteSource: (Source) -> Void
    @State private var isConfirmingDelete = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: displayItem.iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(displayItem.title)
                        .font(.headline)
                        .lineLimit(1)
                    PillTag(title: displayItem.kindTitle)
                    if let category = displayItem.category {
                        PillTag(title: category)
                    }
                }

                HStack(spacing: 10) {
                    Text(displayItem.urlString)
                        .lineLimit(1)
                    Text(displayItem.successText)
                        .lineLimit(1)
                    if let error = displayItem.errorMessage {
                        Text("Error")
                            .foregroundStyle(.red)
                            .help(error)
                    }
                }
                .font(.caption)
                .foregroundStyle(theme.metadata)
            }

            Spacer(minLength: 12)

            Button(displayItem.enabled ? "Enabled" : "Paused", systemImage: displayItem.enabled ? "checkmark.circle.fill" : "pause.circle") {
                updateEnabled(source, !source.enabled)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(displayItem.enabled ? theme.tint : theme.metadata)

            Button("Edit", systemImage: "pencil", action: edit)
                .buttonStyle(.borderless)

            Button("Refresh", systemImage: "arrow.clockwise") {
                refresh(source)
            }
            .buttonStyle(.borderless)

            Button("Delete", systemImage: "trash", role: .destructive) {
                isConfirmingDelete = true
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .confirmationDialog("Delete this source and its articles?", isPresented: $isConfirmingDelete) {
            Button("Delete Source", role: .destructive) {
                deleteSource(source)
            }
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
