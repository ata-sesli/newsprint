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
    #expect(row.iconName == "dot.radiowaves.left.and.right")
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
    var selection = SourcesSelectionState(selectedPresetID: selected.id)

    #expect(selection.selectedPresetRow(in: rows) == selected)
}

@Test func sourcesSelectionResolvesSourceRow() throws {
    let source = Source(
        title: "Example",
        url: URL(string: "https://example.com/feed.xml")!,
        kind: .rss
    )
    let rows = SourceDisplayItemBuilder.sourceRows(for: [source])
    var selection = SourcesSelectionState(selectedSection: .addedSources, selectedSourceID: source.id)

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
