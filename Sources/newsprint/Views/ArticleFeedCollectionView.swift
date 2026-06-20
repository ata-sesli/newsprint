import AppKit
import SwiftUI
import newsprintCore

struct ArticleFeedCollectionView: NSViewRepresentable {
    let items: [ArticleFeedDisplayItem]
    let expandedArticleID: String?
    let appearance: ArticleFeedAppearance
    let isActive: Bool
    let reloadGeneration: Int
    let edgeResetGeneration: Int
    let onToggleExpanded: (ArticleFeedDisplayItem) -> Void
    let onOpenInPreview: (ArticleFeedDisplayItem) -> Void
    let onNearEnd: (Int) -> Void
    let onArticleAction: (String, ArticleStateMutation) -> Void

    func makeCoordinator() -> ArticleFeedCollectionCoordinator {
        ArticleFeedCollectionCoordinator(
            items: items,
            expandedArticleID: expandedArticleID,
            appearance: appearance,
            isActive: isActive,
            reloadGeneration: reloadGeneration,
            edgeResetGeneration: edgeResetGeneration,
            onToggleExpanded: onToggleExpanded,
            onOpenInPreview: onOpenInPreview,
            onNearEnd: onNearEnd,
            onArticleAction: onArticleAction
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = appearance.density.rowVerticalPadding + 10
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = NSEdgeInsets(top: 18, left: 14, bottom: 18, right: 14)

        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        collectionView.autoresizingMask = [.width]
        collectionView.register(
            ArticleFeedCollectionItem.self,
            forItemWithIdentifier: ArticleFeedCollectionItem.reuseIdentifier
        )

        context.coordinator.collectionView = collectionView
        context.coordinator.layout = layout

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = collectionView
        scrollView.contentView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(ArticleFeedCollectionCoordinator.clipViewBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            items: items,
            expandedArticleID: expandedArticleID,
            appearance: appearance,
            isActive: isActive,
            reloadGeneration: reloadGeneration,
            edgeResetGeneration: edgeResetGeneration,
            onToggleExpanded: onToggleExpanded,
            onOpenInPreview: onOpenInPreview,
            onNearEnd: onNearEnd,
            onArticleAction: onArticleAction
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: ArticleFeedCollectionCoordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }
}

@MainActor
final class ArticleFeedCollectionCoordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    weak var collectionView: NSCollectionView?
    weak var layout: NSCollectionViewFlowLayout?
    private var items: [ArticleFeedDisplayItem]
    private var expandedArticleID: String?
    private var appearance: ArticleFeedAppearance
    private var isActive: Bool
    private var reloadGeneration: Int
    private var edgeResetGeneration: Int
    private var needsReloadOnActivation = false
    private var shouldScrollToTopOnActivation = false
    private let heightCache = ArticleFeedHeightCache()
    private var lastLayoutWidth: CGFloat = 0
    private var edgeReporter = ArticleRenderWindowEdgeReporter()
    private var onToggleExpanded: (ArticleFeedDisplayItem) -> Void
    private var onOpenInPreview: (ArticleFeedDisplayItem) -> Void
    private var onNearEnd: (Int) -> Void
    private var onArticleAction: (String, ArticleStateMutation) -> Void

    init(
        items: [ArticleFeedDisplayItem],
        expandedArticleID: String?,
        appearance: ArticleFeedAppearance,
        isActive: Bool,
        reloadGeneration: Int,
        edgeResetGeneration: Int,
        onToggleExpanded: @escaping (ArticleFeedDisplayItem) -> Void,
        onOpenInPreview: @escaping (ArticleFeedDisplayItem) -> Void,
        onNearEnd: @escaping (Int) -> Void,
        onArticleAction: @escaping (String, ArticleStateMutation) -> Void
    ) {
        self.items = items
        self.expandedArticleID = expandedArticleID
        self.appearance = appearance
        self.isActive = isActive
        self.reloadGeneration = reloadGeneration
        self.edgeResetGeneration = edgeResetGeneration
        self.onToggleExpanded = onToggleExpanded
        self.onOpenInPreview = onOpenInPreview
        self.onNearEnd = onNearEnd
        self.onArticleAction = onArticleAction
    }

    func update(
        items newItems: [ArticleFeedDisplayItem],
        expandedArticleID newExpandedArticleID: String?,
        appearance newAppearance: ArticleFeedAppearance,
        isActive newIsActive: Bool,
        reloadGeneration newReloadGeneration: Int,
        edgeResetGeneration newEdgeResetGeneration: Int,
        onToggleExpanded: @escaping (ArticleFeedDisplayItem) -> Void,
        onOpenInPreview: @escaping (ArticleFeedDisplayItem) -> Void,
        onNearEnd: @escaping (Int) -> Void,
        onArticleAction: @escaping (String, ArticleStateMutation) -> Void
    ) {
        let oldIDs = items.map(\.id)
        let oldStateKeys = items.map(stateKey)
        let oldExpandedID = expandedArticleID
        let oldAppearanceKey = appearance.key
        let oldIsActive = isActive
        let oldReloadGeneration = reloadGeneration
        let oldEdgeResetGeneration = edgeResetGeneration
        let newIDs = newItems.map(\.id)
        let newStateKeys = newItems.map(stateKey)
        let newAppearanceKey = newAppearance.key

        items = newItems
        expandedArticleID = newExpandedArticleID
        appearance = newAppearance
        isActive = newIsActive
        reloadGeneration = newReloadGeneration
        edgeResetGeneration = newEdgeResetGeneration
        self.onToggleExpanded = onToggleExpanded
        self.onOpenInPreview = onOpenInPreview
        self.onNearEnd = onNearEnd
        self.onArticleAction = onArticleAction

        guard newIsActive else {
            if oldReloadGeneration != newReloadGeneration ||
                oldEdgeResetGeneration != newEdgeResetGeneration ||
                oldAppearanceKey != newAppearanceKey ||
                oldExpandedID != newExpandedArticleID ||
                oldIDs != newIDs ||
                oldStateKeys != newStateKeys {
                needsReloadOnActivation = true
                shouldScrollToTopOnActivation = shouldScrollToTopOnActivation || oldReloadGeneration != newReloadGeneration
            }
            return
        }

        updateLayoutSpacing(for: newAppearance)

        guard let collectionView else {
            return
        }

        if needsReloadOnActivation {
            let shouldScrollTop = shouldScrollToTopOnActivation || oldReloadGeneration != newReloadGeneration
            needsReloadOnActivation = false
            shouldScrollToTopOnActivation = false
            heightCache.removeAll()
            edgeReporter.reset()
            collectionView.reloadData()
            collectionView.collectionViewLayout?.invalidateLayout()
            if shouldScrollTop {
                scrollToTop(in: collectionView)
            } else {
                restoreVisibleAnchor(visibleAnchorID(in: collectionView), in: collectionView)
            }
            return
        }

        if oldIsActive,
           oldReloadGeneration == newReloadGeneration,
           oldEdgeResetGeneration == newEdgeResetGeneration,
           oldAppearanceKey == newAppearanceKey,
           oldExpandedID == newExpandedArticleID,
           oldIDs == newIDs,
           oldStateKeys == newStateKeys {
            return
        }

        if oldEdgeResetGeneration != newEdgeResetGeneration {
            edgeReporter.reset()
        }
        let visibleAnchorID = visibleAnchorID(in: collectionView)

        if oldReloadGeneration != newReloadGeneration {
            heightCache.removeAll()
            edgeReporter.reset()
            collectionView.reloadData()
            collectionView.collectionViewLayout?.invalidateLayout()
            scrollToTop(in: collectionView)
            return
        }

        if oldAppearanceKey != newAppearanceKey {
            heightCache.removeAll()
            collectionView.reloadData()
            collectionView.collectionViewLayout?.invalidateLayout()
            restoreVisibleAnchor(visibleAnchorID, in: collectionView)
            return
        }

        if oldIDs != newIDs {
            edgeReporter.reset()
            if oldIDs.count != newIDs.count {
                collectionView.reloadData()
                collectionView.collectionViewLayout?.invalidateLayout()
            } else {
                reloadVisibleItems(in: collectionView)
            }
            restoreVisibleAnchor(visibleAnchorID, in: collectionView)
            return
        }

        if oldExpandedID != newExpandedArticleID {
            reloadExpandedItems(oldExpandedID: oldExpandedID, newExpandedID: newExpandedArticleID)
            collectionView.collectionViewLayout?.invalidateLayout()
            return
        }

        reloadChangedVisibleItems(in: collectionView)
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: ArticleFeedCollectionItem.reuseIdentifier,
            for: indexPath
        )
        guard let articleItem = item as? ArticleFeedCollectionItem else {
            return item
        }

        let itemModel = items[indexPath.item]
        articleItem.configure(
            item: itemModel,
            isExpanded: itemModel.id == expandedArticleID,
            appearance: appearance,
            onToggleExpanded: { [weak self] item in
                self?.onToggleExpanded(item)
            },
            onOpenInPreview: { [weak self] item in
                self?.onOpenInPreview(item)
            },
            onArticleAction: { [weak self] articleID, mutation in
                self?.onArticleAction(articleID, mutation)
            }
        )
        return articleItem
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        let width = itemWidth(for: collectionView)
        guard indexPath.item < items.count else {
            return NSSize(width: width, height: 1)
        }

        let item = items[indexPath.item]
        guard item.id == expandedArticleID else {
            return NSSize(width: width, height: CGFloat(appearance.density.collapsedCardHeight))
        }

        let key = item.heightCacheKey(width: width, appearance: appearance)
        if let cached = heightCache.height(for: key) {
            return NSSize(width: width, height: cached)
        }

        let measured = measureHeight(for: item, width: width)
        heightCache.setHeight(measured, for: key)
        return NSSize(width: width, height: measured)
    }

