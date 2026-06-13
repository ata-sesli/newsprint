import AppKit
import SwiftData
import SwiftUI
import newsprintCore

struct ReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.readerFontChoice) private var readerFontChoice
    @Environment(\.readerFontSize) private var readerFontSize
    let article: Article?
    @State private var actionErrorMessage: String?

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
                                .fontDesign(readerFontChoice.fontDesign)
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
                            ArticleActionButtons(
                                article: article,
                                hackerNewsMetadata: hackerNewsMetadata,
                                onSaveError: { message in
                                    actionErrorMessage = message.isEmpty ? nil : message
                                }
                            )
                        }

                        if let actionErrorMessage {
                            Text(actionErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Divider()

                        ReaderContent(article: article, hackerNewsMetadata: hackerNewsMetadata)
                    }
                    .padding(24)
                    .background(theme.readerSurface, in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(theme.readerBackground)
                .contextMenu {
                    ArticleContextMenu(article: article, hackerNewsMetadata: hackerNewsMetadata)
                }
            } else {
                ContentUnavailableView("Select an Article", systemImage: "doc.text")
                    .background(theme.readerBackground)
            }
        }
    }
}

private struct ReaderContent: View {
    @Environment(\.readerFontChoice) private var readerFontChoice
    @Environment(\.readerFontSize) private var readerFontSize
    let article: Article
    let hackerNewsMetadata: HackerNewsMetadata?

    var body: some View {
        if let hackerNewsMetadata {
            if let authorComment = hackerNewsMetadata.authorComment {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Author Comment", systemImage: "text.quote")
                        .font(.headline)
                    Text(authorComment)
                        .font(.system(size: CGFloat(readerFontSize), design: readerFontChoice.fontDesign))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                }
                .padding(14)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView("No Author Comment", systemImage: "text.bubble", description: Text("Use Open Original or Open HN Thread for the discussion."))
            }
        } else {
            Text(article.contentText ?? article.excerpt ?? "Open the original article to read the full post.")
                .font(.system(size: CGFloat(readerFontSize), design: readerFontChoice.fontDesign))
                .lineSpacing(6)
                .textSelection(.enabled)
        }
    }
}
