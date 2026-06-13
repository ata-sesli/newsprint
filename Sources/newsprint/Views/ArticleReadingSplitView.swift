import AppKit
import SwiftData
import SwiftUI

struct ArticleReadingSplitView<Feed: View, Preview: View>: NSViewControllerRepresentable {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.newsprintTheme) private var theme
    @Environment(\.readerFontChoice) private var readerFontChoice
    @Environment(\.readerFontSize) private var readerFontSize
    @Environment(\.articleListDensity) private var articleListDensity

    @Binding var isPreviewCollapsed: Bool
    private let feed: Feed
    private let preview: Preview

    init(
        isPreviewCollapsed: Binding<Bool>,
        @ViewBuilder feed: () -> Feed,
        @ViewBuilder preview: () -> Preview
    ) {
        self._isPreviewCollapsed = isPreviewCollapsed
        self.feed = feed()
        self.preview = preview()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPreviewCollapsed: $isPreviewCollapsed)
    }

    func makeNSViewController(context: Context) -> ArticleReadingSplitViewController {
        ArticleReadingSplitViewController(
            feed: prepared(feed),
            preview: prepared(preview),
            isPreviewCollapsed: isPreviewCollapsed
        )
    }

    func updateNSViewController(_ controller: ArticleReadingSplitViewController, context: Context) {
        context.coordinator.isPreviewCollapsed = $isPreviewCollapsed
        controller.update(
            feed: prepared(feed),
            preview: prepared(preview),
            isPreviewCollapsed: isPreviewCollapsed
        )
    }

    private func prepared<V: View>(_ view: V) -> AnyView {
        AnyView(
            view
                .modelContext(modelContext)
                .environment(\.newsprintTheme, theme)
                .environment(\.readerFontChoice, readerFontChoice)
                .environment(\.readerFontSize, readerFontSize)
                .environment(\.articleListDensity, articleListDensity)
                .preferredColorScheme(theme.colorScheme)
                .tint(theme.tint)
        )
    }

    final class Coordinator {
        var isPreviewCollapsed: Binding<Bool>

        init(isPreviewCollapsed: Binding<Bool>) {
            self.isPreviewCollapsed = isPreviewCollapsed
        }
    }
}

@MainActor
final class ArticleReadingSplitViewController: NSSplitViewController {
    private let feedHost: NSHostingController<AnyView>
    private let previewHost: NSHostingController<AnyView>
    private let previewItem: NSSplitViewItem

    init(feed: AnyView, preview: AnyView, isPreviewCollapsed: Bool) {
        feedHost = NSHostingController(rootView: feed)
        previewHost = NSHostingController(rootView: preview)
        previewItem = NSSplitViewItem(viewController: previewHost)
        super.init(nibName: nil, bundle: nil)

        splitView.autosaveName = "NewsprintArticlePreviewSplitView"
        splitView.dividerStyle = .thin

        let feedItem = NSSplitViewItem(viewController: feedHost)
        feedItem.minimumThickness = 420
        previewItem.minimumThickness = 360
        previewItem.preferredThicknessFraction = 0.42
        previewItem.isCollapsed = isPreviewCollapsed

        addSplitViewItem(feedItem)
        addSplitViewItem(previewItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(feed: AnyView, preview: AnyView, isPreviewCollapsed: Bool) {
        feedHost.rootView = feed
        previewHost.rootView = preview
        if previewItem.isCollapsed != isPreviewCollapsed {
            previewItem.animator().isCollapsed = isPreviewCollapsed
        }
    }
}
