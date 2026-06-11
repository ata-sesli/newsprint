import SwiftData
import SwiftUI
import newsprintCore

struct ReaderView: View {
    @Environment(\.modelContext) private var modelContext
    let article: Article?

    var body: some View {
        Group {
            if let article {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(article.title)
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                            .textSelection(.enabled)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(article.sourceTitle)
                            if let author = article.author {
                                Text(author)
                            }
                            Text((article.publishedAt ?? article.fetchedAt).formatted(date: .abbreviated, time: .shortened))
                            Text(article.url.absoluteString)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        HStack {
                            Button(article.isStarred ? "Unstar" : "Star", systemImage: article.isStarred ? "star.slash" : "star") {
                                save { article.isStarred.toggle() }
                            }

                            Button(article.isRead ? "Mark Unread" : "Mark Read", systemImage: article.isRead ? "circle" : "checkmark.circle") {
                                save { article.isRead.toggle() }
                            }

                            Button(article.isHidden ? "Unhide" : "Hide", systemImage: article.isHidden ? "eye" : "eye.slash") {
                                save { article.isHidden.toggle() }
                            }

                            Link(destination: article.url) {
                                Label("Open Original", systemImage: "safari")
                            }
                        }

                        Divider()

                        Text(article.contentText ?? article.excerpt ?? "Open the original article to read the full post.")
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                    .padding(24)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Select an Article", systemImage: "doc.text")
            }
        }
    }

    private func save(_ change: () -> Void) {
        change()
        try? modelContext.save()
    }
}

