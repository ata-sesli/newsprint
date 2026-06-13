import AppKit
import SwiftUI
import newsprintCore

struct ArticleFeedView: View {
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.articleListDensity) private var density
    let articles: [Article]
    let allArticles: [Article]
    let sources: [Source]
    @Binding var selection: SidebarSelection
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding
    @Binding var expandedArticleID: String?
    @Binding var focusedArticleID: String?
    let onArticleAction: (Article, ArticleStateMutation) -> Void

    var body: some View {
        VStack(spacing: 0) {
            FeedControlHeader(
                articles: allArticles,
                sources: sources,
                selection: $selection,
                searchText: $searchText,
                searchFocused: searchFocused
            )
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .background(theme.paneBackground)

            Divider()

            ScrollView {
                LazyVStack(spacing: density.rowVerticalPadding + 10) {
                    ForEach(articles) { article in
                        ArticleFeedCard(
                            article: article,
                            isExpanded: expandedArticleID == article.id,
                            onToggleExpanded: {
                                focusedArticleID = article.id
                                expandedArticleID = expandedArticleID == article.id ? nil : article.id
                            },
                            onArticleAction: onArticleAction
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
            }
            .overlay {
                if articles.isEmpty {
                    ContentUnavailableView("No Articles", systemImage: "newspaper", description: Text("Add a source and refresh to read locally."))
                }
            }
            .background(theme.paneBackground)
        }
        .background(theme.paneBackground)
        .navigationTitle("Feed")
    }
}

struct ArticleFeedCard: View {
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.readerFontChoice) private var readerFontChoice
    @Environment(\.readerFontSize) private var readerFontSize
    @Environment(\.articleListDensity) private var density
    let article: Article
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onArticleAction: (Article, ArticleStateMutation) -> Void

    private var hackerNewsMetadata: HackerNewsMetadata? {
        HackerNewsMetadata(text: article.contentText ?? article.excerpt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density.rowSpacing) {
            cardHeader

            if let previewText {
                Text(previewText)
                    .font(.system(size: CGFloat(readerFontSize), design: readerFontChoice.fontDesign))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .lineLimit(isExpanded ? nil : density.previewLineLimit)
            }

            if !article.tagNames.isEmpty {
                tagRow
            }

            if isExpanded {
                Divider()
                    .padding(.vertical, 4)

                ExpandedArticleContent(
                    article: article,
                    hackerNewsMetadata: hackerNewsMetadata
                )

                expandedActions
                .padding(.top, 4)
            }
        }
        .padding(density.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.readerSurface, in: RoundedRectangle(cornerRadius: density.cardCornerRadius))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(article.isRead ? Color.clear : theme.rowAccent)
                .frame(width: isExpanded ? 5 : 3)
                .padding(.vertical, density.cardPadding)
        }
        .overlay {
            RoundedRectangle(cornerRadius: density.cardCornerRadius)
                .stroke(isExpanded ? theme.rowAccent.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.25), lineWidth: isExpanded ? 1.4 : 1)
        }
        .shadow(color: .black.opacity(isExpanded ? 0.10 : 0.04), radius: isExpanded ? 12 : 4, y: isExpanded ? 5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: density.cardCornerRadius))
        .onTapGesture(perform: onToggleExpanded)
        .contextMenu {
            ArticleContextMenu(article: article, hackerNewsMetadata: hackerNewsMetadata)
        }
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: density.rowSpacing) {
            HStack(spacing: 8) {
                if hackerNewsMetadata != nil {
                    HackerNewsBadge()
                }

                Text(metadata)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.metadata)

                if article.isStarred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }

                if article.isHidden {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.metadata)
            }

            Text(article.title)
                .font(.system(size: CGFloat(readerFontSize) * density.titleScale, weight: article.isRead ? .medium : .semibold, design: readerFontChoice.fontDesign))
                .foregroundStyle(article.isRead ? .secondary : .primary)
                .lineLimit(isExpanded ? nil : 3)

            if let hackerNewsMetadata {
                HackerNewsStatLabels(metadata: hackerNewsMetadata)
            }
        }
    }

    private var metadata: String {
        var parts = [article.sourceTitle]
        if let author = article.author, !author.isEmpty {
            parts.append(author)
        }
        parts.append((article.publishedAt ?? article.fetchedAt).formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }

    private var previewText: String? {
        guard hackerNewsMetadata == nil else {
            return nil
        }
        return (article.contentText ?? article.excerpt)?.nilIfBlank
    }

    private var tagRow: some View {
        HStack {
            ForEach(article.tagNames, id: \.self) { tag in
                Label(tag, systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var expandedActions: some View {
        HStack {
            Button(article.isStarred ? "Unstar" : "Star", systemImage: article.isStarred ? "star.slash" : "star") {
                onArticleAction(article, .toggleStar)
            }

            Button(article.isRead ? "Mark Unread" : "Mark Read", systemImage: article.isRead ? "circle" : "checkmark.circle") {
                onArticleAction(article, .toggleRead)
            }

            Button(article.isHidden ? "Unhide" : "Hide", systemImage: article.isHidden ? "eye" : "eye.slash") {
                onArticleAction(article, .toggleHidden)
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
}

struct ExpandedArticleContent: View {
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.readerFontChoice) private var readerFontChoice
    @Environment(\.readerFontSize) private var readerFontSize
    @Environment(\.articleListDensity) private var density
    let article: Article
    let hackerNewsMetadata: HackerNewsMetadata?

    var body: some View {
        VStack(alignment: .leading, spacing: density.expandedContentSpacing) {
            if let bodyText = articleBodyText {
                Text(bodyText)
                    .font(.system(size: CGFloat(readerFontSize), design: readerFontChoice.fontDesign))
                    .lineSpacing(6)
                    .textSelection(.enabled)
            }

            if let authorComment = hackerNewsMetadata?.authorComment {
                authorCommentBlock(authorComment)
            } else if articleBodyText == nil {
                Text("Open the original article for the full post.")
                    .font(.system(size: CGFloat(readerFontSize), design: readerFontChoice.fontDesign))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var articleBodyText: String? {
        guard hackerNewsMetadata == nil else {
            return nil
        }
        return (article.contentText ?? article.excerpt)?.nilIfBlank
    }

    private func authorCommentBlock(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 2)
                .fill(theme.rowAccent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                Label("Author Comment", systemImage: "text.quote")
                    .font(.headline)
                Text(text)
                    .font(.system(size: CGFloat(readerFontSize), design: readerFontChoice.fontDesign))
                    .lineSpacing(6)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .background(theme.rowAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct FeedControlHeader: View {
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.articleListDensity) private var density
    let articles: [Article]
    let sources: [Source]
    @Binding var selection: SidebarSelection
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding

    private var summary: TodaySummary {
        TodaySummaryBuilder().summary(articles: articles, sources: sources, frontPageLimit: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density.summarySpacing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(.title2.weight(.semibold))
                    Text("Search and filter the feed without leaving the reading surface.")
                        .font(.callout)
                        .foregroundStyle(theme.metadata)
                }

                Spacer()

                HStack {
                    Button("Refresh All", systemImage: "arrow.clockwise") {
                        NotificationCenter.default.post(name: .newsprintRefreshAll, object: nil)
                    }
                    Button("Add Source", systemImage: "plus") {
                        NotificationCenter.default.post(name: .newsprintAddSource, object: nil)
                    }
                    Button("Search", systemImage: "magnifyingglass") {
                        searchFocused.wrappedValue = true
                    }
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                SummaryPill(title: "Today", value: summary.todayCount, systemImage: "calendar")
                SummaryPill(title: "Unread", value: summary.unreadCount, systemImage: "circle")
                SummaryPill(title: "Starred", value: summary.starredCount, systemImage: "star")
                SummaryPill(title: "Hidden", value: summary.hiddenCount, systemImage: "eye.slash")
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    searchField
                    filterChips
                }

                VStack(alignment: .leading, spacing: 10) {
                    searchField
                    filterChips
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.metadata)

            TextField("Search articles", text: $searchText)
                .textFieldStyle(.plain)
                .focused(searchFocused)
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.metadata)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minWidth: 260)
        .background(theme.readerSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.25))
        }
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(FeedFilterChip.quickFilters) { filter in
                Button {
                    selection = filter.selection
                } label: {
                    Label(filter.title, systemImage: filter.systemImage)
                }
                .buttonStyle(FilterChipButtonStyle(isSelected: selection == filter.selection))
            }

            sourcePicker

            if let contextualFilter {
                HStack(spacing: 6) {
                    Label(contextualFilter, systemImage: "line.3.horizontal.decrease.circle")
                    Button {
                        selection = .inbox
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Clear Filter")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(theme.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var sourcePicker: some View {
        Menu {
            Button {
                selection = .inbox
            } label: {
                Label("All Sources", systemImage: "tray")
            }

            if !sources.isEmpty {
                Divider()
            }

            ForEach(sources) { source in
                Button {
                    selection = .source(source.id)
                } label: {
                    Label(
                        source.title,
                        systemImage: source.enabled ? "dot.radiowaves.left.and.right" : "pause.circle"
                    )
                }
            }
        } label: {
            Label(sourcePickerTitle, systemImage: "dot.radiowaves.left.and.right")
        }
        .menuStyle(.button)
        .buttonStyle(FilterChipButtonStyle(isSelected: isSourceFilterSelected))
    }

    private var contextualFilter: String? {
        switch selection {
        case .tag(let tag):
            return "Tag: \(tag)"
        case .inbox, .unread, .today, .starred, .hidden, .source, .sources, .rules, .settings:
            return nil
        }
    }

    private var isSourceFilterSelected: Bool {
        if case .source = selection {
            return true
        }
        return false
    }

    private var sourcePickerTitle: String {
        guard case .source(let id) = selection,
              let source = sources.first(where: { $0.id == id }) else {
            return "All Sources"
        }
        return source.title
    }
}

private struct FeedFilterChip: Identifiable {
    let id: SidebarSelection
    let title: String
    let systemImage: String
    let selection: SidebarSelection

    static let quickFilters = [
        FeedFilterChip(id: .inbox, title: "Inbox", systemImage: "tray", selection: .inbox),
        FeedFilterChip(id: .unread, title: "Unread", systemImage: "circle", selection: .unread),
        FeedFilterChip(id: .today, title: "Today", systemImage: "calendar", selection: .today),
        FeedFilterChip(id: .starred, title: "Starred", systemImage: "star", selection: .starred),
        FeedFilterChip(id: .hidden, title: "Hidden", systemImage: "eye.slash", selection: .hidden)
    ]
}

private struct FilterChipButtonStyle: ButtonStyle {
    @Environment(\.newsprintTheme) private var theme
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .foregroundStyle(isSelected ? Color.white : theme.metadata)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(background(configuration: configuration), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private func background(configuration: Configuration) -> Color {
        if isSelected {
            return theme.tint
        }
        if configuration.isPressed {
            return theme.readerSurface.opacity(0.7)
        }
        return theme.readerSurface
    }

    private var borderColor: Color {
        isSelected ? theme.tint.opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.25)
    }
}

private struct SummaryPill: View {
    @Environment(\.newsprintTheme) private var theme
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.tint)
            Text("\(value)")
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(theme.metadata)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.readerSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.25))
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
