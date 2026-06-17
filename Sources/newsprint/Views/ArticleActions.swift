import AppKit
import SwiftData
import SwiftUI
import newsprintCore

struct ArticleActionButtons: View {
    @Environment(\.modelContext) private var modelContext
    let article: Article
    let hackerNewsMetadata: HackerNewsMetadata?
    var onSaveError: (String) -> Void = { _ in }

    var body: some View {
        Group {
            Button(article.isStarred ? "Unstar" : "Star", systemImage: article.isStarred ? "star.slash" : "star") {
                save(.toggleStar)
            }

            Button(article.isRead ? "Mark Unread" : "Mark Read", systemImage: article.isRead ? "circle" : "checkmark.circle") {
                save(.toggleRead)
            }

            Button(article.isHidden ? "Unhide" : "Hide", systemImage: article.isHidden ? "eye" : "eye.slash") {
                save(.toggleHidden)
            }

            Button("Open Original", systemImage: "safari") {
                NSWorkspace.shared.open(article.url)
            }

            if let threadURL = hackerNewsMetadata?.threadURL {
                Button("Open HN Thread", systemImage: "bubble.left.and.bubble.right") {
                    NSWorkspace.shared.open(threadURL)
                }
            }

            Button("Copy Link", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(article.url.absoluteString, forType: .string)
            }
        }
    }

    private func save(_ mutation: ArticleStateMutation) {
        let snapshot = ArticleStateSnapshot(article: article)
        do {
            try mutation.apply(
                to: article,
                repository: SwiftDataArticleRepository(context: modelContext)
            )
            onSaveError("")
        } catch {
            snapshot.restore(article)
            onSaveError("Could not save article: \(error.localizedDescription)")
        }
    }
}

struct ArticleContextMenu: View {
    let article: Article
    let hackerNewsMetadata: HackerNewsMetadata?

    var body: some View {
        ArticleActionButtons(article: article, hackerNewsMetadata: hackerNewsMetadata)
    }
}

struct HackerNewsBadge: View {
    var fontSize: CGFloat = 11
    var padding: EdgeInsets = EdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5)

    var body: some View {
        Text("HN")
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(padding)
            .background(Color.orange, in: RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel("Hacker News")
    }
}

struct HackerNewsStatLabels: View {
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.readerFontSize) private var readerFontSize
    let metadata: HackerNewsMetadata

    var body: some View {
        HStack(spacing: 14) {
            if let points = metadata.points {
                HackerNewsStatBadge(
                    value: points,
                    systemImage: "arrowtriangle.up.fill",
                    accessibilityLabel: "\(points) \(points == 1 ? "point" : "points")",
                    fontSize: statFontSize
                )
            }

            if let commentCount = metadata.commentCount {
                HackerNewsStatBadge(
                    value: commentCount,
                    systemImage: "text.bubble",
                    accessibilityLabel: "\(commentCount) \(commentCount == 1 ? "comment" : "comments")",
                    fontSize: statFontSize
                )
            }
        }
    }

    private var statFontSize: CGFloat {
        max(17, CGFloat(readerFontSize) * 1.12)
    }
}

private struct HackerNewsStatBadge: View {
    @Environment(\.newsprintTheme) private var theme
    let value: Int
    let systemImage: String
    let accessibilityLabel: String
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: fontSize, weight: .semibold))
            Text("\(value)")
                .font(.system(size: fontSize, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(theme.metadata)
        .accessibilityLabel(accessibilityLabel)
    }
}
