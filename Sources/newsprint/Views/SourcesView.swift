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

    private var presetColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 12)]
    }

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
                    youtubeSurface
                }

                VStack(alignment: .leading, spacing: 14) {
                    addSourceSurface
                    youtubeSurface
                }
            }

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

            if !sources.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    AdminSectionHeader("Added Sources", caption: "\(sources.count) active records")
                    LazyVStack(spacing: 12) {
                        ForEach(sources) { source in
                            SourceRow(
                                source: source,
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
                                }
                            )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                AdminSectionHeader("Presets", caption: "Lightweight starting points for common feeds.")
                LazyVGrid(columns: presetColumns, alignment: .leading, spacing: 12) {
                    ForEach(PresetSourceCatalog.all) { preset in
                        PresetGridCard(
                            preset: preset,
                            isAdded: isPresetAdded(preset)
                        ) {
                            viewModel.addPreset(preset, context: modelContext, onSourcesChanged: sourceChanged)
                        }
                    }
                }

                if let sourceMessage = viewModel.sourceMessage {
                    Text(sourceMessage)
                        .font(.callout)
                        .foregroundStyle(theme.metadata)
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

struct PresetGridCard: View {
    @Environment(\.newsprintTheme) private var theme
    let preset: PresetSource
    let isAdded: Bool
    let add: () -> Void

    var body: some View {
        AdminSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: iconName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.tint)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(preset.title)
                            .font(.headline)
                            .lineLimit(2)
                        HStack {
                            PillTag(title: preset.category)
                            PillTag(title: preset.kind.displayName)
                        }
                    }

                    Spacer()
                }

                if isAdded {
                    Button("Added", systemImage: "checkmark.circle") {}
                        .disabled(true)
                        .buttonStyle(.bordered)
                } else {
                    Button("Add", systemImage: "plus.circle") {
                        add()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .opacity(isAdded ? 0.62 : 1)
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
}

private struct SourceRow: View {
    @Environment(\.newsprintTheme) private var theme
    let source: Source
    let refresh: (Source) -> Void
    let updateTitle: (Source, String) -> Void
    let updateCategory: (Source, String) -> Void
    let updateEnabled: (Source, Bool) -> Void
    let deleteSource: (Source) -> Void
    @State private var isConfirmingDelete = false

    var body: some View {
        AdminSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Title", text: Binding(
                            get: { source.title },
                            set: { value in updateTitle(source, value) }
                        ))
                        .font(.headline)
                        .textFieldStyle(.plain)

                        Text(source.url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(theme.metadata)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Toggle("Enabled", isOn: Binding(
                        get: { source.enabled },
                        set: { value in updateEnabled(source, value) }
                    ))
                    .labelsHidden()

                    Button("Refresh", systemImage: "arrow.clockwise") {
                        refresh(source)
                    }
                    .buttonStyle(.borderless)

                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .buttonStyle(.borderless)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        sourceMetadata
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        sourceMetadata
                    }
                }

                if let error = source.lastErrorMessage {
                    Text("Last error: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog("Delete this source and its articles?", isPresented: $isConfirmingDelete) {
            Button("Delete Source", role: .destructive) {
                deleteSource(source)
            }
        }
    }

    private var sourceMetadata: some View {
        Group {
            PillTag(title: source.kind.displayName)
            TextField("Category", text: Binding(
                get: { source.category ?? "" },
                set: { value in updateCategory(source, value) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 190)
            Text("Last fetch: \(source.lastFetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")")
            Text("Last success: \(source.lastSuccessfulFetchAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")")
        }
        .font(.caption)
        .foregroundStyle(theme.metadata)
    }
}
