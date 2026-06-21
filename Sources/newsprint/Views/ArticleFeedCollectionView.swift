import AppKit
import SwiftUI
import newsprintCore

struct ArticleFeedCollectionView: NSViewRepresentable {
    let items: [ArticleFeedDisplayItem]
    let detailsByID: [String: ArticleDetailSnapshot]
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
            detailsByID: detailsByID,
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
            detailsByID: detailsByID,
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
    private var detailsByID: [String: ArticleDetailSnapshot]
    private var expandedArticleID: String?
    private var appearance: ArticleFeedAppearance
    private var isActive: Bool
    private var reloadGeneration: Int
    private var edgeResetGeneration: Int
    private var needsReloadOnActivation = false
    private var shouldScrollToTopOnActivation = false
    private let heightCache = ArticleFeedHeightCache()
    private var textExpandedArticleIDs: Set<String> = []
    private var lastLayoutWidth: CGFloat = 0
    private var edgeReporter = ArticleRenderWindowEdgeReporter()
    private var onToggleExpanded: (ArticleFeedDisplayItem) -> Void
    private var onOpenInPreview: (ArticleFeedDisplayItem) -> Void
    private var onNearEnd: (Int) -> Void
    private var onArticleAction: (String, ArticleStateMutation) -> Void

    init(
        items: [ArticleFeedDisplayItem],
        detailsByID: [String: ArticleDetailSnapshot],
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
        self.detailsByID = detailsByID
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
        detailsByID newDetailsByID: [String: ArticleDetailSnapshot],
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
        let oldItems = items
        let oldIDs = items.map(\.id)
        let oldDetailKeys = items.map { detailKey(for: $0.id, in: detailsByID) }
        let oldStateKeys = items.map(stateKey)
        let oldExpandedID = expandedArticleID
        let oldAppearanceKey = appearance.key
        let oldIsActive = isActive
        let oldReloadGeneration = reloadGeneration
        let oldEdgeResetGeneration = edgeResetGeneration
        let newIDs = newItems.map(\.id)
        let newDetailKeys = newItems.map { detailKey(for: $0.id, in: newDetailsByID) }
        let newStateKeys = newItems.map(stateKey)
        let newAppearanceKey = newAppearance.key
        let visibleAnchorIDBeforeUpdate: String?
        if let collectionView {
            visibleAnchorIDBeforeUpdate = visibleAnchorID(in: collectionView, items: oldItems)
        } else {
            visibleAnchorIDBeforeUpdate = nil
        }

        items = newItems
        detailsByID = newDetailsByID
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
                oldDetailKeys != newDetailKeys ||
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
           oldDetailKeys == newDetailKeys,
           oldStateKeys == newStateKeys {
            return
        }

        if oldEdgeResetGeneration != newEdgeResetGeneration {
            edgeReporter.reset()
        }
        let visibleAnchorID = visibleAnchorIDBeforeUpdate

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
            if let oldExpandedID {
                textExpandedArticleIDs.remove(oldExpandedID)
            }
            reloadExpandedItems(oldExpandedID: oldExpandedID, newExpandedID: newExpandedArticleID)
            collectionView.collectionViewLayout?.invalidateLayout()
            return
        }

