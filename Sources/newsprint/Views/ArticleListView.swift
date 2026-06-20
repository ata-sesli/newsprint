import AppKit
import SwiftUI
import newsprintCore

struct ArticleFeedView: View {
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.readerFontChoice) private var readerFontChoice
    @Environment(\.readerFontSize) private var readerFontSize
    @Environment(\.articleListDensity) private var density
    let displayItems: [ArticleFeedDisplayItem]
    let counts: FeedCounts
    let sources: [Source]
    let pendingRefreshSummary: FeedRefreshSummary?
    @Binding var selection: SidebarSelection
    @Binding var searchText: String
    @Binding var feedSort: ArticleFeedSort
    @Binding var feedKindFilter: ArticleFeedKindFilter
    var searchFocused: FocusState<Bool>.Binding
    @Binding var expandedArticleID: String?
    @Binding var focusedArticleID: String?
    let isLoading: Bool
    let isPreparingFeed: Bool
    let isRefreshing: Bool
    let isActive: Bool
    let hasLoadedInitialPage: Bool
    let previewArticle: ArticleFeedDisplayItem?
    @Binding var previewArticleID: String?
    @Binding var previewMode: PreviewMode
    @Binding var isPreviewCollapsed: Bool
    @State private var didLogFirstAppearance = false
    let reloadGeneration: Int
    let edgeResetGeneration: Int
    let onNearEnd: (Int) -> Void
    let cleanHome: () -> Void
    let applyPendingRefresh: () -> Void
    let dismissPendingRefresh: () -> Void
    let onArticleAction: (String, ArticleStateMutation) -> Void

    var body: some View {
        ArticleReadingSplitView(isPreviewCollapsed: $isPreviewCollapsed) {
            feedContent
        } preview: {
            ArticlePreviewPane(
                article: previewArticle,
                previewMode: $previewMode,
                isCollapsed: $isPreviewCollapsed
            )
        }
        .navigationTitle("Feed")
        .onAppear {
            guard !didLogFirstAppearance else { return }
            didLogFirstAppearance = true
            NewsprintLog.startup.info("First feed view appeared")
        }
    }

    private var feedContent: some View {
        VStack(spacing: 0) {
            FeedControlHeader(
                counts: counts,
                sources: sources,
                pendingRefreshSummary: pendingRefreshSummary,
                selection: $selection,
                searchText: $searchText,
                feedSort: $feedSort,
                feedKindFilter: $feedKindFilter,
                isPreviewCollapsed: $isPreviewCollapsed,
                isRefreshing: isRefreshing,
                searchFocused: searchFocused,
                cleanHome: cleanHome,
                applyPendingRefresh: applyPendingRefresh,
                dismissPendingRefresh: dismissPendingRefresh
            )
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .background(theme.paneBackground)

            Divider()

            ZStack {
                if showsInitialLoadingState {
                    FeedLoadingPlaceholder()
                } else {
                    ArticleFeedCollectionView(
                        items: displayItems,
                        expandedArticleID: expandedArticleID,
                        appearance: ArticleFeedAppearance(
                            theme: theme,
                            readerFontChoice: readerFontChoice,
                            readerFontSize: readerFontSize,
                            density: density
                        ),
                        isActive: isActive,
                        reloadGeneration: reloadGeneration,
                        edgeResetGeneration: edgeResetGeneration,
                        onToggleExpanded: { item in
                            focusedArticleID = item.id
                            expandedArticleID = expandedArticleID == item.id ? nil : item.id
                        },
                        onOpenInPreview: { item in
                            focusedArticleID = item.id
                            previewArticleID = item.id
                            isPreviewCollapsed = false
                        },
                        onNearEnd: onNearEnd,
                        onArticleAction: onArticleAction
                    )
                    .overlay {
                        if showsEmptyState {
                            ContentUnavailableView("No Articles", systemImage: "newspaper", description: Text("Add a source and refresh to read locally."))
                        }
                    }
                }
            }
            .background(theme.paneBackground)
        }
        .background(theme.paneBackground)
    }

    private var showsInitialLoadingState: Bool {
        isPreparingFeed || (!hasLoadedInitialPage && displayItems.isEmpty)
    }

    private var showsEmptyState: Bool {
        hasLoadedInitialPage && !isLoading && displayItems.isEmpty
    }
}

