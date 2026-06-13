import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import newsprintCore

struct SourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.newsprintTheme) private var theme
    let sources: [Source]
    let refresh: (Source) -> Void
    let sourceChanged: () -> Void
    @StateObject private var viewModel = SourcesViewModel()
    @State private var expandedSourceID: UUID?

    var body: some View {
        AdminPageShell("Sources") {
            HStack(alignment: .top) {
                AdminSectionHeader("Sources", caption: "Add feeds, manage active sources, and import or export your subscriptions.")
                Spacer()
                HStack {
                    Button("Import OPML", systemImage: "square.and.arrow.down") {
                        viewModel.showingImporter = true
                    }
                    Button("Export OPML", systemImage: "square.and.arrow.up") {
                        viewModel.exportOPML(sources: sources)
                    }
                }
                .buttonStyle(.bordered)
            }

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

            if let importPreview = viewModel.importPreview, !importPreview.sources.isEmpty {
                opmlPreviewSection(importPreview)
            }

            if let importMessage = viewModel.importMessage {
                Text(importMessage)
                    .font(.callout)
                    .foregroundStyle(theme.metadata)
            }

            VStack(alignment: .leading, spacing: 14) {
                AdminSectionHeader("Presets", caption: "Lightweight starting points for common feeds.")
                presetList

                if let sourceMessage = viewModel.sourceMessage {
                    Text(sourceMessage)
                        .font(.callout)
                        .foregroundStyle(theme.metadata)
                }
            }

            if !sources.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    AdminSectionHeader("Added Sources", caption: "\(sources.count) active records")
                    LazyVStack(spacing: 10) {
                        ForEach(sources) { source in
                            SourceRow(
                                source: source,
                                isExpanded: expandedSourceID == source.id,
                                toggleExpanded: {
                                    expandedSourceID = expandedSourceID == source.id ? nil : source.id
                                },
                                refresh: refresh,
                                updateTitle: { source, title in
                                    viewModel.updateTitle(source, title: title, context: modelContext, onSourcesChanged: sourceChanged)
                                },
                                updateCategory: { source, category in
                                    viewModel.updateCategory(source, category: category, context: modelContext, onSourcesChanged: sourceChanged)
                                },
                                updateEnabled: { source, enabled in
                                    viewModel.updateEnabled(source, enabled: enabled, context: modelContext, onSourcesChanged: sourceChanged)
                                },
                                deleteSource: { source in
                                    viewModel.deleteSource(source, context: modelContext, onSourcesChanged: sourceChanged)
                                    if expandedSourceID == source.id {
                                        expandedSourceID = nil
                                    }
                                }
                            )
                        }
                    }
                }
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
    }

    private var presetList: some View {
        AdminSurface {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Text("Feed")
                        .frame(width: 28, alignment: .leading)
                    Text("Name")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Tags")
                        .frame(width: 360, alignment: .leading)
                    Text("Added")
                        .frame(width: 72, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.metadata)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                List(PresetSourceCatalog.all) { preset in
                    PresetListRow(
                        preset: preset,
                        isAdded: isPresetAdded(preset)
                    ) {
                        viewModel.addPreset(preset, context: modelContext, onSourcesChanged: sourceChanged)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: min(CGFloat(PresetSourceCatalog.all.count) * 46, 520))
            }
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

    private func isPresetAdded(_ preset: PresetSource) -> Bool {
        let canonicalPreset = URLCanonicalizer.canonicalize(preset.url).absoluteString
        return sources.contains {
            URLCanonicalizer.canonicalize($0.url).absoluteString == canonicalPreset
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
    let preset: PresetSource
    let isAdded: Bool
    let add: () -> Void

    var body: some View {
        Button {
            if !isAdded {
                add()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.tint)
                    .frame(width: 28, alignment: .leading)

                Text(preset.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    ForEach(displayTags, id: \.self) { tag in
                        PillTag(title: tag)
                    }
                }
                .frame(width: 360, alignment: .leading)

                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isAdded ? theme.tint : theme.metadata)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
    }

    private var iconName: String {
        switch preset.kind {
        case .hackerNews:
            "text.bubble"
        case .youtube:
            "play.rectangle"
        case .rss, .atom, .jsonFeed, .blog:
            "dot.radiowaves.left.and.right"
        }
    }

    private var displayTags: [String] {
        var tags: [String] = []
        for tag in [preset.category, preset.kind.displayName] {
            guard !tags.contains(tag) else {
                continue
            }
            tags.append(tag)
        }
        return tags
    }

    private var rowBackground: Color {
        isAdded ? theme.tint.opacity(0.10) : Color.clear
    }
}

private struct SourceRow: View {
    @Environment(\.newsprintTheme) private var theme
    let source: Source
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let refresh: (Source) -> Void
    let updateTitle: (Source, String) -> Void
    let updateCategory: (Source, String) -> Void
    let updateEnabled: (Source, Bool) -> Void
    let deleteSource: (Source) -> Void
    @State private var isConfirmingDelete = false
    @State private var draftTitle = ""
    @State private var draftCategory = ""

    var body: some View {
        AdminSurface {
            VStack(alignment: .leading, spacing: 12) {
                collapsedRow

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        sourceMetadata
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        sourceMetadata
                    }
                }

                if isExpanded {
                    Divider()
                    editor
                }

                if let error = source.lastErrorMessage {
                    Text("Last error: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .onAppear(perform: syncDrafts)
        .onChange(of: isExpanded) {
            if isExpanded {
                syncDrafts()
            }
        }
        .confirmationDialog("Delete this source and its articles?", isPresented: $isConfirmingDelete) {
            Button("Delete Source", role: .destructive) {
                deleteSource(source)
            }
        }
    }

    private var collapsedRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: toggleExpanded) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: source.kind == .hackerNews ? "text.bubble" : "dot.radiowaves.left.and.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.tint)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(source.url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(theme.metadata)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(source.enabled ? "Enabled" : "Paused", systemImage: source.enabled ? "checkmark.circle.fill" : "pause.circle") {
                updateEnabled(source, !source.enabled)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(source.enabled ? theme.tint : theme.metadata)

            Button(isExpanded ? "Done" : "Edit", systemImage: isExpanded ? "checkmark" : "pencil") {
                toggleExpanded()
            }
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
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
            TextField("Category", text: $draftCategory)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Save Changes", systemImage: "checkmark.circle") {
                    saveDrafts()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasDraftChanges)
            }
        }
    }

    private var sourceMetadata: some View {
        Group {
            PillTag(title: source.kind.displayName)
            if let category = source.category, !category.isEmpty {
                PillTag(title: category)
            }
            Text("Last fetch: \(source.lastFetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")")
            Text("Last success: \(source.lastSuccessfulFetchAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")")
        }
        .font(.caption)
        .foregroundStyle(theme.metadata)
    }

    private var hasDraftChanges: Bool {
        draftTitle != source.title || draftCategory != (source.category ?? "")
    }

    private func syncDrafts() {
        draftTitle = source.title
        draftCategory = source.category ?? ""
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
