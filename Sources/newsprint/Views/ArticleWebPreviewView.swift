import SwiftUI
import WebKit
import newsprintCore

struct ArticleWebPreviewView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsAirPlayForMediaPlayback = false
        WebContentBlocker.install(on: configuration.userContentController)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let url else {
            webView.loadHTMLString("", baseURL: nil)
            return
        }

        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
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