        if oldDetailKeys != newDetailKeys {
            reloadChangedDetailItems(oldDetailKeys: oldDetailKeys, newDetailKeys: newDetailKeys, in: collectionView)
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
            detail: detailsByID[itemModel.id],
            isExpanded: itemModel.id == expandedArticleID,
            isTextExpanded: textExpandedArticleIDs.contains(itemModel.id),
            appearance: appearance,
            onToggleExpanded: { [weak self] item in
                self?.onToggleExpanded(item)
            },
            onOpenInPreview: { [weak self] item in
                self?.onOpenInPreview(item)
            },
            onReadMore: { [weak self] articleID in
                self?.expandText(for: articleID)
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

        let isTextExpanded = textExpandedArticleIDs.contains(item.id)
        let key = item.heightCacheKey(width: width, appearance: appearance, isTextExpanded: isTextExpanded)
        if let cached = heightCache.height(for: key) {
            return NSSize(width: width, height: cached)
        }

        let measured = measureHeight(
            for: item,
            detail: detailsByID[item.id],
            width: width,
            isTextExpanded: isTextExpanded
        )
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

    private func measureHeight(
        for item: ArticleFeedDisplayItem,
        detail: ArticleDetailSnapshot?,
        width: CGFloat,
        isTextExpanded: Bool
    ) -> CGFloat {
        let cardView = ArticleFeedCollapsedCardView()
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: CGFloat(appearance.density.collapsedCardHeight)
        )
        cardView.widthAnchor.constraint(equalToConstant: width).isActive = true
        cardView.configure(
            item: item,
            detail: detail,
            isExpanded: item.id == expandedArticleID,
            isTextExpanded: isTextExpanded,
            appearance: appearance,
            onToggleExpanded: {},
            onOpenInPreview: {},
            onReadMore: { _ in },
            onArticleAction: { _, _ in }
        )
        cardView.layoutSubtreeIfNeeded()
        let size = cardView.fittingSize
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

    private func expandText(for articleID: String) {
        guard let collectionView else {
            return
        }

        textExpandedArticleIDs.insert(articleID)
        heightCache.removeHeights(articleID: articleID)
        if let index = items.firstIndex(where: { $0.id == articleID }) {
            collectionView.reloadItems(at: Set([IndexPath(item: index, section: 0)]))
        }
        collectionView.collectionViewLayout?.invalidateLayout()
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

    private func reloadChangedDetailItems(
        oldDetailKeys: [String],
        newDetailKeys: [String],
        in collectionView: NSCollectionView
    ) {
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems().filter { $0.item < items.count }
        let changed = Set(visibleIndexPaths.filter { indexPath in
            indexPath.item < oldDetailKeys.count &&
                indexPath.item < newDetailKeys.count &&
                oldDetailKeys[indexPath.item] != newDetailKeys[indexPath.item]
        })
        for indexPath in changed {
            heightCache.removeHeights(articleID: items[indexPath.item].id)
        }
        if !changed.isEmpty {
            collectionView.reloadItems(at: changed)
        }
    }

    private func stateKey(for item: ArticleFeedDisplayItem) -> String {
        "\(item.isRead)|\(item.isStarred)|\(item.isHidden)"
    }

    private func detailKey(for articleID: String, in details: [String: ArticleDetailSnapshot]) -> String {
        guard let detail = details[articleID] else { return "none" }
        return "\(detail.contentHTML?.count ?? 0)|\(detail.contentText?.count ?? 0)|\(detail.excerpt?.count ?? 0)|\(detail.authorCommentText?.count ?? 0)"
    }

    private func visibleAnchorID(in collectionView: NSCollectionView) -> String? {
        visibleAnchorID(in: collectionView, items: items)
    }

    private func visibleAnchorID(
        in collectionView: NSCollectionView,
        items sourceItems: [ArticleFeedDisplayItem]
    ) -> String? {
        collectionView.indexPathsForVisibleItems()
            .sorted { $0.item < $1.item }
            .compactMap { indexPath in
                indexPath.item < sourceItems.count ? sourceItems[indexPath.item].id : nil
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
        detail: ArticleDetailSnapshot?,
        isExpanded: Bool,
        isTextExpanded: Bool,
        appearance: ArticleFeedAppearance,
        onToggleExpanded: @escaping (ArticleFeedDisplayItem) -> Void,
        onOpenInPreview: @escaping (ArticleFeedDisplayItem) -> Void,
        onReadMore: @escaping (String) -> Void,
        onArticleAction: @escaping (String, ArticleStateMutation) -> Void
    ) {
        currentID = item.id
        currentStateKey = "\(item.isRead)|\(item.isStarred)|\(item.isHidden)"

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
            detail: detail,
            isExpanded: isExpanded,
            isTextExpanded: isTextExpanded,
            appearance: appearance,
            onToggleExpanded: {
                onToggleExpanded(item)
            },
            onOpenInPreview: {
                onOpenInPreview(item)
            },
            onReadMore: onReadMore,
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
    private let badgeView = ArticleFeedHackerNewsBadgeView()
    private let metadataLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let chevronLabel = NSTextField(labelWithString: "⌄")
    private let titleLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")
    private let dividerView = NSBox()
    private let expandedBodyLabel = NSTextField(labelWithString: "")
    private let bodyReadMoreButton = NSButton(title: "Read More", target: nil, action: nil)
    private let authorCommentView = NSView()
    private let authorAccentView = NSView()
    private let authorStack = NSStackView()
    private let authorTitleLabel = NSTextField(labelWithString: "Author Comment")
    private let authorCommentLabel = NSTextField(labelWithString: "")
    private let authorReadMoreButton = NSButton(title: "Read More", target: nil, action: nil)
    private let actionsStack = NSStackView()
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
    private var onReadMore: ((String) -> Void)?
    private var onArticleAction: ((String, ArticleStateMutation) -> Void)?
    private var lastConfiguredWidth: CGFloat = 0

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
        detail: ArticleDetailSnapshot?,
        isExpanded: Bool,
        isTextExpanded: Bool,
        appearance: ArticleFeedAppearance,
        onToggleExpanded: @escaping () -> Void,
        onOpenInPreview: @escaping () -> Void,
        onReadMore: @escaping (String) -> Void,
        onArticleAction: @escaping (String, ArticleStateMutation) -> Void
    ) {
        currentItem = item
        self.onToggleExpanded = onToggleExpanded
        self.onOpenInPreview = onOpenInPreview
        self.onReadMore = onReadMore
        self.onArticleAction = onArticleAction
        lastConfiguredWidth = bounds.width

        let density = appearance.density
        let metadataFontSize = max(12, CGFloat(appearance.readerFontSize) * density.metadataScale)
        let titleFontSize = CGFloat(appearance.readerFontSize) * density.titleScale
        let contentInset = density.cardPadding

        wantsLayer = true
        layer?.cornerRadius = density.cardCornerRadius
        layer?.backgroundColor = nsColor(appearance.theme.readerSurface).cgColor
        layer?.borderWidth = isExpanded ? 1.4 : 1
        layer?.borderColor = (isExpanded
            ? nsColor(appearance.theme.rowAccent).withAlphaComponent(0.55)
            : NSColor.separatorColor.withAlphaComponent(0.10)).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(isExpanded ? 0.10 : 0.025).cgColor
        layer?.shadowRadius = isExpanded ? 12 : 4
        layer?.shadowOffset = NSSize(width: 0, height: isExpanded ? 5 : 1)
        layer?.shadowOpacity = 1

        accentView.layer?.backgroundColor = item.isRead
            ? NSColor.clear.cgColor
            : nsColor(appearance.theme.rowAccent).cgColor

        badgeView.configure(
            isVisible: item.hackerNewsMetadata != nil,
            fontSize: metadataFontSize * 0.78
        )

        metadataLabel.stringValue = item.metadataText
        metadataLabel.font = cardFont(choice: appearance.readerFontChoice, size: metadataFontSize, weight: .semibold)
        metadataLabel.textColor = nsColor(appearance.theme.metadata)

        let arrowConfiguration = NSImage.SymbolConfiguration(pointSize: metadataFontSize * 1.50, weight: .bold)
        openButton.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "Open in Side")?
            .withSymbolConfiguration(arrowConfiguration)
        openButton.bezelStyle = .inline
        openButton.isBordered = false
        openButton.contentTintColor = nsColor(appearance.theme.tint)
        openButton.target = self
        openButton.action = #selector(openInPreview)

        statusLabel.stringValue = statusText(for: item)
        statusLabel.font = .systemFont(ofSize: metadataFontSize, weight: .semibold)
        statusLabel.textColor = nsColor(appearance.theme.metadata)

        chevronLabel.stringValue = isExpanded ? "⌃" : "⌄"
        chevronLabel.font = .systemFont(ofSize: metadataFontSize * 1.12, weight: .semibold)
        chevronLabel.textColor = nsColor(appearance.theme.metadata)

        titleLabel.stringValue = item.title
        titleLabel.font = cardFont(choice: appearance.readerFontChoice, size: titleFontSize, weight: item.isRead ? .medium : .semibold)
        titleLabel.textColor = item.isRead ? .secondaryLabelColor : .labelColor
        titleLabel.maximumNumberOfLines = isExpanded ? 0 : 3

        setArticleText(
            item.previewText ?? "",
            on: previewLabel,
            font: cardFont(choice: appearance.readerFontChoice, size: CGFloat(appearance.readerFontSize), weight: .regular),
            color: .secondaryLabelColor,
            lineSpacing: 4
        )
        previewLabel.isHidden = item.previewText == nil
        previewLabel.maximumNumberOfLines = isExpanded ? 0 : min(density.previewLineLimit, 2)

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
        contentStack.setCustomSpacing(density.rowSpacing + 5, after: headerStack)
        contentStack.setCustomSpacing(density.rowSpacing + 8, after: titleLabel)
        contentStack.setCustomSpacing(density.rowSpacing + 8, after: previewLabel)

        configureExpandedContent(
            item: item,
            detail: detail,
            isExpanded: isExpanded,
            isTextExpanded: isTextExpanded,
            appearance: appearance
        )
        configureActionButtons(item: item, isExpanded: isExpanded, appearance: appearance)

        accentTopConstraint?.constant = contentInset
        accentBottomConstraint?.constant = -contentInset
        accentWidthConstraint?.constant = item.isRead ? 0 : (isExpanded ? 5 : 3)
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
        for field in [metadataLabel, statusLabel, chevronLabel, titleLabel, previewLabel, expandedBodyLabel, authorTitleLabel, authorCommentLabel] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.lineBreakMode = .byTruncatingTail
        }
        titleLabel.lineBreakMode = .byWordWrapping
        previewLabel.lineBreakMode = .byWordWrapping
        expandedBodyLabel.lineBreakMode = .byWordWrapping
        authorCommentLabel.lineBreakMode = .byWordWrapping
        titleLabel.cell?.usesSingleLineMode = false
        previewLabel.cell?.wraps = true
        previewLabel.cell?.isScrollable = false
        previewLabel.cell?.usesSingleLineMode = false
        expandedBodyLabel.cell?.wraps = true
        expandedBodyLabel.cell?.isScrollable = false
        expandedBodyLabel.cell?.usesSingleLineMode = false
        authorCommentLabel.cell?.wraps = true
        authorCommentLabel.cell?.isScrollable = false
        authorCommentLabel.cell?.usesSingleLineMode = false
        metadataLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        expandedBodyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        authorCommentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        metadataLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        statsStack.setContentCompressionResistancePriority(.required, for: .vertical)
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        expandedBodyLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        authorCommentLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        openButton.translatesAutoresizingMaskIntoConstraints = false
        bodyReadMoreButton.translatesAutoresizingMaskIntoConstraints = false
        authorReadMoreButton.translatesAutoresizingMaskIntoConstraints = false
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        accentView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        dividerView.translatesAutoresizingMaskIntoConstraints = false
        authorCommentView.translatesAutoresizingMaskIntoConstraints = false
        authorAccentView.translatesAutoresizingMaskIntoConstraints = false
        authorStack.translatesAutoresizingMaskIntoConstraints = false
        actionsStack.translatesAutoresizingMaskIntoConstraints = false

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

        dividerView.boxType = .separator

        authorCommentView.wantsLayer = true
        authorCommentView.layer?.cornerRadius = 8
        authorAccentView.wantsLayer = true
        authorAccentView.layer?.cornerRadius = 2
        authorStack.orientation = .vertical
        authorStack.alignment = .leading
        authorStack.spacing = 10
        authorStack.distribution = .fill
        authorStack.detachesHiddenViews = true
        authorTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        configureReadMoreButton(bodyReadMoreButton)
        configureReadMoreButton(authorReadMoreButton)

        actionsStack.orientation = .horizontal
        actionsStack.alignment = .centerY
        actionsStack.spacing = 10
        actionsStack.distribution = .gravityAreas
        actionsStack.detachesHiddenViews = true

        addSubview(accentView)
        addSubview(contentStack)

        headerStack.addArrangedSubview(badgeView)
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
        contentStack.addArrangedSubview(dividerView)
        contentStack.addArrangedSubview(expandedBodyLabel)
        contentStack.addArrangedSubview(bodyReadMoreButton)
        contentStack.addArrangedSubview(authorCommentView)
        contentStack.addArrangedSubview(actionsStack)

        authorStack.addArrangedSubview(authorTitleLabel)
        authorStack.addArrangedSubview(authorCommentLabel)
        authorStack.addArrangedSubview(authorReadMoreButton)
        authorCommentView.addSubview(authorAccentView)
        authorCommentView.addSubview(authorStack)

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

            badgeView.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            badgeView.heightAnchor.constraint(equalToConstant: 28),

            openButton.widthAnchor.constraint(equalToConstant: 34),
            openButton.heightAnchor.constraint(equalToConstant: 34),

            headerStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            titleLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            previewLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            dividerView.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            expandedBodyLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            authorCommentView.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            actionsStack.widthAnchor.constraint(lessThanOrEqualTo: contentStack.widthAnchor),

            authorAccentView.leadingAnchor.constraint(equalTo: authorCommentView.leadingAnchor, constant: 16),
            authorAccentView.topAnchor.constraint(equalTo: authorCommentView.topAnchor, constant: 16),
            authorAccentView.bottomAnchor.constraint(equalTo: authorCommentView.bottomAnchor, constant: -16),
            authorAccentView.widthAnchor.constraint(equalToConstant: 4),

            authorStack.leadingAnchor.constraint(equalTo: authorAccentView.trailingAnchor, constant: 14),
            authorStack.trailingAnchor.constraint(equalTo: authorCommentView.trailingAnchor, constant: -16),
            authorStack.topAnchor.constraint(equalTo: authorCommentView.topAnchor, constant: 16),
            authorStack.bottomAnchor.constraint(equalTo: authorCommentView.bottomAnchor, constant: -16),
            authorCommentLabel.widthAnchor.constraint(equalTo: authorStack.widthAnchor)
        ])
    }

