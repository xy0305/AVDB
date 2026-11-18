import SwiftUI
import WebKit

/// Build 353 supplement: avfan sign-in, ported from AVFan's locked
/// scheme — the form looks native, but submission happens on the
/// site's real sign-in page inside a WKWebView (the captcha is solved
/// there; that is the normal path). Credentials are typed into the
/// page itself: this code never sends them anywhere else and never
/// stores the password. On success the WebView's cookies are exported
/// into the shared cookie storage, so AvfanClient fetches (board
/// matching + detail pages) immediately carry the login state.
struct AvfanLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var session = AvfanSession.shared
    @State private var account = ""
    @State private var password = ""
    @State private var ageConfirmed = false
    @State private var webEvent: AvfanLoginEvent = .idle
    @State private var reloadToken = 0

    var body: some View {
        NavigationStack {
            Form {
                if session.isSignedIn {
                    Section("当前状态") {
                        Label(session.displayName.map { "已登录：\($0)" } ?? "已登录 avfan", systemImage: "person.crop.circle.badge.checkmark")
                        Button("退出登录", role: .destructive) {
                            Task {
                                await session.signOut()
                                dismiss()
                            }
                        }
                    }
                } else {
                    Section("账号") {
                        TextField("邮箱或用户名", text: $account)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField("密码", text: $password)
                            .textContentType(.password)
                    }
                    Section {
                        Toggle("我已年满 18 岁", isOn: $ageConfirmed)
                    } footer: {
                        Text("站点会要求年龄确认；勾选后会写入站点的 legal_age 确认 Cookie。")
                    }
                    Section {
                        AvfanLoginWebView(
                            account: account,
                            password: password,
                            reloadToken: reloadToken,
                            event: $webEvent
                        )
                        .frame(height: 430)
                        .listRowInsets(EdgeInsets())
                    } header: {
                        Text("网页登录")
                    } footer: {
                        Text(statusText)
                    }
                    Section {
                        Button("重新加载登录页") {
                            reloadToken += 1
                        }
                    }
                }
            }
            .navigationTitle("avfan 登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                if ageConfirmed {
                    await AvfanCookieBridge.applyLegalAgeCookie()
                }
            }
            .onChange(of: ageConfirmed) { _, confirmed in
                if confirmed {
                    Task { await AvfanCookieBridge.applyLegalAgeCookie() }
                }
            }
            .onChange(of: webEvent) { _, event in
                if event == .signedIn {
                    Task {
                        session.markSignedIn()
                        await AvfanCookieBridge.exportWebKitToShared()
                        await AvfanClient.shared.clearCache()
                        dismiss()
                    }
                }
            }
        }
    }

    private var statusText: String {
        switch webEvent {
        case .idle, .loading:
            return "在上方表单填写账号密码后，网页会自动填入并提交；出现验证码时直接在网页里完成。"
        case .filled:
            return "已填入账号密码，等待网页提交…"
        case .needsCaptcha:
            return "请在网页里完成验证码，完成后会自动继续。"
        case .injectionFailed:
            return "自动填入失败，请直接在网页里输入账号密码登录。"
        case .stillOnLogin:
            return "仍停留在登录页，请检查账号密码或完成验证码。"
        case .signedIn:
            return "登录成功。"
        case .pageError(let message):
            return "页面错误：\(message)"
        }
    }
}

enum AvfanLoginEvent: Equatable {
    case idle
    case loading
    case filled
    case needsCaptcha
    case injectionFailed
    case stillOnLogin
    case signedIn
    case pageError(String)
}

