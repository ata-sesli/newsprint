import AppKit
import SwiftUI
import newsprintCore

struct ArticleFeedCollectionView: NSViewRepresentable {
    let items: [ArticleFeedItemModel]
    let reloadGeneration: Int
    let edgeResetGeneration: Int
    let onToggleExpanded: (Article) -> Void
    let onOpenInPreview: (Article) -> Void
    let onNearEnd: (Int) -> Void
    let onArticleAction: (Article, ArticleStateMutation) -> Void

    func makeCoordinator() -> ArticleFeedCollectionCoordinator {
        ArticleFeedCollectionCoordinator(
            items: items,
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
        layout.minimumLineSpacing = 18
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
    private var items: [ArticleFeedItemModel]
    private var reloadGeneration: Int
    private var edgeResetGeneration: Int
    private let heightCache = ArticleFeedHeightCache()
    private var lastLayoutWidth: CGFloat = 0
    private var edgeReporter = ArticleRenderWindowEdgeReporter()
    private var onToggleExpanded: (Article) -> Void
    private var onOpenInPreview: (Article) -> Void
    private var onNearEnd: (Int) -> Void
    private var onArticleAction: (Article, ArticleStateMutation) -> Void

    init(
        items: [ArticleFeedItemModel],
        reloadGeneration: Int,
        edgeResetGeneration: Int,
        onToggleExpanded: @escaping (Article) -> Void,
        onOpenInPreview: @escaping (Article) -> Void,
        onNearEnd: @escaping (Int) -> Void,
        onArticleAction: @escaping (Article, ArticleStateMutation) -> Void
    ) {
        self.items = items
        self.reloadGeneration = reloadGeneration
        self.edgeResetGeneration = edgeResetGeneration
        self.onToggleExpanded = onToggleExpanded
        self.onOpenInPreview = onOpenInPreview
        self.onNearEnd = onNearEnd
        self.onArticleAction = onArticleAction
    }

    func update(
        items newItems: [ArticleFeedItemModel],
        reloadGeneration newReloadGeneration: Int,
        edgeResetGeneration newEdgeResetGeneration: Int,
        onToggleExpanded: @escaping (Article) -> Void,
        onOpenInPreview: @escaping (Article) -> Void,
        onNearEnd: @escaping (Int) -> Void,
        onArticleAction: @escaping (Article, ArticleStateMutation) -> Void
    ) {
        updateLayoutSpacing(for: newItems)

        let oldIDs = items.map(\.id)
        let oldExpandedID = items.first(where: \.isExpanded)?.id
        let oldAppearanceKey = items.first.map(appearanceKey)
        let oldReloadGeneration = reloadGeneration
        let oldEdgeResetGeneration = edgeResetGeneration
        let newIDs = newItems.map(\.id)
        let newExpandedID = newItems.first(where: \.isExpanded)?.id
        let newAppearanceKey = newItems.first.map(appearanceKey)

        items = newItems
        reloadGeneration = newReloadGeneration
        edgeResetGeneration = newEdgeResetGeneration
        self.onToggleExpanded = onToggleExpanded
        self.onOpenInPreview = onOpenInPreview
        self.onNearEnd = onNearEnd
        self.onArticleAction = onArticleAction

        guard let collectionView else {
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

        if oldIDs != newIDs || oldAppearanceKey != newAppearanceKey {
            heightCache.removeAll()
            edgeReporter.reset()
            collectionView.reloadData()
            collectionView.collectionViewLayout?.invalidateLayout()
            restoreVisibleAnchor(visibleAnchorID, in: collectionView)
            return
        }

        if oldExpandedID != newExpandedID {
            reloadExpandedItems(oldExpandedID: oldExpandedID, newExpandedID: newExpandedID)
            collectionView.collectionViewLayout?.invalidateLayout()
            return
        }
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

        let index = indexPath.item
        let model = items[index]
        articleItem.configure(
            model: model,
            onToggleExpanded: { [weak self] article in
                self?.onToggleExpanded(article)
            },
            onOpenInPreview: { [weak self] article in
                self?.onOpenInPreview(article)
            },
            onArticleAction: { [weak self] article, mutation in
                self?.onArticleAction(article, mutation)
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

        let model = items[indexPath.item]
        guard model.isExpanded else {
            return NSSize(width: width, height: CGFloat(model.density.collapsedCardHeight))
        }

        let key = model.heightCacheKey(width: width)
        if let cached = heightCache.height(for: key) {
            return NSSize(width: width, height: cached)
        }

        let measured = measureHeight(for: model, width: width)
        heightCache.setHeight(measured, for: key)
        return NSSize(width: width, height: measured)
    }

    @objc func clipViewBoundsChanged(_ notification: Notification) {
        guard let collectionView else {
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

    private func measureHeight(for model: ArticleFeedItemModel, width: CGFloat) -> CGFloat {
        let view = ArticleFeedCard(
            article: model.article,
            isExpanded: model.isExpanded,
            hackerNewsMetadata: model.hackerNewsMetadata,
            metadataText: model.metadataText,
            previewText: model.previewText,
            onToggleExpanded: {},
            onOpenInPreview: {},
            onArticleAction: { _, _ in }
        )
        .environment(\.newsprintTheme, model.theme)
        .environment(\.readerFontChoice, model.readerFontChoice)
        .environment(\.readerFontSize, model.readerFontSize)
        .environment(\.articleListDensity, model.density)
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
            collectionView.reloadData()
        } else {
            for id in ids {
                heightCache.removeHeights(articleID: id)
            }
            collectionView.reloadItems(at: Set(indexPaths))
        }
    }

    private func appearanceKey(for item: ArticleFeedItemModel) -> String {
        [
            item.theme.choice.rawValue,
            item.readerFontChoice.rawValue,
            "\(item.readerFontSize)",
            item.density.rawValue
        ].joined(separator: "|")
    }

    private func updateLayoutSpacing(for items: [ArticleFeedItemModel]) {
        guard let density = items.first?.density else {
            return
        }
        layout?.minimumLineSpacing = density.rowVerticalPadding + 10
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

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func configure(
        model: ArticleFeedItemModel,
        onToggleExpanded: @escaping (Article) -> Void,
        onOpenInPreview: @escaping (Article) -> Void,
        onArticleAction: @escaping (Article, ArticleStateMutation) -> Void
    ) {
        let rootView = AnyView(
            ArticleFeedCard(
                article: model.article,
                isExpanded: model.isExpanded,
                hackerNewsMetadata: model.hackerNewsMetadata,
                metadataText: model.metadataText,
                previewText: model.previewText,
                onToggleExpanded: {
                    onToggleExpanded(model.article)
                },
                onOpenInPreview: {
                    onOpenInPreview(model.article)
                },
                onArticleAction: onArticleAction
            )
            .environment(\.newsprintTheme, model.theme)
            .environment(\.readerFontChoice, model.readerFontChoice)
            .environment(\.readerFontSize, model.readerFontSize)
            .environment(\.articleListDensity, model.density)
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
}
