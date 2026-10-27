import Foundation

#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit

/// Hidden WKWebView that loads allowlisted ranking URLs, completes the official
/// adult self-declaration when authorized, waits for ranked DOM, and returns HTML
/// for `DMMRankingCore`. Uses a non-persistent data store; never copies Safari cookies.
@MainActor
final class DMMRankingHydrator: NSObject, WKNavigationDelegate {
    static let shared = DMMRankingHydrator()

    private var webView: WKWebView?
    private var hostWindow: UIWindow?
    private var continuation: CheckedContinuation<(String, URL), Error>?
    private var authorize = false
    private var targetKind: DMMRankingKind = .weekly
    private var declared = false
    private var pollTask: Task<Void, Never>?
    private var finished = false
    private let timeoutSeconds: TimeInterval = 28

    func document(kind: DMMRankingKind, authorizeAdultDeclaration: Bool) async throws -> (String, URL) {
        cancel()
        authorize = authorizeAdultDeclaration
        targetKind = kind
        declared = false
        finished = false
        guard authorizeAdultDeclaration else { throw DMMRankingError.accessGate }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        view.navigationDelegate = self
        view.isOpaque = false
        view.alpha = 0.01
        // Prefer Japanese age_check path that matches DMMTransport allowlist.
        view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.windowLevel = .normal - 1
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(view)
        window.isHidden = false
        hostWindow = window
        webView = view

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(String, URL), Error>) in
            self.continuation = cont
            var request = URLRequest(url: kind.sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("ja-JP,ja;q=0.9", forHTTPHeaderField: "Accept-Language")
            view.load(request)
            self.pollTask = Task { [weak self] in
                let deadline = Date().addingTimeInterval(self?.timeoutSeconds ?? 28)
                while Date() < deadline {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard let self, !Task.isCancelled else { return }
                    await self.probeReady()
                }
                await MainActor.run { self?.fail(.accessGate) }
            }
        }
    }

    static func cancelActive() { shared.cancel() }

    func cancel() {
        pollTask?.cancel(); pollTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        hostWindow?.isHidden = true
        hostWindow = nil
        if let cont = continuation {
            continuation = nil
            cont.resume(throwing: CancellationError())
        }
        finished = true
    }

    private func succeed(_ html: String, _ url: URL) {
        guard !finished else { return }
        finished = true
        pollTask?.cancel(); pollTask = nil
        let cont = continuation
        continuation = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        hostWindow?.isHidden = true
        hostWindow = nil
        cont?.resume(returning: (html, url))
    }

    private func fail(_ error: DMMRankingError) {
        guard !finished else { return }
        finished = true
        pollTask?.cancel(); pollTask = nil
        let cont = continuation
        continuation = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        hostWindow?.isHidden = true
        hostWindow = nil
        cont?.resume(throwing: error)
    }

    private func probeReady() async {
        guard let webView, !finished, let pageURL = webView.url else { return }
        if isAgeURL(pageURL) {
            await handleAgePageIfNeeded(webView, pageURL: pageURL)
            return
        }
        guard DMMRankingKind.from(url: pageURL) == targetKind else { return }
        let expected = targetKind.expectedCount
        let js: String
        if targetKind.isActress {
            js = """
            (function(){
              var links = Array.from(document.querySelectorAll('a[href*=\"actress=\"]'));
              var ranks = document.body ? (document.body.innerText.match(/[0-9]+位/g) || []) : [];
              return JSON.stringify({links: links.length, ranks: ranks.length, html: document.documentElement ? document.documentElement.outerHTML : ''});
            })()
            """
        } else {
            js = """
            (function(){
              var titles = document.querySelectorAll('a[data-e2eid=\"title\"]').length;
              return JSON.stringify({titles: titles, html: document.documentElement ? document.documentElement.outerHTML : ''});
            })()
            """
        }
        guard let raw = try? await webView.evaluateJavaScript(js) as? String,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = obj["html"] as? String, html.count <= 8_000_000 else { return }
        if targetKind.isActress {
            let links = obj["links"] as? Int ?? 0
            guard links >= expected else { return }
        } else {
            let titles = obj["titles"] as? Int ?? 0
            guard titles >= expected else { return }
        }
        if let board = try? DMMRankingCore.board(html: html, responseURL: pageURL, observedAt: Date()),
           board.kind == targetKind, board.count == expected {
            succeed(html, pageURL)
        }
    }

    private func isAgeURL(_ url: URL) -> Bool {
        guard url.host == "www.dmm.co.jp" else { return false }
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? ""
        return path == "/age_check/=/" || path == "/en/age_check/=/" || path.hasPrefix("/age_check/") || path.hasPrefix("/en/age_check/")
    }

    private func handleAgePageIfNeeded(_ webView: WKWebView, pageURL: URL) async {
        guard authorize, !declared else {
            if !authorize { fail(.accessGate) }
            return
        }
        let js = """
        (function(){
          var n = document.getElementById('__NEXT_DATA__');
          var href = null;
          try {
            if (n && n.textContent) {
              var j = JSON.parse(n.textContent);
              href = j && j.props && j.props.pageProps && j.props.pageProps.yesButtonLink;
            }
          } catch (e) {}
          if (!href) {
            var a = Array.from(document.querySelectorAll('a')).find(function(el){
              return (el.textContent || '').indexOf('18') >= 0 && (el.href || '').indexOf('declared=yes') >= 0;
            });
            href = a ? a.href : null;
          }
          return href || '';
        })()
        """
        guard let href = try? await webView.evaluateJavaScript(js) as? String, !href.isEmpty,
              let yes = URL(string: href), DMMTransport.allowed(yes),
              (URLComponents(url: yes, resolvingAgainstBaseURL: false)?.path == "/age_check/=/declared=yes/"
                || URLComponents(url: yes, resolvingAgainstBaseURL: false)?.path == "/en/age_check/=/declared=yes/") else {
            fail(.accessGate)
            return
        }
        // Prefer Japanese declared path used by DMMTransport when EN wrapper appears.
        let navigate: URL
        if let components = URLComponents(url: yes, resolvingAgainstBaseURL: false),
           components.path.hasPrefix("/en/"),
           let rurl = components.queryItems?.first(where: { $0.name == "rurl" })?.value {
            var rebuilt = URLComponents()
            rebuilt.scheme = "https"; rebuilt.host = "www.dmm.co.jp"
            rebuilt.path = "/age_check/=/declared=yes/"
            rebuilt.queryItems = [URLQueryItem(name: "rurl", value: rurl)]
            if let url = rebuilt.url, DMMTransport.allowed(url) { navigate = url } else { navigate = yes }
        } else {
            navigate = yes
        }
        declared = true
        var request = URLRequest(url: navigate, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("ja-JP,ja;q=0.9", forHTTPHeaderField: "Accept-Language")
        webView.load(request)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel); return
        }
        if DMMTransport.allowed(url) || isAgeURL(url) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            // Cross-domain / login fail closed.
            if url.host == "accounts.dmm.co.jp" { fail(.accessGate) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await probeReady() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if !finished { fail(.accessGate) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if !finished { fail(.accessGate) }
    }
}
#else
enum DMMRankingHydrator {
    static func document(kind: DMMRankingKind, authorizeAdultDeclaration: Bool) async throws -> (String, URL) {
        throw DMMRankingError.accessGate
    }
    static func cancelActive() {}
}
#endif
