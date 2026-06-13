import SwiftUI
import newsprintCore

struct TodaySummaryView: View {
    @Environment(\.newsprintTheme) private var theme
    let articles: [Article]
    let sources: [Source]
    @Binding var selectedArticle: Article?

    private var summary: TodaySummary {
        TodaySummaryBuilder().summary(articles: articles, sources: sources)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                metrics
                frontPage
                sourceHealth
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.readerBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.largeTitle.weight(.semibold))

            Text("Front Page gathers the highest-ranked unread articles and a quick pulse of source health.")
                .foregroundStyle(theme.metadata)

            HStack {
                Button("Refresh All", systemImage: "arrow.clockwise") {
                    NotificationCenter.default.post(name: .newsprintRefreshAll, object: nil)
                }

                Button("Add Source", systemImage: "plus") {
                    NotificationCenter.default.post(name: .newsprintAddSource, object: nil)
                }

                Button("Search", systemImage: "magnifyingglass") {
                    NotificationCenter.default.post(name: .newsprintFocusSearch, object: nil)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var metrics: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                SummaryMetric(title: "Today", value: summary.todayCount, systemImage: "calendar")
                SummaryMetric(title: "Unread", value: summary.unreadCount, systemImage: "circle")
            }
            GridRow {
                SummaryMetric(title: "Starred", value: summary.starredCount, systemImage: "star")
                SummaryMetric(title: "Hidden", value: summary.hiddenCount, systemImage: "eye.slash")
            }
        }
    }

    private var frontPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Front Page", systemImage: "newspaper")
                .font(.title3.weight(.semibold))

            if summary.frontPage.isEmpty {
                ContentUnavailableView("No unread articles", systemImage: "checkmark.circle", description: Text("Refresh sources or add a new feed."))
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                VStack(spacing: 0) {
                    ForEach(summary.frontPage) { article in
                        Button {
                            selectedArticle = article
                        } label: {
                            FrontPageRow(article: article)
                        }
                        .buttonStyle(.plain)

                        if article.id != summary.frontPage.last?.id {
                            Divider()
                        }
                    }
                }
                .background(theme.readerSurface, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.35))
                }
            }
        }
    }

    private var sourceHealth: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recent Sources", systemImage: "dot.radiowaves.left.and.right")
                .font(.title3.weight(.semibold))

            if summary.recentSources.isEmpty {
                ContentUnavailableView("No sources yet", systemImage: "plus.circle", description: Text("Add a source to start reading."))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(summary.recentSources) { source in
                        SourceHealthRow(source: source)
                        if source.id != summary.recentSources.last?.id {
                            Divider()
                        }
                    }
                }
                .background(theme.readerSurface, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.35))
                }
            }
        }
    }
}

private struct SummaryMetric: View {
    @Environment(\.newsprintTheme) private var theme
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.title2.weight(.semibold))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(theme.metadata)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(theme.readerSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.35))
        }
    }
}

private struct FrontPageRow: View {
    @Environment(\.newsprintTheme) private var theme
    let article: Article

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(theme.rowAccent)
                .frame(width: 7, height: 7)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 5) {
                Text(article.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("\(article.sourceTitle) · \((article.publishedAt ?? article.fetchedAt).formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(theme.metadata)

                if let excerpt = article.contentText ?? article.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}

private struct SourceHealthRow: View {
    @Environment(\.newsprintTheme) private var theme
    let source: Source

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: source.lastErrorMessage == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(source.lastErrorMessage == nil ? .green : .orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(source.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(theme.metadata)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var statusText: String {
        if let lastErrorMessage = source.lastErrorMessage, !lastErrorMessage.isEmpty {
            return lastErrorMessage
        }

        if let lastSuccessfulFetchAt = source.lastSuccessfulFetchAt {
            return "Last updated \(lastSuccessfulFetchAt.formatted(date: .abbreviated, time: .shortened))"
        }

        return "Waiting for first refresh"
    }
}