/// The real avfan sign-in page in a WebView; typed credentials are
/// injected into the page's own form fields and the page's own submit
/// runs — this view never calls any session endpoint itself.
private struct AvfanLoginWebView: UIViewRepresentable {
    let account: String
    let password: String
    let reloadToken: Int
    @Binding var event: AvfanLoginEvent

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = AvfanClient.mobileSafariUA
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        load(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.didInject = false
            context.coordinator.didSucceed = false
            load(into: webView)
        }
    }

    private func load(into webView: WKWebView) {
        var request = URLRequest(url: AvfanSession.signInURL())
        request.setValue(AvfanClient.mobileSafariUA, forHTTPHeaderField: "User-Agent")
        webView.load(request)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AvfanLoginWebView
        weak var webView: WKWebView?
        var lastReloadToken = 0
        var didInject = false
        var didSucceed = false
        private var retryWork: DispatchWorkItem?

        init(parent: AvfanLoginWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            evaluateState(in: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.event = .pageError(error.localizedDescription)
        }

        private func evaluateState(in webView: WKWebView) {
            let probe = """
            (function() {
              var path = location.pathname || '';
              var hasSignOut = !!document.querySelector('a[href*="sign_out"], a[href*="logout"], form[action*="sign_out"]');
              var bodyText = document.body ? document.body.innerText : '';
              if (hasSignOut || bodyText.indexOf('退出登录') >= 0 || bodyText.indexOf('登出') >= 0) return 'signed-in';
              if (path.indexOf('sign_in') >= 0 || document.querySelector('input[name="session[password]"]')) return 'login';
              return 'other';
            })()
            """
            webView.evaluateJavaScript(probe) { [weak self] result, _ in
                guard let self else { return }
                let state = (result as? String) ?? "other"
                if state == "signed-in" {
                    if !self.didSucceed {
                        self.didSucceed = true
                        self.parent.event = .signedIn
                    }
                    return
                }
                if state == "login" {
                    self.parent.event = .loading
                    self.injectCredentials(into: webView)
                } else {
                    self.scheduleRecheck(in: webView)
                }
            }
        }

        private func injectCredentials(into webView: WKWebView) {
            let account = parent.account.trimmingCharacters(in: .whitespacesAndNewlines)
            let password = parent.password
            guard !didInject, !account.isEmpty, !password.isEmpty else { return }
            didInject = true
            let script = """
            (function() {
              function setValue(el, value) {
                if (!el) return false;
                var proto = Object.getPrototypeOf(el);
                var desc = Object.getOwnPropertyDescriptor(proto, 'value');
                if (desc && desc.set) { desc.set.call(el, value); } else { el.value = value; }
                el.dispatchEvent(new Event('input', {bubbles: true}));
                el.dispatchEvent(new Event('change', {bubbles: true}));
                return true;
              }
              var user = document.querySelector('#session_email_or_username, input[name="session[email_or_username]"], input[name="session_email_or_username"], input[type="email"], input[name*="email"], input[name*="username"]');
              var pass = document.querySelector('input[name="session[password]"], input[type="password"]');
              if (!user || !pass) return 'missing-fields';
              var okUser = setValue(user, \(jsString(account)));
              var okPass = setValue(pass, \(jsString(password)));
              if (!okUser || !okPass) return 'fill-failed';
              var captcha = document.querySelector('input[name*="rucaptcha" i], input[id*="rucaptcha" i], .cf-turnstile, iframe[src*="turnstile"], iframe[src*="captcha"]');
              if (captcha) return 'captcha';
              var submit = document.querySelector('input[type="submit"], button[type="submit"], form input[name="commit"]');
              if (submit) { submit.click(); return 'submitted'; }
              if (pass.form) { pass.form.requestSubmit ? pass.form.requestSubmit() : pass.form.submit(); return 'submitted'; }
              return 'no-submit';
            })()
            """
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self else { return }
                switch (result as? String) ?? "" {
                case "submitted":
                    self.parent.event = .filled
                    self.scheduleRecheck(in: webView, delay: 2.5)
                case "captcha":
                    self.parent.event = .needsCaptcha
                    self.scheduleRecheck(in: webView, delay: 4)
                case "missing-fields", "fill-failed", "no-submit":
                    self.parent.event = .injectionFailed
                default:
                    self.parent.event = .injectionFailed
                }
            }
        }

        private func scheduleRecheck(in webView: WKWebView, delay: TimeInterval = 3) {
            retryWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView, !self.didSucceed else { return }
                self.evaluateState(in: webView)
                if !self.didSucceed, self.parent.event != .signedIn {
                    if (webView.url?.path.contains("sign_in") ?? false), self.didInject {
                        self.parent.event = .stillOnLogin
                    }
                }
            }
            retryWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private func jsString(_ value: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [value]),
                  let text = String(data: data, encoding: .utf8) else { return "\"\"" }
            return String(text.dropFirst().dropLast())
        }
    }
}
