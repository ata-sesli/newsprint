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

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Add Direct Feed") {
                    TextField("Title", text: $title)
                    TextField("Feed URL", text: $urlString)
                    Picker("Kind", selection: $kind) {
                        ForEach(SourceKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    HStack {
                        Button("Add Source", systemImage: "plus") {
                            addSource()
                        }
                        .buttonStyle(.borderedProminent)

                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 190)

            Divider()

            List {
                ForEach(sources) { source in
                    SourceRow(source: source, refresh: refresh)
                }
            }
        }
        .navigationTitle("Sources")
    }

    private func addSource() {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), url.scheme != nil else {
            errorMessage = "Enter a valid feed URL."
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = Source(
            title: trimmedTitle.isEmpty ? (url.host() ?? trimmedURL) : trimmedTitle,
            url: url,
            kind: kind
        )

        modelContext.insert(source)

        do {
            try modelContext.save()
            title = ""
            urlString = ""
            kind = .rss
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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