private struct FeedLoadingPlaceholder: View {
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.articleListDensity) private var density

    var body: some View {
        ScrollView {
            LazyVStack(spacing: density.rowVerticalPadding + 10) {
                ForEach(0..<5, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(theme.tint.opacity(0.30))
                                .frame(width: 42, height: 28)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.metadata.opacity(0.18))
                                .frame(width: CGFloat(230 + (index % 2) * 80), height: 16)
                            Spacer()
                        }

                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.metadata.opacity(0.20))
                            .frame(height: 34)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.metadata.opacity(0.14))
                            .frame(width: 520, height: 26)
                    }
                    .padding(density.cardPadding)
                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
                    .background(theme.readerSurface, in: RoundedRectangle(cornerRadius: density.cardCornerRadius))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.rowAccent.opacity(0.55))
                            .frame(width: 3)
                            .padding(.vertical, density.cardPadding)
                    }
                    .opacity(0.72)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
        }
        .disabled(true)
    }
}

struct ArticleFeedCard: View {
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.readerFontChoice) private var readerFontChoice
    @Environment(\.readerFontSize) private var readerFontSize
    @Environment(\.articleListDensity) private var density
    let article: ArticleFeedDisplayItem
    let isExpanded: Bool
    let hackerNewsMetadata: HackerNewsMetadata?
    let metadataText: String
    let previewText: String?
    let onToggleExpanded: () -> Void
    let onOpenInPreview: () -> Void
    let onArticleAction: (String, ArticleStateMutation) -> Void

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
            Button(article.isStarred ? "Unstar" : "Star", systemImage: article.isStarred ? "star.slash" : "star") {
                onArticleAction(article.id, .toggleStar)
            }

            Button(article.isRead ? "Mark Unread" : "Mark Read", systemImage: article.isRead ? "circle" : "checkmark.circle") {
                onArticleAction(article.id, .toggleRead)
            }

            Button(article.isHidden ? "Unhide" : "Hide", systemImage: article.isHidden ? "eye" : "eye.slash") {
                onArticleAction(article.id, .toggleHidden)
            }

            Divider()

            Button("Open Original", systemImage: "safari") {
                NSWorkspace.shared.open(article.previewURL)
            }

            if let threadURL = hackerNewsMetadata?.threadURL {
                Button("Open HN Thread", systemImage: "bubble.left.and.bubble.right") {
                    NSWorkspace.shared.open(threadURL)
                }
            }

            Button("Copy Link", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(article.previewURL.absoluteString, forType: .string)
            }
        }
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: density.rowSpacing) {
            HStack(spacing: 8) {
                if hackerNewsMetadata != nil {
                    HackerNewsBadge(
                        fontSize: metadataFontSize * 0.78,
                        padding: density.metadataBadgePadding
                    )
                }

                Text(metadataText)
                    .font(.system(size: metadataFontSize, weight: .semibold, design: readerFontChoice.fontDesign))
                    .foregroundStyle(theme.metadata)

                Button {
                    onOpenInPreview()
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: metadataFontSize * 1.10, weight: .bold, design: .rounded))
                        .frame(width: metadataIconFrame, height: metadataIconFrame)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.tint)
                .help("Open in Side")

                if article.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: metadataFontSize, weight: .semibold))
                        .foregroundStyle(.yellow)
                }

                if article.isHidden {
                    Image(systemName: "eye.slash")
                        .font(.system(size: metadataFontSize, weight: .semibold))
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

    private var metadataFontSize: CGFloat {
        max(12, CGFloat(readerFontSize) * density.metadataScale)
    }

    private var metadataIconFrame: CGFloat {
        max(24, CGFloat(readerFontSize) * density.metadataIconScale)
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
                    onArticleAction(article.id, .toggleStar)
            }

            Button(article.isRead ? "Mark Unread" : "Mark Read", systemImage: article.isRead ? "circle" : "checkmark.circle") {
                    onArticleAction(article.id, .toggleRead)
            }

            Button(article.isHidden ? "Unhide" : "Hide", systemImage: article.isHidden ? "eye" : "eye.slash") {
                    onArticleAction(article.id, .toggleHidden)
            }

            Button("Open Original", systemImage: "safari") {
                NSWorkspace.shared.open(article.previewURL)
            }

            if let threadURL = hackerNewsMetadata?.threadURL {
                Button("Open HN Thread", systemImage: "bubble.left.and.bubble.right") {
                    NSWorkspace.shared.open(threadURL)
                }
            }

            Button("Copy Link", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(article.previewURL.absoluteString, forType: .string)
            }
        }
    }
}

