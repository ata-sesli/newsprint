import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import newsprintCore

struct SourcesView: View {
    @Environment(\.modelContext) private var modelContext
    let sources: [Source]
    let refresh: (Source) -> Void
    @State private var title = ""
    @State private var urlString = ""
    @State private var kind: SourceKind = .rss
    @State private var errorMessage: String?
    @State private var discoveredFeeds: [DiscoveredFeed] = []
    @State private var isDiscovering = false
    @State private var youtubeChannel = ""
    @State private var importPreview: OPMLImportPreview?
    @State private var importMessage: String?
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument = TextFileDocument()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Add Source") {
                    TextField("Title", text: $title)
                    TextField("Feed or Website URL", text: $urlString)
                    Picker("Kind", selection: $kind) {
                        ForEach(SourceKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    HStack {
                        Button(isDiscovering ? "Checking..." : "Add Source", systemImage: "plus") {
                            Task {
                                await addSource()
                            }
                        }
                        .disabled(isDiscovering)
                        .buttonStyle(.borderedProminent)

                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("YouTube") {
                    TextField("Channel ID or feed URL", text: $youtubeChannel)
                    Button("Add YouTube Feed", systemImage: "play.rectangle") {
                        addYouTubeFeed()
                    }
                    .disabled(youtubeChannel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                                addPreset(preset)
                            }
                        }
                    }
                }

                Section("Import and Export") {
                    HStack {
                        Button("Import OPML", systemImage: "square.and.arrow.down") {
                            showingImporter = true
                        }

                        Button("Export OPML", systemImage: "square.and.arrow.up") {
                            exportOPML()
                        }
                    }

                    if let importMessage {
                        Text(importMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                if !discoveredFeeds.isEmpty {
                    Section("Discovered Feeds") {
                        ForEach(discoveredFeeds) { feed in
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
                                    addDiscoveredFeed(feed)
                                }
                            }
                        }
                    }
                }

                if let importPreview, !importPreview.sources.isEmpty {
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
                            importSources(from: importPreview)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 460)

            Divider()

            List {
                ForEach(sources) { source in
                    SourceRow(source: source, refresh: refresh)
                }
            }
        }
        .navigationTitle("Sources")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.opml, .xml]) { result in
            importOPML(from: result)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .opml,
            defaultFilename: "newsprint-sources.opml"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addSource() async {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), url.scheme != nil else {
            errorMessage = "Enter a valid feed URL."
            return
        }

        isDiscovering = true
        defer { isDiscovering = false }

        do {
            let result = try await FeedDiscoveryService().discover(from: url)
            switch result {
            case .directFeed(let feed):
                addDiscoveredFeed(feed)
            case .candidates(let feeds):
                discoveredFeeds = feeds
                errorMessage = feeds.isEmpty ? "No feed was found at that URL." : nil
            }
        } catch {
            discoveredFeeds = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func addDiscoveredFeed(_ feed: DiscoveredFeed) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = Source(
            title: trimmedTitle.isEmpty ? (feed.title ?? feed.url.host() ?? feed.url.absoluteString) : trimmedTitle,
            url: feed.url,
            kind: feed.type.sourceKind
        )

        do {
            let inserted = try SwiftDataSourceRepository(context: modelContext).saveIfNew(source)
            errorMessage = inserted ? nil : "That source is already added."
            title = ""
            urlString = ""
            kind = .rss
            discoveredFeeds = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addPreset(_ preset: PresetSource) {
        let source = Source(
            title: preset.title,
            url: preset.url,
            kind: preset.kind,
            category: preset.category
        )
        saveNewSource(source)
    }

    private func addYouTubeFeed() {
        guard let url = PresetSourceCatalog.youtubeFeedURL(from: youtubeChannel) else {
            errorMessage = "Enter a valid YouTube channel ID or feed URL."
            return
        }
        let source = Source(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "YouTube Channel",
            url: url,
            kind: .youtube,
            category: "YouTube"
        )
        saveNewSource(source)
        youtubeChannel = ""
        title = ""
    }

    private func saveNewSource(_ source: Source) {
        do {
            let inserted = try SwiftDataSourceRepository(context: modelContext).saveIfNew(source)
            errorMessage = inserted ? nil : "That source is already added."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importOPML(from result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let data = try Data(contentsOf: url)
            importPreview = try OPMLImporter().preview(data: data)
            importMessage = "Previewing \(importPreview?.sources.count ?? 0) sources."
            errorMessage = nil
        } catch {
            importPreview = nil
            errorMessage = error.localizedDescription
        }
    }

    private func importSources(from preview: OPMLImportPreview) {
        var imported = 0
        var skipped = 0
        let repository = SwiftDataSourceRepository(context: modelContext)

        for importedSource in preview.sources {
            let source = Source(
                title: importedSource.title,
                url: importedSource.feedURL,
                siteURL: importedSource.siteURL,
                kind: importedSource.kind,
                category: importedSource.category
            )
            do {
                if try repository.saveIfNew(source) {
                    imported += 1
                } else {
                    skipped += 1
                }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        importPreview = nil
        importMessage = "Imported \(imported), skipped \(skipped) duplicates."
        errorMessage = nil
    }

    private func exportOPML() {
        do {
            let data = try OPMLExporter().export(sources: sources)
            exportDocument = TextFileDocument(text: String(data: data, encoding: .utf8) ?? "")
            showingExporter = true
        } catch {
            errorMessage = error.localizedDescription
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
    @Environment(\.modelContext) private var modelContext
    let source: Source
    let refresh: (Source) -> Void
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    TextField("Title", text: Binding(
                        get: { source.title },
                        set: { value in save { source.title = value } }
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
                    set: { value in
                        source.enabled = value
                        source.updatedAt = Date()
                        try? modelContext.save()
                    }
                ))
                .labelsHidden()

                Button("Refresh", systemImage: "arrow.clockwise") {
                    refresh(source)
                }

                Button("Delete", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            }

            HStack(spacing: 12) {
                Text("Kind: \(source.kind.displayName)")
                TextField("Category", text: Binding(
                    get: { source.category ?? "" },
                    set: { value in save { source.category = value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty } }
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
                try? SwiftDataSourceRepository(context: modelContext).delete(source)
            }
        }
    }

    private func save(_ change: () -> Void) {
        change()
        source.updatedAt = Date()
        try? modelContext.save()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