    @objc func clipViewBoundsChanged(_ notification: Notification) {
        guard isActive, let collectionView else {
            return
        }

        let width = itemWidth(for: collectionView)
        if abs(width - lastLayoutWidth) > 1 {
            lastLayoutWidth = width
            heightCache.removeAll()
            collectionView.collectionViewLayout?.invalidateLayout()
        }

        notifyWindowEdgeIfNeeded(in: collectionView)
    }

    private func notifyWindowEdgeIfNeeded(in collectionView: NSCollectionView) {
        let visibleIndexes = collectionView.indexPathsForVisibleItems()
            .map(\.item)
            .filter { $0 >= 0 && $0 < items.count }
            .sorted()
        guard let firstVisible = visibleIndexes.first,
              let lastVisible = visibleIndexes.last else {
            return
        }

        if let report = edgeReporter.report(
            firstVisible: firstVisible,
            lastVisible: lastVisible,
            itemCount: items.count,
            loadMoreThreshold: ArticleFeedStore.loadMoreThreshold,
            generation: edgeResetGeneration
        ) {
            onNearEnd(report.localIndex)
        }
    }

    private func itemWidth(for collectionView: NSCollectionView) -> CGFloat {
        let sectionInset = layout?.sectionInset ?? NSEdgeInsets(top: 18, left: 14, bottom: 18, right: 14)
        let width = collectionView.enclosingScrollView?.contentView.bounds.width ?? collectionView.bounds.width
        return max(120, width - sectionInset.left - sectionInset.right)
    }

