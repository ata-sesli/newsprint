import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import newsprintCore

struct SourcesView: View {
    @Environment(\.modelContext) private var modelContext
    let sources: [Source]
    let refresh: (Source) -> Void
    let sourceChanged: () -> Void
    @StateObject private var viewModel = SourcesViewModel()

    var body: some View {
        Form {
            Section("Add Source") {
                TextField("Title", text: $viewModel.title)
                TextField("Feed or Website URL", text: $viewModel.urlString)
                Picker("Kind", selection: $viewModel.kind) {
                    ForEach(SourceKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                HStack {
                    Button(viewModel.isDiscovering ? "Checking..." : "Add Source", systemImage: "plus") {
                        Task {
                            await viewModel.addSource(context: modelContext, onSourcesChanged: sourceChanged)
                        }
                    }
                    .disabled(viewModel.isDiscovering)
                    .buttonStyle(.borderedProminent)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("YouTube") {
                TextField("Channel ID or feed URL", text: $viewModel.youtubeChannel)
                Button("Add YouTube Feed", systemImage: "play.rectangle") {
                    viewModel.addYouTubeFeed(context: modelContext, onSourcesChanged: sourceChanged)
                }
                .disabled(viewModel.youtubeChannel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.bordered)
            }

            if !sources.isEmpty {
                Section("Added Sources") {
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

            Section("Presets") {
                ForEach(PresetSourceCatalog.all) { preset in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(preset.title)
                            Text(preset.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add", systemImage: "plus.circle") {
                            viewModel.addPreset(preset, context: modelContext, onSourcesChanged: sourceChanged)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if let sourceMessage = viewModel.sourceMessage {
                    Text(sourceMessage)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Import and Export") {
                HStack {
                    Button("Import OPML", systemImage: "square.and.arrow.down") {
                        viewModel.showingImporter = true
                    }
                    .buttonStyle(.bordered)

                    Button("Export OPML", systemImage: "square.and.arrow.up") {
                        viewModel.exportOPML(sources: sources)
                    }
                    .buttonStyle(.bordered)
                }

                if let importMessage = viewModel.importMessage {
                    Text(importMessage)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.discoveredFeeds.isEmpty {
                Section("Discovered Feeds") {
                    ForEach(viewModel.discoveredFeeds) { feed in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(feed.title ?? feed.url.host() ?? feed.url.absoluteString)
                                Text(feed.url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            Spacer()

                            Text(feed.type.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Add", systemImage: "plus.circle") {
                                viewModel.addDiscoveredFeed(feed, context: modelContext, onSourcesChanged: sourceChanged)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            if let importPreview = viewModel.importPreview, !importPreview.sources.isEmpty {
                Section("OPML Preview") {
                    ForEach(importPreview.sources, id: \.feedURL) { source in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(source.title)
                                Text(source.feedURL.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            if let category = source.category {
                                Text(category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button("Import \(importPreview.sources.count) Sources", systemImage: "tray.and.arrow.down") {
                        viewModel.importSources(from: importPreview, context: modelContext, onSourcesChanged: sourceChanged)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

        }
        .formStyle(.grouped)
        .navigationTitle("Sources")
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

private struct SourceRow: View {
    let source: Source
    let refresh: (Source) -> Void
    let updateTitle: (Source, String) -> Void
    let updateCategory: (Source, String) -> Void
    let updateEnabled: (Source, Bool) -> Void
    let deleteSource: (Source) -> Void
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    TextField("Title", text: Binding(
                        get: { source.title },
                        set: { value in updateTitle(source, value) }
                    ))
                    .font(.headline)
                    Text(source.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            HStack(spacing: 12) {
                Text("Kind: \(source.kind.displayName)")
                TextField("Category", text: Binding(
                    get: { source.category ?? "" },
                    set: { value in updateCategory(source, value) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
                Text("Last fetch: \(source.lastFetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")")
                Text("Last success: \(source.lastSuccessfulFetchAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let error = source.lastErrorMessage {
                Text("Last error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Delete this source and its articles?", isPresented: $isConfirmingDelete) {
            Button("Delete Source", role: .destructive) {
                deleteSource(source)
            }
        }
    }
}