    @objc private func openInPreview() {
        onOpenInPreview?()
    }

    private func configureExpandedContent(
        item: ArticleFeedDisplayItem,
        detail: ArticleDetailSnapshot?,
        isExpanded: Bool,
        isTextExpanded: Bool,
        appearance: ArticleFeedAppearance
    ) {
        dividerView.isHidden = !isExpanded
        expandedBodyLabel.isHidden = true
        bodyReadMoreButton.isHidden = true
        authorCommentView.isHidden = true
        authorReadMoreButton.isHidden = true

        guard isExpanded else { return }

        let bodyFont = cardFont(
            choice: appearance.readerFontChoice,
            size: CGFloat(appearance.readerFontSize),
            weight: .regular
        )
        expandedBodyLabel.font = bodyFont
        expandedBodyLabel.textColor = .labelColor
        expandedBodyLabel.maximumNumberOfLines = isTextExpanded ? 0 : 4

        if item.hackerNewsMetadata == nil,
           let bodyText = HTMLTextExtractor.text(
            fromHTML: detail?.contentText ?? detail?.excerpt ?? item.previewText
           )?.articleFeedNilIfBlank {
            let bodyNormalized = bodyText.articleFeedNormalizedText
            let previewNormalized = item.previewText?.articleFeedNilIfBlank?.articleFeedNormalizedText
            if previewNormalized == nil || bodyNormalized != previewNormalized {
                setArticleText(
                    bodyText,
                    on: expandedBodyLabel,
                    font: bodyFont,
                    color: .labelColor,
                    lineSpacing: 6
                )
                expandedBodyLabel.isHidden = false
                bodyReadMoreButton.isHidden = isTextExpanded || !bodyText.articleFeedProbablyNeedsReadMore
            }
        }

        if let authorComment = (detail?.authorCommentText ?? item.hackerNewsAuthorCommentText)?.articleFeedNilIfBlank {
            authorCommentView.isHidden = false
            authorCommentView.layer?.backgroundColor = nsColor(appearance.theme.rowAccent).withAlphaComponent(0.10).cgColor
            authorAccentView.layer?.backgroundColor = nsColor(appearance.theme.rowAccent).cgColor
            authorTitleLabel.stringValue = "Author Comment"
            authorTitleLabel.textColor = .labelColor
            setArticleText(
                authorComment,
                on: authorCommentLabel,
                font: bodyFont,
                color: .labelColor,
                lineSpacing: 6
            )
            authorCommentLabel.maximumNumberOfLines = isTextExpanded ? 0 : 4
            authorReadMoreButton.isHidden = isTextExpanded || !authorComment.articleFeedProbablyNeedsReadMore
        }

        updatePreferredTextWidths()
    }

