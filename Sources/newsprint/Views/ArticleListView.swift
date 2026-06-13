import AppKit
import SwiftUI
import newsprintCore

struct ArticleListView: View {
    @Environment(\.newsprintTheme) private var theme
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
        .scrollContentBackground(.hidden)
        .background(theme.paneBackground)
        .navigationTitle("Articles")
    }
}

private struct ArticleRow: View {
    @Environment(\.articleListDensity) private var density
    @Environment(\.newsprintTheme) private var theme
    let article: Article
    private var hackerNewsMetadata: HackerNewsMetadata? {
        HackerNewsMetadata(text: article.contentText ?? article.excerpt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(article.isRead ? Color.clear : theme.rowAccent)
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: density.rowSpacing) {
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
                    .foregroundStyle(theme.metadata)

                if let hackerNewsMetadata {
                    HackerNewsStatLabels(metadata: hackerNewsMetadata)
                }

                if let preview = previewText, !preview.isEmpty {
                    Text(preview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(density.previewLineLimit)
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
        }
        .padding(.vertical, density.rowVerticalPadding)
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
