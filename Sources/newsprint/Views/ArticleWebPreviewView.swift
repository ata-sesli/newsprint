import SwiftUI
import WebKit
import newsprintCore

struct ArticleWebPreviewView: NSViewRepresentable {
    @Environment(\.webPreviewHorizontalPadding) private var horizontalPadding
    let url: URL?

    func makeCoordinator() -> ArticleWebPreviewCoordinator {
        ArticleWebPreviewCoordinator(horizontalPadding: horizontalPadding)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsAirPlayForMediaPlayback = false
        WebContentBlocker.install(on: configuration.userContentController)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: ArticleWebPreviewCoordinator.paddingScript(horizontalPadding),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.horizontalPadding = horizontalPadding
        context.coordinator.applyPadding(to: webView)

        guard let url else {
            webView.loadHTMLString("", baseURL: nil)
            return
        }

        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

@MainActor
final class ArticleWebPreviewCoordinator: NSObject, WKNavigationDelegate {
    var horizontalPadding: Int

    init(horizontalPadding: Int) {
        self.horizontalPadding = horizontalPadding
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyPadding(to: webView)
    }

    func applyPadding(to webView: WKWebView) {
        webView.evaluateJavaScript(Self.paddingScript(horizontalPadding))
    }

    static func paddingScript(_ padding: Int) -> String {
        let clamped = min(max(padding, 0), 32)
        if clamped == 0 {
            return """
            (() => {
              document.getElementById('newsprint-web-preview-inset')?.remove();
            })();
            """
        }

        return """
        (() => {
          let style = document.getElementById('newsprint-web-preview-inset');
          if (!style) {
            style = document.createElement('style');
            style.id = 'newsprint-web-preview-inset';
            document.head.appendChild(style);
          }
          style.textContent = `html, body { box-sizing: border-box; } body { padding-left: \(clamped)px !important; padding-right: \(clamped)px !important; }`;
        })();
        """
    }
}

enum WebContentBlocker {
    @MainActor
    static func install(on userContentController: WKUserContentController) {
        WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: WebContentBlockerRules.identifier) { ruleList, _ in
            if let ruleList {
                userContentController.add(ruleList)
                return
            }

            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: WebContentBlockerRules.identifier,
                encodedContentRuleList: WebContentBlockerRules.json
            ) { compiledRuleList, error in
                if let compiledRuleList {
                    userContentController.add(compiledRuleList)
                } else if let error {
                    NewsprintLog.ui.warning("Content blocker compilation failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
