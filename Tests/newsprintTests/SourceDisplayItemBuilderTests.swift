import Foundation
import Testing
@testable import newsprintCore

@Test func sourceDisplayBuilderSortsPresetsAlphabetically() throws {
    let rows = SourceDisplayItemBuilder.presetRows(for: [])

    #expect(rows.map(\.title) == rows.map(\.title).sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    })
    #expect(rows.count == PresetSourceCatalog.all.count)
}

@Test func sourceDisplayBuilderMarksAddedPresetByCanonicalURL() throws {
    let source = Source(
        title: "GitHub Engineering",
        url: URL(string: "https://github.blog/category/engineering/feed/?utm_source=newsletter")!,
        kind: .blog,
        category: "Engineering"
    )

    let rows = SourceDisplayItemBuilder.presetRows(for: [source])
    let github = try #require(rows.first { $0.title == "GitHub Engineering" })

    #expect(github.isAdded)
}

@Test func sourceDisplayBuilderDoesNotDuplicatePresetTags() throws {
    let preset = PresetSource(
        title: "Example",
        url: URL(string: "https://example.com/feed.xml")!,
        category: "Blog",
        kind: .blog
    )

    let rows = SourceDisplayItemBuilder.presetRows(for: [], presets: [preset])

    #expect(rows.first?.tags == ["Blog"])
}

@Test func sourceDisplayBuilderFormatsMissingSourceMetadata() throws {
    let source = Source(
        title: "Example",
        url: URL(string: "https://example.com/feed.xml")!,
        kind: .rss,
        category: nil,
        lastSuccessfulFetchAt: nil,
        lastErrorMessage: nil
    )

    let row = try #require(SourceDisplayItemBuilder.sourceRows(for: [source]).first)

    #expect(row.title == "Example")
    #expect(row.urlString == "https://example.com/feed.xml")
    #expect(row.kindTitle == "RSS")
    #expect(row.category == nil)
    #expect(row.successText == "Success: Never")
    #expect(row.errorMessage == nil)
    #expect(row.health == .healthy)
    #expect(row.healthText == "Healthy")
    #expect(row.lastErrorText == nil)
    #expect(row.iconName == "dot.radiowaves.left.and.right")
}

@Test func sourceDisplayBuilderMarksRowsWithErrorsUnhealthy() throws {
    let source = Source(
        title: "Broken",
        url: URL(string: "https://example.com/feed.xml")!,
        kind: .rss,
        lastErrorMessage: "Timeout: the feed did not respond in time"
    )

    let row = SourceDisplayItemBuilder.sourceRow(for: source)

    #expect(row.health == .unhealthy)
    #expect(row.healthText == "Unhealthy")
    #expect(row.lastErrorText == "Timeout: the feed did not respond in time")
}

@Test func sourceDisplayBuilderSingleSourceRowMatchesBulkBuilder() throws {
    let source = Source(
        title: "Example",
        url: URL(string: "https://example.com/feed.xml")!,
        kind: .rss,
        category: "Engineering"
    )

    let single = SourceDisplayItemBuilder.sourceRow(for: source)
    let bulk = try #require(SourceDisplayItemBuilder.sourceRows(for: [source]).first)

    #expect(single == bulk)
}

@Test func sourceDisplayBuilderHomeSourceRowsExcludeHackerNewsSources() throws {
    let blog = Source(
        title: "Blog",
        url: URL(string: "https://example.com/feed.xml")!,
        kind: .blog
    )
    let hackerNews = Source(
        title: "Hacker News Show",
        url: URL(string: "https://hacker-news.firebaseio.com/v0/showstories.json")!,
        kind: .hackerNews
    )

    let rows = SourceDisplayItemBuilder.homeSourceRows(for: [hackerNews, blog])

    #expect(rows.map(\.title) == ["Blog"])
}