    private func measureHeight(for item: ArticleFeedDisplayItem, width: CGFloat) -> CGFloat {
        let view = ArticleFeedCard(
            article: item,
            isExpanded: item.id == expandedArticleID,
            hackerNewsMetadata: item.hackerNewsMetadata,
            metadataText: item.metadataText,
            previewText: item.previewText,
            onToggleExpanded: {},
            onOpenInPreview: {},
            onArticleAction: { _, _ in }
        )
        .environment(\.newsprintTheme, appearance.theme)
        .environment(\.readerFontChoice, appearance.readerFontChoice)
        .environment(\.readerFontSize, appearance.readerFontSize)
        .environment(\.articleListDensity, appearance.density)
        .frame(width: width)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        let size = hostingView.fittingSize
        return max(1, ceil(size.height))
    }

    private func reloadExpandedItems(oldExpandedID: String?, newExpandedID: String?) {
        guard let collectionView else {
            return
        }

        let ids = Set([oldExpandedID, newExpandedID].compactMap { $0 })
        let indexPaths = items.enumerated().compactMap { index, item -> IndexPath? in
            ids.contains(item.id) ? IndexPath(item: index, section: 0) : nil
        }

        if indexPaths.isEmpty {
            reloadVisibleItems(in: collectionView)
        } else {
            for id in ids {
                heightCache.removeHeights(articleID: id)
            }
            collectionView.reloadItems(at: Set(indexPaths))
        }
    }

    private func updateLayoutSpacing(for appearance: ArticleFeedAppearance) {
        layout?.minimumLineSpacing = appearance.density.rowVerticalPadding + 10
    }

