import AppKit
import SwiftUI
import newsprintCore

struct ArticleFeedCollectionView: NSViewRepresentable {
    let items: [ArticleFeedItemModel]
    let reloadGeneration: Int
    let onToggleExpanded: (Article) -> Void
    let onNearEnd: (Int) -> Void
    let onArticleAction: (Article, ArticleStateMutation) -> Void

    func makeCoordinator() -> ArticleFeedCollectionCoordinator {
        ArticleFeedCollectionCoordinator(
            items: items,
            reloadGeneration: reloadGeneration,
            onToggleExpanded: onToggleExpanded,
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
            onToggleExpanded: onToggleExpanded,
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
    private let heightCache = ArticleFeedHeightCache()
    private var lastLayoutWidth: CGFloat = 0
    private var onToggleExpanded: (Article) -> Void
    private var onNearEnd: (Int) -> Void
    private var onArticleAction: (Article, ArticleStateMutation) -> Void

    init(
        items: [ArticleFeedItemModel],
        reloadGeneration: Int,
        onToggleExpanded: @escaping (Article) -> Void,
        onNearEnd: @escaping (Int) -> Void,
        onArticleAction: @escaping (Article, ArticleStateMutation) -> Void
    ) {
        self.items = items
        self.reloadGeneration = reloadGeneration
        self.onToggleExpanded = onToggleExpanded
        self.onNearEnd = onNearEnd
        self.onArticleAction = onArticleAction
    }

    func update(
        items newItems: [ArticleFeedItemModel],
        reloadGeneration newReloadGeneration: Int,
        onToggleExpanded: @escaping (Article) -> Void,
        onNearEnd: @escaping (Int) -> Void,
        onArticleAction: @escaping (Article, ArticleStateMutation) -> Void
    ) {
        updateLayoutSpacing(for: newItems)

        let oldIDs = items.map(\.id)
        let oldExpandedID = items.first(where: \.isExpanded)?.id
        let oldAppearanceKey = items.first.map(appearanceKey)
        let oldReloadGeneration = reloadGeneration
        let newIDs = newItems.map(\.id)
        let newExpandedID = newItems.first(where: \.isExpanded)?.id
        let newAppearanceKey = newItems.first.map(appearanceKey)

        items = newItems
        reloadGeneration = newReloadGeneration
        self.onToggleExpanded = onToggleExpanded
        self.onNearEnd = onNearEnd
        self.onArticleAction = onArticleAction

        guard let collectionView else {
            return
        }

        if oldReloadGeneration != newReloadGeneration || oldIDs != newIDs || oldAppearanceKey != newAppearanceKey {
            heightCache.removeAll()
            collectionView.reloadData()
            collectionView.collectionViewLayout?.invalidateLayout()
            return
        }

        if oldExpandedID != newExpandedID {
            reloadExpandedItems(oldExpandedID: oldExpandedID, newExpandedID: newExpandedID)
            collectionView.collectionViewLayout?.invalidateLayout()
            return
        }

        collectionView.reloadData()
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
        notifyNearEndIfNeeded(index: index)

        let model = items[index]
        articleItem.configure(
            model: model,
            onToggleExpanded: { [weak self] article in
                self?.onToggleExpanded(article)
            },
            onArticleAction: { [weak self] article, mutation in
                self?.onArticleAction(article, mutation)
            }
        )
        return articleItem
    }

    private func notifyNearEndIfNeeded(index: Int) {
        guard index >= max(0, items.count - ArticleFeedStore.loadMoreThreshold) else {
            return
        }
        onNearEnd(index)
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
        guard abs(width - lastLayoutWidth) > 1 else {
            return
        }

        lastLayoutWidth = width
        heightCache.removeAll()
        collectionView.collectionViewLayout?.invalidateLayout()
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
            onToggleExpanded: {},
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
        onArticleAction: @escaping (Article, ArticleStateMutation) -> Void
    ) {
        let rootView = AnyView(
            ArticleFeedCard(
                article: model.article,
                isExpanded: model.isExpanded,
                hackerNewsMetadata: model.hackerNewsMetadata,
                metadataText: model.metadataText,
                onToggleExpanded: {
                    onToggleExpanded(model.article)
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