@Test func sourceDisplayBuilderMarksSinglePresetAddedWithoutReorderingRows() throws {
    let rows = SourceDisplayItemBuilder.presetRows(for: [])
    let selected = try #require(rows.first { $0.title == "GitHub Engineering" })

    let updatedRows = SourceDisplayItemBuilder.markPresetAdded(
        canonicalURLString: selected.canonicalURLString,
        in: rows
    )
    let updatedSelected = try #require(updatedRows.first { $0.id == selected.id })
    let otherRows = updatedRows.filter { $0.id != selected.id }

    #expect(updatedRows.map(\.id) == rows.map(\.id))
    #expect(updatedSelected.isAdded)
    #expect(otherRows.allSatisfy { !$0.isAdded })
}

@Test func sourcesSelectionResolvesPresetRow() throws {
    let rows = SourceDisplayItemBuilder.presetRows(for: [])
    let selected = try #require(rows.first)
    let selection = SourcesSelectionState(selectedPresetID: selected.id)

    #expect(selection.selectedPresetRow(in: rows) == selected)
}

@Test func sourcesSelectionResolvesSourceRow() throws {
    let source = Source(
        title: "Example",
        url: URL(string: "https://example.com/feed.xml")!,
        kind: .rss
    )
    let rows = SourceDisplayItemBuilder.sourceRows(for: [source])
    let selection = SourcesSelectionState(selectedSection: .addedSources, selectedSourceID: source.id)

    #expect(selection.selectedSourceRow(in: rows)?.id == source.id)
}

@Test func sourcesSelectionClearsMissingRows() throws {
    let source = Source(
        title: "Example",
        url: URL(string: "https://example.com/feed.xml")!,
        kind: .rss
    )
    let preset = try #require(SourceDisplayItemBuilder.presetRows(for: []).first)
    var selection = SourcesSelectionState(
        selectedSection: .addedSources,
        selectedSourceID: source.id,
        selectedPresetID: preset.id
    )

    selection.pruneMissingSelections(sourceRows: [], presetRows: [])

    #expect(selection.selectedSourceID == nil)
    #expect(selection.selectedPresetID == nil)
}

@Test func sourceDisplayBuilderUpdatesPresetAddedStateAfterSourceChange() throws {
    let initialRows = SourceDisplayItemBuilder.presetRows(for: [])
    let preset = try #require(initialRows.first)
    let source = Source(
        title: preset.title,
        url: preset.preset.url,
        kind: preset.preset.kind,
        category: preset.preset.category
    )

    let updatedRows = SourceDisplayItemBuilder.presetRows(for: [source])
    let updatedPreset = try #require(updatedRows.first { $0.id == preset.id })

    #expect(!preset.isAdded)
    #expect(updatedPreset.isAdded)
}

@Test func sourceDisplayBuilderBuildsUnifiedRowsForPresetsAndCustomSources() throws {
    let preset = PresetSource(
        title: "Preset A",
        url: URL(string: "https://example.com/a.xml")!,
        category: "AI",
        kind: .blog
    )
    let addedPresetSource = Source(
        title: "Preset A",
        url: preset.url,
        kind: preset.kind,
        category: preset.category
    )
    let customSource = Source(
        title: "Custom Z",
        url: URL(string: "https://custom.example.com/feed.xml")!,
        kind: .rss,
        lastErrorMessage: "HTTP 404"
    )

    let rows = SourceDisplayItemBuilder.unifiedRows(
        for: [customSource, addedPresetSource],
        presets: [preset]
    )

    #expect(rows.map(\.title) == ["Custom Z", "Preset A"])
    let custom = try #require(rows.first { $0.title == "Custom Z" })
    let presetRow = try #require(rows.first { $0.title == "Preset A" })
    #expect(custom.action == .remove)
    #expect(custom.sourceID == customSource.id)
    #expect(custom.health == .unhealthy)
    #expect(presetRow.action == .remove)
    #expect(presetRow.sourceID == addedPresetSource.id)
    #expect(presetRow.preset != nil)
}

@Test func sourceDisplayBuilderUnifiedRowsShowAddForMissingPreset() throws {
    let preset = PresetSource(
        title: "Preset A",
        url: URL(string: "https://example.com/a.xml")!,
        category: "AI",
        kind: .blog
    )

    let row = try #require(SourceDisplayItemBuilder.unifiedRows(for: [], presets: [preset]).first)

    #expect(row.action == .add)
    #expect(row.sourceID == nil)
    #expect(row.preset == preset)
}
