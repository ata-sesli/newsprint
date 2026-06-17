import Foundation

public struct SourceRowDisplayItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let urlString: String
    public let kindTitle: String
    public let category: String?
    public let successText: String
    public let errorMessage: String?
    public let iconName: String
    public let enabled: Bool
}

public struct PresetRowDisplayItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let preset: PresetSource
    public let title: String
    public let iconName: String
    public let tags: [String]
    public let canonicalURLString: String
    public let isAdded: Bool
}

public enum SourcesPageSection: String, Codable, CaseIterable, Sendable {
    case presets
    case addedSources

    public var displayName: String {
        switch self {
        case .presets: "Presets"
        case .addedSources: "Added Sources"
        }
    }
}

public struct SourcesSelectionState: Equatable, Sendable {
    public var selectedSection: SourcesPageSection
    public var selectedSourceID: UUID?
    public var selectedPresetID: String?

    public init(
        selectedSection: SourcesPageSection = .presets,
        selectedSourceID: UUID? = nil,
        selectedPresetID: String? = nil
    ) {
        self.selectedSection = selectedSection
        self.selectedSourceID = selectedSourceID
        self.selectedPresetID = selectedPresetID
    }

    public func selectedSourceRow(in rows: [SourceRowDisplayItem]) -> SourceRowDisplayItem? {
        guard let selectedSourceID else { return nil }
        return rows.first { $0.id == selectedSourceID }
    }

    public func selectedPresetRow(in rows: [PresetRowDisplayItem]) -> PresetRowDisplayItem? {
        guard let selectedPresetID else { return nil }
        return rows.first { $0.id == selectedPresetID }
    }

    public mutating func pruneMissingSelections(
        sourceRows: [SourceRowDisplayItem],
        presetRows: [PresetRowDisplayItem]
    ) {
        if selectedSourceID != nil, selectedSourceRow(in: sourceRows) == nil {
            selectedSourceID = nil
        }
        if selectedPresetID != nil, selectedPresetRow(in: presetRows) == nil {
            selectedPresetID = nil
        }
    }
}

public enum SourceDisplayItemBuilder {
    public static func sourceRows(for sources: [Source]) -> [SourceRowDisplayItem] {
        sources.map { source in
            SourceRowDisplayItem(
                id: source.id,
                title: source.title,
                urlString: source.url.absoluteString,
                kindTitle: source.kind.displayName,
                category: source.category?.nilIfEmpty,
                successText: "Success: \(source.lastSuccessfulFetchAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")",
                errorMessage: source.lastErrorMessage,
                iconName: iconName(for: source.kind),
                enabled: source.enabled
            )
        }
    }

    public static func presetRows(
        for sources: [Source],
        presets: [PresetSource] = PresetSourceCatalog.all
    ) -> [PresetRowDisplayItem] {
        let addedURLs = Set(sources.map { URLCanonicalizer.canonicalize($0.url).absoluteString })
        return presets
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { preset in
                let canonicalURLString = URLCanonicalizer.canonicalize(preset.url).absoluteString
                return PresetRowDisplayItem(
                    id: preset.id,
                    preset: preset,
                    title: preset.title,
                    iconName: iconName(for: preset.kind),
                    tags: displayTags(for: preset),
                    canonicalURLString: canonicalURLString,
                    isAdded: addedURLs.contains(canonicalURLString)
                )
            }
    }

    private static func iconName(for kind: SourceKind) -> String {
        switch kind {
        case .hackerNews:
            "text.bubble"
        case .youtube:
            "play.rectangle"
        case .rss, .atom, .jsonFeed, .blog:
            "dot.radiowaves.left.and.right"
        }
    }

    private static func displayTags(for preset: PresetSource) -> [String] {
        var tags: [String] = []
        for tag in [preset.category, preset.kind.displayName] {
            guard !tags.contains(tag) else { continue }
            tags.append(tag)
        }
        return tags
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
