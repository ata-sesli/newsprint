import Foundation

public struct SourceRowDisplayItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let urlString: String
    public let kindTitle: String
    public let category: String?
    public let successText: String
    public let errorMessage: String?
    public let health: SourceHealth
    public let healthText: String
    public let lastErrorText: String?
    public let iconName: String
    public let enabled: Bool
}

public enum SourceHealth: String, Codable, Equatable, Sendable {
    case healthy
    case unhealthy

    public var displayName: String {
        switch self {
        case .healthy:
            "Healthy"
        case .unhealthy:
            "Unhealthy"
        }
    }
}

public enum SourceUnifiedRowAction: String, Codable, Equatable, Sendable {
    case add
    case remove
}

public struct SourcesUnifiedRowDisplayItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let iconName: String
    public let tags: [String]
    public let canonicalURLString: String
    public let preset: PresetSource?
    public let sourceID: UUID?
    public let action: SourceUnifiedRowAction
    public let health: SourceHealth
    public let healthText: String
    public let lastErrorText: String?
    public let enabled: Bool

    public init(
        id: String,
        title: String,
        iconName: String,
        tags: [String],
        canonicalURLString: String,
        preset: PresetSource?,
        sourceID: UUID?,
        action: SourceUnifiedRowAction,
        health: SourceHealth,
        healthText: String,
        lastErrorText: String?,
        enabled: Bool
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.tags = tags
        self.canonicalURLString = canonicalURLString
        self.preset = preset
        self.sourceID = sourceID
        self.action = action
        self.health = health
        self.healthText = healthText
        self.lastErrorText = lastErrorText
        self.enabled = enabled
    }
}

public struct PresetRowDisplayItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let preset: PresetSource
    public let title: String
    public let iconName: String
    public let tags: [String]
    public let canonicalURLString: String
    public let isAdded: Bool

    public init(
        id: String,
        preset: PresetSource,
        title: String,
        iconName: String,
        tags: [String],
        canonicalURLString: String,
        isAdded: Bool
    ) {
        self.id = id
        self.preset = preset
        self.title = title
        self.iconName = iconName
        self.tags = tags
        self.canonicalURLString = canonicalURLString
        self.isAdded = isAdded
    }
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
    public static func sourceRow(for source: Source) -> SourceRowDisplayItem {
        let health = health(for: source)
        return SourceRowDisplayItem(
            id: source.id,
            title: source.title,
            urlString: source.url.absoluteString,
            kindTitle: source.kind.displayName,
            category: source.category?.nilIfEmpty,
            successText: "Success: \(source.lastSuccessfulFetchAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")",
            errorMessage: source.lastErrorMessage,
            health: health,
            healthText: health.displayName,
            lastErrorText: source.lastErrorMessage?.nilIfEmpty,
            iconName: iconName(for: source.kind),
            enabled: source.enabled
        )
    }

    public static func sourceRows(for sources: [Source]) -> [SourceRowDisplayItem] {
        sources.map(sourceRow(for:))
    }

    public static func homeSourceRows(for sources: [Source]) -> [SourceRowDisplayItem] {
        sources
            .filter { $0.kind != .hackerNews }
            .map(sourceRow(for:))
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

    public static func markPresetAdded(
        canonicalURLString: String,
        in rows: [PresetRowDisplayItem]
    ) -> [PresetRowDisplayItem] {
        rows.map { row in
            guard row.canonicalURLString == canonicalURLString else {
                return row
            }
            return PresetRowDisplayItem(
                id: row.id,
                preset: row.preset,
                title: row.title,
                iconName: row.iconName,
                tags: row.tags,
                canonicalURLString: row.canonicalURLString,
                isAdded: true
            )
        }
    }

    public static func unifiedRows(
        for sources: [Source],
        presets: [PresetSource] = PresetSourceCatalog.all
    ) -> [SourcesUnifiedRowDisplayItem] {
        let sourceByCanonicalURL = Dictionary(
            sources.map { source in
                (URLCanonicalizer.canonicalize(source.url).absoluteString, source)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let presetCanonicalURLs = Set(presets.map { URLCanonicalizer.canonicalize($0.url).absoluteString })
        var rows: [SourcesUnifiedRowDisplayItem] = presets.map { preset in
            let canonicalURLString = URLCanonicalizer.canonicalize(preset.url).absoluteString
            let source = sourceByCanonicalURL[canonicalURLString]
            return unifiedRow(
                title: preset.title,
                iconName: iconName(for: preset.kind),
                tags: displayTags(for: preset),
                canonicalURLString: canonicalURLString,
                preset: preset,
                source: source
            )
        }

        rows.append(contentsOf: sources.compactMap { source in
            let canonicalURLString = URLCanonicalizer.canonicalize(source.url).absoluteString
            guard !presetCanonicalURLs.contains(canonicalURLString) else {
                return nil
            }
            return unifiedRow(
                title: source.title,
                iconName: iconName(for: source.kind),
                tags: sourceTags(for: source),
                canonicalURLString: canonicalURLString,
                preset: nil,
                source: source
            )
        })

        return rows.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private static func unifiedRow(
        title: String,
        iconName: String,
        tags: [String],
        canonicalURLString: String,
        preset: PresetSource?,
        source: Source?
    ) -> SourcesUnifiedRowDisplayItem {
        let health = source.map(health(for:)) ?? .healthy
        return SourcesUnifiedRowDisplayItem(
            id: preset?.id ?? source?.id.uuidString ?? canonicalURLString,
            title: title,
            iconName: iconName,
            tags: tags,
            canonicalURLString: canonicalURLString,
            preset: preset,
            sourceID: source?.id,
            action: source == nil ? .add : .remove,
            health: health,
            healthText: health.displayName,
            lastErrorText: source?.lastErrorMessage?.nilIfEmpty,
            enabled: source?.enabled ?? false
        )
    }

    private static func health(for source: Source) -> SourceHealth {
        source.lastErrorMessage?.nilIfEmpty == nil ? .healthy : .unhealthy
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

    private static func sourceTags(for source: Source) -> [String] {
        var tags: [String] = []
        for tag in [source.category, Optional(source.kind.displayName)] {
            guard let tag, !tags.contains(tag) else { continue }
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