struct ExpandedArticleContent: View {
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.readerFontChoice) private var readerFontChoice
    @Environment(\.readerFontSize) private var readerFontSize
    @Environment(\.articleListDensity) private var density
    let article: ArticleFeedDisplayItem
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
        guard let bodyText = HTMLTextExtractor.text(fromHTML: article.contentText ?? article.excerpt)?.nilIfBlank else {
            return nil
        }
        if let previewText = article.previewText?.nilIfBlank,
           bodyText.normalizedArticleText == previewText.normalizedArticleText {
            return nil
        }
        return bodyText
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
    let counts: FeedCounts
    let sources: [Source]
    let pendingRefreshSummary: FeedRefreshSummary?
    @Binding var selection: SidebarSelection
    @Binding var searchText: String
    @Binding var feedSort: ArticleFeedSort
    @Binding var feedKindFilter: ArticleFeedKindFilter
    @Binding var isPreviewCollapsed: Bool
    let isRefreshing: Bool
    var searchFocused: FocusState<Bool>.Binding
    let cleanHome: () -> Void
    let applyPendingRefresh: () -> Void
    let dismissPendingRefresh: () -> Void
    @State private var isConfirmingCleanHome = false

    private var usesCompactControls: Bool {
        !isPreviewCollapsed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density.summarySpacing) {
            HStack(alignment: .top) {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timeline.date.formatted(.dateTime.hour().minute()))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(timeline.date.formatted(.dateTime.month(.wide).day().year()))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(theme.metadata)
                    }
                }

                Spacer()

                HStack {
                    Button {
                        NotificationCenter.default.post(name: .newsprintRefreshAll, object: nil)
                    } label: {
                        refreshHeaderLabel
                    }
                    .buttonStyle(HeaderActionButtonStyle())
                    .disabled(isRefreshing)
                    .help("Refresh All")

                    Button(role: .destructive) {
                        isConfirmingCleanHome = true
                    } label: {
                        headerLabel("Clean Home", systemImage: "trash")
                    }
                    .buttonStyle(HeaderActionButtonStyle())
                    .disabled(isRefreshing)
                    .help("Remove all non-starred articles")

                    Button {
                        isPreviewCollapsed.toggle()
                    } label: {
                        headerLabel(isPreviewCollapsed ? "Show Preview" : "Hide Preview", systemImage: "sidebar.right")
                    }
                    .buttonStyle(HeaderActionButtonStyle())
                    .help(isPreviewCollapsed ? "Show Preview" : "Hide Preview")
                }
            }

            HStack(spacing: 10) {
                SummaryPill(title: "Today", value: counts.today, systemImage: "calendar", isCompact: usesCompactControls)
                SummaryPill(title: "Unread", value: counts.unread, systemImage: "circle", isCompact: usesCompactControls)
                SummaryPill(title: "Starred", value: counts.starred, systemImage: "star", isCompact: usesCompactControls)
                SummaryPill(title: "Hidden", value: counts.hidden, systemImage: "eye.slash", isCompact: usesCompactControls)
            }

            if let pendingRefreshSummary {
                PendingFeedUpdateBanner(
                    summary: pendingRefreshSummary,
                    apply: applyPendingRefresh,
                    dismiss: dismissPendingRefresh
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    searchField
                    sortChips
                    filterChips
                }

                VStack(alignment: .leading, spacing: 10) {
                    searchField
                    HStack(spacing: 8) {
                        sortChips
                        filterChips
                    }
                }
            }
        }
        .confirmationDialog(
            "Clean Home?",
            isPresented: $isConfirmingCleanHome,
            titleVisibility: .visible
        ) {
            Button("Clean Home", role: .destructive) {
                cleanHome()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all non-starred articles. Starred articles are kept.")
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
                    chipLabel(filter.title, systemImage: filter.systemImage)
                }
                .buttonStyle(FilterChipButtonStyle(isSelected: selection == filter.selection))
                .help(filter.title)
            }

            sourcePicker

            Button {
                if feedKindFilter == .hackerNews {
                    feedKindFilter = .all
                } else {
                    if case .source = selection {
                        selection = .inbox
                    }
                    feedKindFilter = .hackerNews
                }
            } label: {
                chipLabel("HN", systemImage: "text.bubble")
            }
            .buttonStyle(FilterChipButtonStyle(isSelected: feedKindFilter == .hackerNews))
            .help(feedKindFilter == .hackerNews ? "Show all sources" : "Show Hacker News")

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

    private var sortChips: some View {
        HStack(spacing: 8) {
            ForEach(ArticleFeedSort.allCases) { sort in
                Button {
                    feedSort = sort
                } label: {
                    chipLabel(sort.displayName, systemImage: sort == .hot ? "flame" : "clock")
                }
                .buttonStyle(FilterChipButtonStyle(isSelected: feedSort == sort))
                .help(sort.displayName)
            }
        }
    }

    private var sourcePicker: some View {
        let homeSources = SourceDisplayItemBuilder.homeSourceRows(for: sources)
        return Menu {
            Button {
                feedKindFilter = .all
                selection = .inbox
            } label: {
                Label("All Sources", systemImage: "tray")
            }

            if !homeSources.isEmpty {
                Divider()
            }

            ForEach(homeSources) { source in
                Button {
                    feedKindFilter = .all
                    selection = .source(source.id)
                } label: {
                    Label(
                        source.title,
                        systemImage: source.enabled ? "dot.radiowaves.left.and.right" : "pause.circle"
                    )
                }
            }
        } label: {
            chipLabel(sourcePickerTitle, systemImage: "dot.radiowaves.left.and.right")
        }
        .menuStyle(.button)
        .buttonStyle(FilterChipButtonStyle(isSelected: isSourceFilterSelected))
        .help(sourcePickerTitle)
    }

    @ViewBuilder
    private func chipLabel(_ title: String, systemImage: String) -> some View {
        if usesCompactControls {
            Image(systemName: systemImage)
                .accessibilityLabel(title)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private func headerLabel(_ title: String, systemImage: String) -> some View {
        if usesCompactControls {
            Image(systemName: systemImage)
                .accessibilityLabel(title)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private var refreshHeaderLabel: some View {
        if usesCompactControls {
            RotatingRefreshIcon(isRefreshing: isRefreshing)
                .accessibilityLabel("Refresh All")
        } else {
            HStack(spacing: 6) {
                RotatingRefreshIcon(isRefreshing: isRefreshing)
                Text("Refresh All")
            }
        }
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
              let source = SourceDisplayItemBuilder.homeSourceRows(for: sources).first(where: { $0.id == id }) else {
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

private struct PendingFeedUpdateBanner: View {
    @Environment(\.newsprintTheme) private var theme
    let summary: FeedRefreshSummary
    let apply: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.tint)

            Text(message)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Button("Update Feed", systemImage: "arrow.triangle.2.circlepath") {
                apply()
            }
            .buttonStyle(HeaderActionButtonStyle())

            Button("Dismiss", systemImage: "xmark") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.metadata)
            .help("Keep the current feed unchanged")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.tint.opacity(0.26))
        }
    }

    private var message: String {
        if summary.insertedCount > 0 {
            "\(summary.insertedCount) new article\(summary.insertedCount == 1 ? "" : "s") ready"
        } else {
            "Feed update ready"
        }
    }
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

private struct RotatingRefreshIcon: View {
    let isRefreshing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isRefreshing)) { timeline in
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(rotationDegrees(for: timeline.date)))
        }
    }

    private func rotationDegrees(for date: Date) -> Double {
        guard isRefreshing else { return 0 }
        return date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 1.0) * 360
    }
}

private struct HeaderActionButtonStyle: ButtonStyle {
    @Environment(\.newsprintTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(background(configuration: configuration), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.tint.opacity(configuration.isPressed ? 0.50 : 0.32), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.84 : 1)
    }

    private func background(configuration: Configuration) -> Color {
        configuration.isPressed ? theme.tint.opacity(0.18) : theme.tint.opacity(0.10)
    }
}

private struct SummaryPill: View {
    @Environment(\.newsprintTheme) private var theme
    let title: String
    let value: Int
    let systemImage: String
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.tint)
            Text("\(value)")
                .font(.headline)
                .monospacedDigit()
            if !isCompact {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(theme.metadata)
            }
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

    var normalizedArticleText: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
