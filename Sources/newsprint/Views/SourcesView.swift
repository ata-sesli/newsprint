import SwiftData
import SwiftUI
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
            }
            .formStyle(.grouped)
            .frame(minHeight: discoveredFeeds.isEmpty ? 190 : 330)

            Divider()

            List {
                ForEach(sources) { source in
                    SourceRow(source: source, refresh: refresh)
                }
            }
        }
        .navigationTitle("Sources")
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

        modelContext.insert(source)

        do {
            try modelContext.save()
            title = ""
            urlString = ""
            kind = .rss
            errorMessage = nil
            discoveredFeeds = []
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(source.title)
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
            }

            HStack(spacing: 12) {
                Text("Kind: \(source.kind.displayName)")
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
    }
}