    override func layout() {
        super.layout()
        lastConfiguredWidth = bounds.width
        updatePreferredTextWidths()
    }

    private func updatePreferredTextWidths() {
        let fallbackContentWidth = max(1, lastConfiguredWidth - (contentLeadingConstraint?.constant ?? 0) + (contentTrailingConstraint?.constant ?? 0))
        let contentWidth = contentStack.bounds.width > 1 ? contentStack.bounds.width : fallbackContentWidth
        let fallbackAuthorWidth = max(1, contentWidth - 50)
        let authorWidth = authorStack.bounds.width > 1 ? authorStack.bounds.width : fallbackAuthorWidth
        titleLabel.preferredMaxLayoutWidth = contentWidth
        previewLabel.preferredMaxLayoutWidth = contentWidth
        expandedBodyLabel.preferredMaxLayoutWidth = contentWidth
        authorCommentLabel.preferredMaxLayoutWidth = authorWidth
    }

    private func configureActionButtons(
        item: ArticleFeedDisplayItem,
        isExpanded: Bool,
        appearance: ArticleFeedAppearance
    ) {
        actionsStack.arrangedSubviews.forEach { view in
            actionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        actionsStack.isHidden = !isExpanded
        guard isExpanded else { return }

        actionsStack.addArrangedSubview(actionButton(
            title: item.isStarred ? "Unstar" : "Star",
            symbolName: item.isStarred ? "star.slash" : "star",
            action: #selector(toggleStar)
        ))
        actionsStack.addArrangedSubview(actionButton(
            title: item.isRead ? "Mark Unread" : "Mark Read",
            symbolName: item.isRead ? "circle" : "checkmark.circle",
            action: #selector(toggleRead)
        ))
        actionsStack.addArrangedSubview(actionButton(
            title: item.isHidden ? "Unhide" : "Hide",
            symbolName: item.isHidden ? "eye" : "eye.slash",
            action: #selector(toggleHidden)
        ))
        actionsStack.addArrangedSubview(actionButton(
            title: "Open Original",
            symbolName: "safari",
            action: #selector(openOriginal)
        ))
        if item.hackerNewsMetadata?.threadURL != nil {
            actionsStack.addArrangedSubview(actionButton(
                title: "Open HN Thread",
                symbolName: "bubble.left.and.bubble.right",
                action: #selector(openHNThread)
            ))
        }
        actionsStack.addArrangedSubview(actionButton(
            title: "Copy Link",
            symbolName: "link",
            action: #selector(copyLink)
        ))
    }

    private func actionButton(title: String, symbolName: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    private func configureReadMoreButton(_ button: NSButton) {
        button.target = self
        button.action = #selector(readMore)
        button.bezelStyle = .inline
        button.isBordered = false
        button.controlSize = .regular
        button.alignment = .left
        button.setButtonType(.momentaryPushIn)
        button.contentTintColor = NSColor.systemOrange
        button.font = .systemFont(ofSize: 14, weight: .semibold)
    }

    @objc private func readMore() {
        guard let currentItem else { return }
        onReadMore?(currentItem.id)
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

    private func setArticleText(
        _ text: String,
        on label: NSTextField,
        font: NSFont,
        color: NSColor,
        lineSpacing: CGFloat
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = lineSpacing
        label.font = font
        label.textColor = color
        label.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )
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
private final class ArticleFeedHackerNewsBadgeView: NSView {
    private var font = NSFont.systemFont(ofSize: 12, weight: .bold)

    override var isHidden: Bool {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: NSSize {
        isHidden ? .zero : NSSize(width: 40, height: 28)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(isVisible: Bool, fontSize: CGFloat) {
        isHidden = !isVisible
        font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isHidden else { return }

        let badgePath = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
        NSColor.systemOrange.setFill()
        badgePath.fill()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let text = "HN" as NSString
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: bounds.minX,
            y: bounds.midY - (textSize.height / 2),
            width: bounds.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }

    private func setup() {
        wantsLayer = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
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

private extension String {
    var articleFeedNilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var articleFeedNormalizedText: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var articleFeedProbablyNeedsReadMore: Bool {
        let hardLineCount = components(separatedBy: .newlines).count
        return hardLineCount > 4 || articleFeedNormalizedText.count > 260
    }
}
