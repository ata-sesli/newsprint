import AppKit
import SwiftUI
import newsprintCore

struct ArticleListView: View {
    let articles: [Article]
    @Binding var selectedArticle: Article?

    var body: some View {
        List(articles, selection: $selectedArticle) { article in
            ArticleRow(article: article)
                .tag(article)
                .contextMenu {
                    ArticleContextMenu(article: article, hackerNewsMetadata: HackerNewsMetadata(text: article.contentText ?? article.excerpt))
                }
        }
        .overlay {
            if articles.isEmpty {
                ContentUnavailableView("No Articles", systemImage: "newspaper", description: Text("Add a source and refresh to read locally."))
            }
        }
        .navigationTitle("Articles")
    }
}

private struct ArticleRow: View {
    let article: Article
    private var hackerNewsMetadata: HackerNewsMetadata? {
        HackerNewsMetadata(text: article.contentText ?? article.excerpt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if hackerNewsMetadata != nil {
                    HackerNewsBadge()
                }

                Text(article.title)
                    .font(.headline)
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(2)

                if article.isStarred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }

                if article.isHidden {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondary)
                }
            }

            Text(metadata)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let hackerNewsMetadata {
                HackerNewsStatLabels(metadata: hackerNewsMetadata)
            }

            if let preview = previewText, !preview.isEmpty {
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if !article.tagNames.isEmpty {
                HStack {
                    ForEach(article.tagNames, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var metadata: String {
        let date = article.publishedAt ?? article.fetchedAt
        return "\(article.sourceTitle) · \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var previewText: String? {
        if let hackerNewsMetadata {
            return hackerNewsMetadata.authorComment
        }
        return article.contentText ?? article.excerpt
    }
}
