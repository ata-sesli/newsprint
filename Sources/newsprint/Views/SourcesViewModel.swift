import Foundation
import SwiftData
import SwiftUI
import newsprintCore

@MainActor
final class SourcesViewModel: ObservableObject {
    @Published var title = ""
    @Published var urlString = ""
    @Published var kind: SourceKind = .rss
    @Published var errorMessage: String?
    @Published var sourceMessage: String?
    @Published var discoveredFeeds: [DiscoveredFeed] = []
    @Published var isDiscovering = false
    @Published var hackerNewsKind: HackerNewsFeedKind = .frontPage
    @Published var hackerNewsMinimumPoints = ""
    @Published var hackerNewsMinimumComments = ""
    @Published var hackerNewsSearchQuery = ""
    @Published var hackerNewsCount = ""
    @Published var youtubeChannel = ""
    @Published var importPreview: OPMLImportPreview?
    @Published var importMessage: String?
    @Published var showingImporter = false
    @Published var showingExporter = false
    @Published var exportDocument = TextFileDocument()

    func addSource(context: ModelContext, onSourcesChanged: () -> Void) async {
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
                addDiscoveredFeed(feed, context: context, onSourcesChanged: onSourcesChanged)
            case .candidates(let feeds):
                discoveredFeeds = feeds
                errorMessage = feeds.isEmpty ? "No feed was found at that URL." : nil
            }
        } catch {
            discoveredFeeds = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func addDiscoveredFeed(_ feed: DiscoveredFeed, context: ModelContext, onSourcesChanged: () -> Void) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = Source(
            title: trimmedTitle.isEmpty ? (feed.title ?? feed.url.host() ?? feed.url.absoluteString) : trimmedTitle,
            url: feed.url,
            kind: feed.type.sourceKind
        )

        saveNewSource(source, context: context, onSourcesChanged: onSourcesChanged)
        if errorMessage == nil {
            title = ""
            urlString = ""
            kind = .rss
            discoveredFeeds = []
        }
    }

    func addPreset(_ preset: PresetSource, context: ModelContext, onSourcesChanged: () -> Void) {
        let source = Source(
            title: preset.title,
            url: preset.url,
            kind: preset.kind,
            category: preset.category
        )
        saveNewSource(source, context: context, onSourcesChanged: onSourcesChanged)
    }

    func addHackerNewsFeed(context: ModelContext, onSourcesChanged: () -> Void) {
        guard let configuration = hackerNewsConfiguration(reportErrors: true) else {
            return
        }

        let source = Source(
            title: HackerNewsFeedURLBuilder.title(for: configuration),
            url: HackerNewsFeedURLBuilder.url(for: configuration),
            kind: .hackerNews,
            category: "Hacker News"
        )
        saveNewSource(source, context: context, onSourcesChanged: onSourcesChanged)
    }

    var hackerNewsPreviewURL: URL? {
        guard let configuration = hackerNewsConfiguration(reportErrors: false) else {
            return nil
        }
        return HackerNewsFeedURLBuilder.url(for: configuration)
    }

    func addYouTubeFeed(context: ModelContext, onSourcesChanged: () -> Void) {
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
        saveNewSource(source, context: context, onSourcesChanged: onSourcesChanged)
        if errorMessage == nil {
            youtubeChannel = ""
            title = ""
        }
    }

    func updateTitle(_ source: Source, title: String, context: ModelContext, onSourcesChanged: () -> Void) {
        updateSource(source, title: title, category: source.category, enabled: source.enabled, context: context, onSourcesChanged: onSourcesChanged)
    }

    func updateCategory(_ source: Source, category: String, context: ModelContext, onSourcesChanged: () -> Void) {
        updateSource(source, title: source.title, category: category, enabled: source.enabled, context: context, onSourcesChanged: onSourcesChanged)
    }

    func updateEnabled(_ source: Source, enabled: Bool, context: ModelContext, onSourcesChanged: () -> Void) {
        updateSource(source, title: source.title, category: source.category, enabled: enabled, context: context, onSourcesChanged: onSourcesChanged)
    }

    func deleteSource(_ source: Source, context: ModelContext, onSourcesChanged: () -> Void) {
        do {
            try SwiftDataSourceRepository(context: context).delete(source)
            sourceMessage = "Deleted \(source.title)."
            errorMessage = nil
            onSourcesChanged()
        } catch {
            errorMessage = "Could not delete source: \(error.localizedDescription)"
            sourceMessage = nil
        }
    }

    func importOPML(from result: Result<URL, Error>) {
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

    func importSources(from preview: OPMLImportPreview, context: ModelContext, onSourcesChanged: () -> Void) {
        var imported = 0
        var skipped = 0
        for importedSource in preview.sources {
            let source = Source(
                title: importedSource.title,
                url: importedSource.feedURL,
                siteURL: importedSource.siteURL,
                kind: importedSource.kind,
                category: importedSource.category
            )
            do {
                if try saveSource(source, context: context) {
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
        onSourcesChanged()
    }

    func exportOPML(sources: [Source]) {
        do {
            let data = try OPMLExporter().export(sources: sources)
            exportDocument = TextFileDocument(text: String(data: data, encoding: .utf8) ?? "")
            showingExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateSource(
        _ source: Source,
        title: String,
        category: String?,
        enabled: Bool,
        context: ModelContext,
        onSourcesChanged: () -> Void
    ) {
        let oldTitle = source.title
        let oldCategory = source.category
        let oldEnabled = source.enabled
        do {
            try SwiftDataSourceRepository(context: context).update(
                source,
                title: title,
                category: category,
                enabled: enabled
            )
            errorMessage = nil
            onSourcesChanged()
        } catch {
            source.title = oldTitle
            source.category = oldCategory
            source.enabled = oldEnabled
            errorMessage = "Could not update source: \(error.localizedDescription)"
        }
    }

    private func saveNewSource(_ source: Source, context: ModelContext, onSourcesChanged: () -> Void) {
        do {
            let inserted = try saveSource(source, context: context)
            errorMessage = inserted ? nil : "That source is already added."
            sourceMessage = inserted ? "Added \(source.title)." : "Already added: \(source.title)."
            if inserted {
                onSourcesChanged()
            }
        } catch {
            errorMessage = error.localizedDescription
            sourceMessage = nil
        }
    }

    private func saveSource(_ source: Source, context: ModelContext) throws -> Bool {
        try SwiftDataSourceRepository(context: context).saveIfNew(source)
    }

    private func hackerNewsConfiguration(reportErrors: Bool) -> HackerNewsFeedConfiguration? {
        guard let minimumPoints = optionalPositiveInt(hackerNewsMinimumPoints, fieldName: "Minimum points", reportErrors: reportErrors),
              let minimumComments = optionalPositiveInt(hackerNewsMinimumComments, fieldName: "Minimum comments", reportErrors: reportErrors),
              let count = optionalPositiveInt(hackerNewsCount, fieldName: "Item count", reportErrors: reportErrors) else {
            return nil
        }

        return HackerNewsFeedConfiguration(
            kind: hackerNewsKind,
            minimumPoints: minimumPoints,
            minimumComments: minimumComments,
            searchQuery: hackerNewsSearchQuery,
            count: count
        )
    }

    private func optionalPositiveInt(_ value: String, fieldName: String, reportErrors: Bool) -> Int?? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .some(nil)
        }
        guard let number = Int(trimmed), number > 0 else {
            if reportErrors {
                errorMessage = "\(fieldName) must be a positive number."
            }
            return nil
        }
        if reportErrors {
            errorMessage = nil
        }
        return .some(number)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
