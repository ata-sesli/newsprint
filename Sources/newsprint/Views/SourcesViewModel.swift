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
    @Published var hackerNewsCount = ""
    @Published var youtubeChannel = ""
    @Published var importPreview: OPMLImportPreview?
    @Published var importMessage: String?
    @Published var showingImporter = false
    @Published var showingExporter = false
    @Published var exportDocument = TextFileDocument()
    @Published var selectedSection: SourcesPageSection = .presets
    @Published var selectedSourceID: UUID?
    @Published var selectedPresetID: String?
    @Published var selectedUnifiedRowIDs: Set<String> = []
    @Published private(set) var sourceRows: [SourceRowDisplayItem] = []
    @Published private(set) var presetRows: [PresetRowDisplayItem] = SourceDisplayItemBuilder.presetRows(for: [])
    @Published private(set) var unifiedRows: [SourcesUnifiedRowDisplayItem] = SourceDisplayItemBuilder.unifiedRows(for: [])
    private var locallyInsertedSourceIDs = Set<UUID>()

    func configureSources(_ sources: [Source]) {
        sourceRows = SourceDisplayItemBuilder.sourceRows(for: sources)
        presetRows = SourceDisplayItemBuilder.presetRows(for: sources)
        unifiedRows = SourceDisplayItemBuilder.unifiedRows(for: sources)
        pruneMissingSelections()
    }

    func configureSourcesAfterExternalChange(_ sources: [Source]) {
        if consumeLocalInsertChange(in: sources) {
            return
        }
        configureSources(sources)
    }

    var selectedPresetRow: PresetRowDisplayItem? {
        SourcesSelectionState(
            selectedSection: selectedSection,
            selectedSourceID: selectedSourceID,
            selectedPresetID: selectedPresetID
        )
        .selectedPresetRow(in: presetRows)
    }

    var selectedSourceRow: SourceRowDisplayItem? {
        SourcesSelectionState(
            selectedSection: selectedSection,
            selectedSourceID: selectedSourceID,
            selectedPresetID: selectedPresetID
        )
        .selectedSourceRow(in: sourceRows)
    }

    var selectedUnifiedRow: SourcesUnifiedRowDisplayItem? {
        selectedUnifiedRows.first
    }

    var selectedUnifiedRows: [SourcesUnifiedRowDisplayItem] {
        SourcesUnifiedSelectionState(selectedRowIDs: selectedUnifiedRowIDs)
            .selectedRows(in: unifiedRows)
    }

    var selectedAddRows: [SourcesUnifiedRowDisplayItem] {
        selectedUnifiedRows.filter { $0.action == .add }
    }

    var selectedRemoveRows: [SourcesUnifiedRowDisplayItem] {
        selectedUnifiedRows.filter { $0.action == .remove && $0.sourceID != nil }
    }

    func selectedSource(from sources: [Source]) -> Source? {
        guard selectedUnifiedRows.count <= 1 else { return nil }
        if let sourceID = selectedUnifiedRow?.sourceID {
            return sources.first { $0.id == sourceID }
        }
        guard let selectedSourceID else { return nil }
        return sources.first { $0.id == selectedSourceID }
    }

    func selectedSources(from sources: [Source]) -> [Source] {
        let selectedSourceIDs = Set(selectedRemoveRows.compactMap(\.sourceID))
        return sources.filter { selectedSourceIDs.contains($0.id) }
    }

    func selectPreset(_ row: PresetRowDisplayItem) {
        selectedPresetID = row.id
        selectedSection = .presets
    }

    func selectSource(_ row: SourceRowDisplayItem) {
        selectedSourceID = row.id
        selectedSection = .addedSources
    }

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

    func addPreset(_ row: PresetRowDisplayItem, context: ModelContext, onSourceInserted: (Source) -> Void) {
        if row.isAdded || presetRows.first(where: { $0.id == row.id })?.isAdded == true {
            errorMessage = "That source is already added."
            sourceMessage = "Already added: \(row.title)."
            return
        }

        let preset = row.preset
        let source = Source(
            title: preset.title,
            url: preset.url,
            kind: preset.kind,
            category: preset.category
        )

        do {
            try SwiftDataSourceRepository(context: context).save(source)
            noteSourceInserted(source, presetID: row.id, canonicalURLString: row.canonicalURLString)
            errorMessage = nil
            sourceMessage = "Added \(source.title)."
            onSourceInserted(source)
        } catch {
            errorMessage = error.localizedDescription
            sourceMessage = nil
        }
    }

    func addPreset(_ row: SourcesUnifiedRowDisplayItem, context: ModelContext, onSourceInserted: (Source) -> Void) {
        guard let preset = row.preset else { return }
        addPreset(
            PresetRowDisplayItem(
                id: preset.id,
                preset: preset,
                title: row.title,
                iconName: row.iconName,
                tags: row.tags,
                canonicalURLString: row.canonicalURLString,
                isAdded: row.action == .remove
            ),
            context: context,
            onSourceInserted: onSourceInserted
        )
    }

    func addSelectedPresets(context: ModelContext, onSourceInserted: (Source) -> Void) {
        let rows = selectedAddRows
        guard !rows.isEmpty else { return }

        var added = 0
        var lastError: String?
        for row in rows {
            guard let preset = row.preset else { continue }
            let source = Source(
                title: preset.title,
                url: preset.url,
                kind: preset.kind,
                category: preset.category
            )

            do {
                try SwiftDataSourceRepository(context: context).save(source)
                noteSourceInserted(
                    source,
                    presetID: row.id,
                    canonicalURLString: row.canonicalURLString,
                    selectInserted: false
                )
                onSourceInserted(source)
                added += 1
            } catch {
                lastError = error.localizedDescription
            }
        }

        if added > 0 {
            selectedUnifiedRowIDs = Set(rows.map(\.id))
            sourceMessage = "Added \(added) \(added == 1 ? "source" : "sources")."
            errorMessage = nil
        } else if let lastError {
            errorMessage = lastError
            sourceMessage = nil
        }
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

    @discardableResult
    func deleteSource(_ source: Source, context: ModelContext, onSourcesChanged: () -> Void) -> Bool {
        do {
            try SwiftDataSourceRepository(context: context).delete(source)
            sourceMessage = "Deleted \(source.title)."
            errorMessage = nil
            onSourcesChanged()
            return true
        } catch {
            errorMessage = "Could not delete source: \(error.localizedDescription)"
            sourceMessage = nil
            return false
        }
    }

    @discardableResult
    func deleteSources(_ sources: [Source], context: ModelContext, onSourcesChanged: () -> Void) -> Bool {
        guard !sources.isEmpty else { return false }
        do {
            try SwiftDataSourceRepository(context: context).delete(sources)
            let deletedIDs = Set(sources.map(\.id))
            selectedUnifiedRowIDs.subtract(unifiedRows.filter { row in
                guard let sourceID = row.sourceID else { return false }
                return deletedIDs.contains(sourceID)
            }.map(\.id))
            sourceMessage = "Deleted \(sources.count) \(sources.count == 1 ? "source" : "sources")."
            errorMessage = nil
            onSourcesChanged()
            return true
        } catch {
            errorMessage = "Could not delete sources: \(error.localizedDescription)"
            sourceMessage = nil
            return false
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

    private func noteSourceInserted(
        _ source: Source,
        presetID: String,
        canonicalURLString: String,
        selectInserted: Bool = true
    ) {
        if !sourceRows.contains(where: { $0.id == source.id }) {
            sourceRows.append(SourceDisplayItemBuilder.sourceRow(for: source))
            sourceRows.sort {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
        presetRows = SourceDisplayItemBuilder.markPresetAdded(
            canonicalURLString: canonicalURLString,
            in: presetRows
        )
        unifiedRows = unifiedRows.map { row in
            guard row.canonicalURLString == canonicalURLString else {
                return row
            }
            return SourcesUnifiedRowDisplayItem(
                id: row.id,
                title: row.title,
                iconName: row.iconName,
                tags: row.tags,
                canonicalURLString: row.canonicalURLString,
                preset: row.preset,
                sourceID: source.id,
                action: .remove,
                health: .healthy,
                healthText: SourceHealth.healthy.displayName,
                lastErrorText: nil,
                enabled: source.enabled
            )
        }
        selectedPresetID = presetID
        if selectInserted {
            selectedUnifiedRowIDs = [presetID]
        }
        locallyInsertedSourceIDs.insert(source.id)
        pruneMissingSelections()
    }

    private func consumeLocalInsertChange(in sources: [Source]) -> Bool {
        guard !locallyInsertedSourceIDs.isEmpty else {
            return false
        }
        let sourceIDs = Set(sources.map(\.id))
        guard locallyInsertedSourceIDs.isSubset(of: sourceIDs) else {
            return false
        }
        locallyInsertedSourceIDs.removeAll()
        return true
    }

    private func pruneMissingSelections() {
        var selection = SourcesSelectionState(
            selectedSection: selectedSection,
            selectedSourceID: selectedSourceID,
            selectedPresetID: selectedPresetID
        )
        selection.pruneMissingSelections(sourceRows: sourceRows, presetRows: presetRows)
        selectedSourceID = selection.selectedSourceID
        selectedPresetID = selection.selectedPresetID
        var unifiedSelection = SourcesUnifiedSelectionState(selectedRowIDs: selectedUnifiedRowIDs)
        unifiedSelection.pruneMissingRows(in: unifiedRows)
        selectedUnifiedRowIDs = unifiedSelection.selectedRowIDs
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
