import SwiftUI
import WebKit

/// The authenticated API response is rendered locally. Web content never gets the Token.
struct ReadmeHTMLView: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    var scrolling = false
    @Binding var height: CGFloat
    let openLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false; web.backgroundColor = .clear; web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = scrolling; web.allowsLinkPreview = false
        web.navigationDelegate = context.coordinator
        if !scrolling {
            context.coordinator.sizeObservation = web.scrollView.observe(\.contentSize, options: [.new]) { [weak coordinator = context.coordinator] _, change in
                guard let size = change.newValue, size.height.isFinite else { return }
                let measured = min(max(44, size.height), ReadmeDocumentRules.inlineHeightLimit)
                DispatchQueue.main.async {
                    guard let coordinator, abs(coordinator.parent.height - measured) > 0.5 else { return }
                    coordinator.parent.height = measured
                }
            }
        }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        let identity = (baseURL?.absoluteString ?? "") + "\n" + html
        guard context.coordinator.identity != identity else { return }
        context.coordinator.identity = identity
        web.loadHTMLString(ReadmeDocumentRules.document(html), baseURL: baseURL)
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.sizeObservation?.invalidate(); web.stopLoading(); web.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ReadmeHTMLView
        var identity: String?
        var sizeObservation: NSKeyValueObservation?
        init(_ parent: ReadmeHTMLView) { self.parent = parent }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if action.navigationType == .linkActivated || action.targetFrame == nil {
                if ReadmeDocumentRules.isLocalAnchor(url, base: parent.baseURL) { decisionHandler(.allow); return }
                decisionHandler(.cancel)
                if let safe = CommunityRules.webURL(url.absoluteString) { parent.openLink(safe) }
                return
            }
            decisionHandler(url.scheme == "about" || url == parent.baseURL ? .allow : .cancel)
        }
    }
}

struct ReadmeDocumentBody: View {
    let document: ReadmeDocument
    let baseURL: URL?
    var api: GitHub? = nil
    let expanded: Bool
    @Binding var height: CGFloat
    @State private var readingLink: ReadingLink?
    var body: some View {
        Group {
            if let html = document.html {
                ReadmeHTMLView(html: html, baseURL: baseURL, height: $height) { readingLink = ReadingLink(url: $0) }
                    .frame(height: expanded ? height : min(height, ReadmeDocumentRules.collapsedHeight))
                    .clipped()
            } else if let source = document.source {
                VStack(alignment: .leading, spacing: 8) {
                    Text("排版暂不可用，已显示原文。").font(.caption).foregroundStyle(.secondary)
                    Text(expanded ? source : ReadmePreviewRules.preview(source)).textSelection(.enabled)
                }
            }
        }
        .sheet(item: $readingLink) { ReadingLinkDestination(url: $0.url, api: api) }
    }
}
