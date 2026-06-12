import AppKit
import SwiftData
import SwiftUI
import newsprintCore

struct ReaderView: View {
    @Environment(\.modelContext) private var modelContext
    let article: Article?

    var body: some View {
        Group {
            if let article {
                let hackerNewsMetadata = HackerNewsMetadata(text: article.contentText ?? article.excerpt)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            if hackerNewsMetadata != nil {
                                HackerNewsBadge()
                            }

                            Text(article.title)
                                .font(.largeTitle)
                                .fontWeight(.semibold)
                                .textSelection(.enabled)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(article.sourceTitle)
                            if let author = article.author {
                                Text(author)
                            }
                            Text((article.publishedAt ?? article.fetchedAt).formatted(date: .abbreviated, time: .shortened))
                            if let hackerNewsMetadata {
                                HackerNewsStatLabels(metadata: hackerNewsMetadata)
                            } else {
                                Text(article.url.absoluteString)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        HStack {
                            ArticleActionButtons(article: article, hackerNewsMetadata: hackerNewsMetadata)
                        }

                        Divider()

                        ReaderContent(article: article, hackerNewsMetadata: hackerNewsMetadata)
                    }
                    .padding(24)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contextMenu {
                    ArticleContextMenu(article: article, hackerNewsMetadata: hackerNewsMetadata)
                }
            } else {
                ContentUnavailableView("Select an Article", systemImage: "doc.text")
            }
        }
    }
}

private struct ReaderContent: View {
    let article: Article
    let hackerNewsMetadata: HackerNewsMetadata?

    var body: some View {
        if let hackerNewsMetadata {
            if let authorComment = hackerNewsMetadata.authorComment {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Author Comment", systemImage: "text.quote")
                        .font(.headline)
                    Text(authorComment)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                .padding(14)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView("No Author Comment", systemImage: "text.bubble", description: Text("Use Open Original or Open HN Thread for the discussion."))
            }
        } else {
            Text(article.contentText ?? article.excerpt ?? "Open the original article to read the full post.")
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }
}
