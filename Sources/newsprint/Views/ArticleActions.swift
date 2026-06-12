import AppKit
import SwiftData
import SwiftUI
import newsprintCore

struct ArticleActionButtons: View {
    @Environment(\.modelContext) private var modelContext
    let article: Article
    let hackerNewsMetadata: HackerNewsMetadata?

    var body: some View {
        Group {
            Button(article.isStarred ? "Unstar" : "Star", systemImage: article.isStarred ? "star.slash" : "star") {
                save { article.isStarred.toggle() }
            }

            Button(article.isRead ? "Mark Unread" : "Mark Read", systemImage: article.isRead ? "circle" : "checkmark.circle") {
                save { article.isRead.toggle() }
            }

            Button(article.isHidden ? "Unhide" : "Hide", systemImage: article.isHidden ? "eye" : "eye.slash") {
                save { article.isHidden.toggle() }
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

    private func save(_ change: () -> Void) {
        change()
        try? modelContext.save()
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
    var body: some View {
        Text("HN")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.orange, in: RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel("Hacker News")
    }
}

struct HackerNewsStatLabels: View {
    let metadata: HackerNewsMetadata

    var body: some View {
        HStack(spacing: 10) {
            if let points = metadata.points {
                Label("\(points) \(points == 1 ? "point" : "points")", systemImage: "arrowtriangle.up.fill")
            }

            if let commentCount = metadata.commentCount {
                Label("\(commentCount) \(commentCount == 1 ? "comment" : "comments")", systemImage: "text.bubble")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