    private func reloadVisibleItems(in collectionView: NSCollectionView) {
        let indexPaths = Set(collectionView.indexPathsForVisibleItems().filter { $0.item < items.count })
        if indexPaths.isEmpty {
            collectionView.reloadData()
        } else {
            collectionView.reloadItems(at: indexPaths)
        }
    }

    private func reloadChangedVisibleItems(in collectionView: NSCollectionView) {
        let indexPaths = Set(collectionView.indexPathsForVisibleItems().filter { indexPath in
            guard indexPath.item < items.count,
                  let item = collectionView.item(at: indexPath) as? ArticleFeedCollectionItem else {
                return false
            }
            return item.currentID != items[indexPath.item].id || item.currentStateKey != stateKey(for: items[indexPath.item])
        })
        if !indexPaths.isEmpty {
            collectionView.reloadItems(at: indexPaths)
        }
    }

    private func stateKey(for item: ArticleFeedDisplayItem) -> String {
        "\(item.isRead)|\(item.isStarred)|\(item.isHidden)"
    }

    private func visibleAnchorID(in collectionView: NSCollectionView) -> String? {
        collectionView.indexPathsForVisibleItems()
            .sorted { $0.item < $1.item }
            .compactMap { indexPath in
                indexPath.item < items.count ? items[indexPath.item].id : nil
            }
            .first
    }

    private func restoreVisibleAnchor(_ anchorID: String?, in collectionView: NSCollectionView) {
        guard let anchorID,
              let index = items.firstIndex(where: { $0.id == anchorID }) else {
            return
        }
        DispatchQueue.main.async {
            collectionView.scrollToItems(
                at: Set([IndexPath(item: index, section: 0)]),
                scrollPosition: .top
            )
        }
    }

    private func scrollToTop(in collectionView: NSCollectionView) {
        guard !items.isEmpty else {
            return
        }
        DispatchQueue.main.async {
            collectionView.scrollToItems(
                at: Set([IndexPath(item: 0, section: 0)]),
                scrollPosition: .top
            )
        }
    }
}

@MainActor
final class ArticleFeedCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ArticleFeedCollectionItem")
    private var hostingView: NSHostingView<AnyView>?
    private var collapsedView: ArticleFeedCollapsedCardView?
    private(set) var currentID: String?
    private(set) var currentStateKey: String?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func configure(
        item: ArticleFeedDisplayItem,
        isExpanded: Bool,
        appearance: ArticleFeedAppearance,
        onToggleExpanded: @escaping (ArticleFeedDisplayItem) -> Void,
        onOpenInPreview: @escaping (ArticleFeedDisplayItem) -> Void,
        onArticleAction: @escaping (String, ArticleStateMutation) -> Void
    ) {
        currentID = item.id
        currentStateKey = "\(item.isRead)|\(item.isStarred)|\(item.isHidden)"

        if isExpanded {
            configureExpanded(
                item: item,
                appearance: appearance,
                onToggleExpanded: onToggleExpanded,
                onOpenInPreview: onOpenInPreview,
                onArticleAction: onArticleAction
            )
        } else {
            configureCollapsed(
                item: item,
                appearance: appearance,
                onToggleExpanded: onToggleExpanded,
                onOpenInPreview: onOpenInPreview,
                onArticleAction: onArticleAction
            )
        }
    }

    private func configureExpanded(
        item: ArticleFeedDisplayItem,
        appearance: ArticleFeedAppearance,
        onToggleExpanded: @escaping (ArticleFeedDisplayItem) -> Void,
        onOpenInPreview: @escaping (ArticleFeedDisplayItem) -> Void,
        onArticleAction: @escaping (String, ArticleStateMutation) -> Void
    ) {
        collapsedView?.removeFromSuperview()
        collapsedView = nil

        let rootView = AnyView(
            ArticleFeedCard(
                article: item,
                isExpanded: true,
                hackerNewsMetadata: item.hackerNewsMetadata,
                metadataText: item.metadataText,
                previewText: item.previewText,
                onToggleExpanded: {
                    onToggleExpanded(item)
                },
                onOpenInPreview: {
                    onOpenInPreview(item)
                },
                onArticleAction: onArticleAction
            )
            .environment(\.newsprintTheme, appearance.theme)
            .environment(\.readerFontChoice, appearance.readerFontChoice)
            .environment(\.readerFontSize, appearance.readerFontSize)
            .environment(\.articleListDensity, appearance.density)
        )

        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            hostingView.setContentHuggingPriority(.defaultLow, for: .vertical)
            view.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: view.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            self.hostingView = hostingView
        }
    }

    private func configureCollapsed(
        item: ArticleFeedDisplayItem,
        appearance: ArticleFeedAppearance,
        onToggleExpanded: @escaping (ArticleFeedDisplayItem) -> Void,
        onOpenInPreview: @escaping (ArticleFeedDisplayItem) -> Void,
        onArticleAction: @escaping (String, ArticleStateMutation) -> Void
    ) {
        hostingView?.removeFromSuperview()
        hostingView = nil

        let cardView: ArticleFeedCollapsedCardView
        if let collapsedView {
            cardView = collapsedView
        } else {
            let newView = ArticleFeedCollapsedCardView()
            newView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(newView)
            NSLayoutConstraint.activate([
                newView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                newView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                newView.topAnchor.constraint(equalTo: view.topAnchor),
                newView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            collapsedView = newView
            cardView = newView
        }

        cardView.configure(
            item: item,
            appearance: appearance,
            onToggleExpanded: {
                onToggleExpanded(item)
            },
            onOpenInPreview: {
                onOpenInPreview(item)
            },
            onArticleAction: onArticleAction
        )
    }
}

@MainActor
final class ArticleFeedCollapsedCardView: NSControl {
    private let accentView = NSView()
    private let contentStack = NSStackView()
    private let headerStack = NSStackView()
    private let headerSpacer = NSView()
    private let statsStack = NSStackView()
    private let badgeLabel = NSTextField(labelWithString: "HN")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let chevronLabel = NSTextField(labelWithString: "⌄")
    private let titleLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")
    private let pointsBadge = ArticleFeedCollapsedStatBadgeView()
    private let commentsBadge = ArticleFeedCollapsedStatBadgeView()
    private var accentTopConstraint: NSLayoutConstraint?
    private var accentBottomConstraint: NSLayoutConstraint?
    private var accentWidthConstraint: NSLayoutConstraint?
    private var contentLeadingConstraint: NSLayoutConstraint?
    private var contentTrailingConstraint: NSLayoutConstraint?
    private var contentTopConstraint: NSLayoutConstraint?
    private var contentBottomConstraint: NSLayoutConstraint?
    private var currentItem: ArticleFeedDisplayItem?
    private var onToggleExpanded: (() -> Void)?
    private var onOpenInPreview: (() -> Void)?
    private var onArticleAction: ((String, ArticleStateMutation) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func mouseUp(with event: NSEvent) {
        onToggleExpanded?()
    }

    func configure(
        item: ArticleFeedDisplayItem,
        appearance: ArticleFeedAppearance,
        onToggleExpanded: @escaping () -> Void,
        onOpenInPreview: @escaping () -> Void,
        onArticleAction: @escaping (String, ArticleStateMutation) -> Void
    ) {
        currentItem = item
        self.onToggleExpanded = onToggleExpanded
        self.onOpenInPreview = onOpenInPreview
        self.onArticleAction = onArticleAction

        let density = appearance.density
        let metadataFontSize = max(12, CGFloat(appearance.readerFontSize) * density.metadataScale)
        let titleFontSize = CGFloat(appearance.readerFontSize) * density.titleScale
        let contentInset = density.cardPadding

        wantsLayer = true
        layer?.cornerRadius = density.cardCornerRadius
        layer?.backgroundColor = nsColor(appearance.theme.readerSurface).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.10).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.025).cgColor
        layer?.shadowRadius = 4
        layer?.shadowOffset = NSSize(width: 0, height: 1)
        layer?.shadowOpacity = 1

        accentView.layer?.backgroundColor = item.isRead
            ? NSColor.clear.cgColor
            : nsColor(appearance.theme.rowAccent).cgColor

        badgeLabel.isHidden = item.hackerNewsMetadata == nil
        badgeLabel.font = .systemFont(ofSize: metadataFontSize * 0.92, weight: .bold)
        badgeLabel.textColor = .white

        metadataLabel.stringValue = item.metadataText
        metadataLabel.font = cardFont(choice: appearance.readerFontChoice, size: metadataFontSize, weight: .semibold)
        metadataLabel.textColor = nsColor(appearance.theme.metadata)

        openButton.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "Open in Side")
        openButton.image?.size = NSSize(width: metadataFontSize * 1.38, height: metadataFontSize * 1.38)
        openButton.bezelStyle = .inline
        openButton.isBordered = false
        openButton.contentTintColor = nsColor(appearance.theme.tint)
        openButton.target = self
        openButton.action = #selector(openInPreview)

        statusLabel.stringValue = statusText(for: item)
        statusLabel.font = .systemFont(ofSize: metadataFontSize, weight: .semibold)
        statusLabel.textColor = nsColor(appearance.theme.metadata)

        chevronLabel.font = .systemFont(ofSize: metadataFontSize * 1.12, weight: .semibold)
        chevronLabel.textColor = nsColor(appearance.theme.metadata)

        titleLabel.stringValue = item.title
        titleLabel.font = cardFont(choice: appearance.readerFontChoice, size: titleFontSize, weight: item.isRead ? .medium : .semibold)
        titleLabel.textColor = item.isRead ? .secondaryLabelColor : .labelColor
        titleLabel.maximumNumberOfLines = 3

        previewLabel.stringValue = item.previewText ?? ""
        previewLabel.isHidden = item.previewText == nil
        previewLabel.font = cardFont(choice: appearance.readerFontChoice, size: CGFloat(appearance.readerFontSize), weight: .regular)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.maximumNumberOfLines = density.previewLineLimit

        pointsBadge.configure(
            value: item.hackerNewsMetadata?.points,
            systemImageName: "arrowtriangle.up.fill",
            appearance: appearance,
            fontSize: metadataFontSize
        )
        commentsBadge.configure(
            value: item.hackerNewsMetadata?.commentCount,
            systemImageName: "text.bubble",
            appearance: appearance,
            fontSize: metadataFontSize
        )
        statsStack.isHidden = pointsBadge.isHidden && commentsBadge.isHidden
        contentStack.spacing = density.rowSpacing

        accentTopConstraint?.constant = contentInset
        accentBottomConstraint?.constant = -contentInset
        accentWidthConstraint?.constant = item.isRead ? 0 : 3
        contentLeadingConstraint?.constant = contentInset
        contentTrailingConstraint?.constant = -contentInset
        contentTopConstraint?.constant = contentInset
        contentBottomConstraint?.constant = -contentInset

        menu = contextMenu(for: item)
    }

    private func setup() {
        wantsLayer = true

        accentView.wantsLayer = true
        accentView.layer?.cornerRadius = 2
        badgeLabel.alignment = .center
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.cornerRadius = 3
        badgeLabel.layer?.backgroundColor = NSColor.systemOrange.cgColor

        for field in [badgeLabel, metadataLabel, statusLabel, chevronLabel, titleLabel, previewLabel] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.lineBreakMode = .byTruncatingTail
        }
        titleLabel.lineBreakMode = .byWordWrapping
        previewLabel.lineBreakMode = .byWordWrapping
        previewLabel.cell?.wraps = true
        previewLabel.cell?.isScrollable = false
        metadataLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        openButton.translatesAutoresizingMaskIntoConstraints = false
        accentView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 8
        headerStack.distribution = .fill
        headerStack.detachesHiddenViews = true
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        statsStack.orientation = .horizontal
        statsStack.alignment = .centerY
        statsStack.spacing = 14
        statsStack.distribution = .gravityAreas
        statsStack.detachesHiddenViews = true
        statsStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.distribution = .fill
        contentStack.detachesHiddenViews = true

        addSubview(accentView)
        addSubview(contentStack)

        headerStack.addArrangedSubview(badgeLabel)
        headerStack.addArrangedSubview(metadataLabel)
        headerStack.addArrangedSubview(openButton)
        headerStack.addArrangedSubview(statusLabel)
        headerStack.addArrangedSubview(headerSpacer)
        headerStack.addArrangedSubview(chevronLabel)

        statsStack.addArrangedSubview(pointsBadge)
        statsStack.addArrangedSubview(commentsBadge)

        contentStack.addArrangedSubview(headerStack)
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(previewLabel)
        contentStack.addArrangedSubview(statsStack)

        accentTopConstraint = accentView.topAnchor.constraint(equalTo: topAnchor, constant: 22)
        accentBottomConstraint = accentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22)
        accentWidthConstraint = accentView.widthAnchor.constraint(equalToConstant: 3)
        contentLeadingConstraint = contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28)
        contentTrailingConstraint = contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28)
        contentTopConstraint = contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 28)
        contentBottomConstraint = contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -28)

        NSLayoutConstraint.activate([
            accentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentTopConstraint!,
            accentBottomConstraint!,
            accentWidthConstraint!,

            contentLeadingConstraint!,
            contentTrailingConstraint!,
            contentTopConstraint!,
            contentBottomConstraint!,

            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 46),
            badgeLabel.heightAnchor.constraint(equalToConstant: 32),

            openButton.widthAnchor.constraint(equalToConstant: 34),
            openButton.heightAnchor.constraint(equalToConstant: 34),

            headerStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            titleLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            previewLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor)
        ])
    }

    @objc private func openInPreview() {
        onOpenInPreview?()
    }

    @objc private func toggleStar() {
        guard let currentItem else { return }
        onArticleAction?(currentItem.id, .toggleStar)
    }

    @objc private func toggleRead() {
        guard let currentItem else { return }
        onArticleAction?(currentItem.id, .toggleRead)
    }

    @objc private func toggleHidden() {
        guard let currentItem else { return }
        onArticleAction?(currentItem.id, .toggleHidden)
    }

    @objc private func openOriginal() {
        guard let currentItem else { return }
        NSWorkspace.shared.open(currentItem.previewURL)
    }

    @objc private func openHNThread() {
        guard let threadURL = currentItem?.hackerNewsMetadata?.threadURL else { return }
        NSWorkspace.shared.open(threadURL)
    }

    @objc private func copyLink() {
        guard let currentItem else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentItem.previewURL.absoluteString, forType: .string)
    }

    private func contextMenu(for item: ArticleFeedDisplayItem) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem(title: item.isStarred ? "Unstar" : "Star", action: #selector(toggleStar)))
        menu.addItem(menuItem(title: item.isRead ? "Mark Unread" : "Mark Read", action: #selector(toggleRead)))
        menu.addItem(menuItem(title: item.isHidden ? "Unhide" : "Hide", action: #selector(toggleHidden)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Open Original", action: #selector(openOriginal)))
        if item.hackerNewsMetadata?.threadURL != nil {
            menu.addItem(menuItem(title: "Open HN Thread", action: #selector(openHNThread)))
        }
        menu.addItem(menuItem(title: "Copy Link", action: #selector(copyLink)))
        return menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func statusText(for item: ArticleFeedDisplayItem) -> String {
        var parts: [String] = []
        if item.isStarred {
            parts.append("★")
        }
        if item.isHidden {
            parts.append("◌")
        }
        return parts.joined(separator: " ")
    }

    private func nsColor(_ color: Color) -> NSColor {
        NSColor(color)
    }

    private func cardFont(choice: ReaderFontChoice, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        switch choice {
        case .monospaced:
            NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        case .rounded:
            designedSystemFont(.rounded, size: size, weight: weight)
        case .serif:
            designedSystemFont(.serif, size: size, weight: weight)
        case .system:
            NSFont.systemFont(ofSize: size, weight: weight)
        }
    }

    private func designedSystemFont(_ design: NSFontDescriptor.SystemDesign, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(design) else {
            return base
        }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

@MainActor
private final class ArticleFeedCollapsedStatBadgeView: NSView {
    private let stack = NSStackView()
    private let imageView = NSImageView()
    private let valueLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(
        value: Int?,
        systemImageName: String,
        appearance: ArticleFeedAppearance,
        fontSize: CGFloat
    ) {
        guard let value else {
            isHidden = true
            return
        }

        isHidden = false
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil

        let statFontSize = fontSize * 1.34
        imageView.image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: nil)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: statFontSize, weight: .semibold)
        imageView.contentTintColor = nsColor(appearance.theme.metadata)

        valueLabel.stringValue = "\(value)"
        valueLabel.font = .systemFont(ofSize: statFontSize, weight: .semibold)
        valueLabel.textColor = nsColor(appearance.theme.metadata)
    }

    private func setup() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        imageView.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(valueLabel)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 23),
            imageView.heightAnchor.constraint(equalToConstant: 23)
        ])
    }

    private func nsColor(_ color: Color) -> NSColor {
        NSColor(color)
    }
}
