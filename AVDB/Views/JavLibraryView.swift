import SwiftUI
import WebKit

struct JavLibraryView: View {
    @StateObject private var source = JavLibrarySource()
    @AppStorage("javlibrary.adultConfirmed") private var adultConfirmed = false
    @State private var kind: JLRanking = .mostWanted
    @State private var filter = ""
    @State private var page = JLPage()
    @State private var loading = false
    @State private var message = ""
    @State private var challenge = false
    @State private var verification = false
    @State private var settings = false
    @State private var visited = Set<URL>()
    private var startURL: URL { JLPolicy.route(kind, mode: filter, base: source.base) }
    var body: some View {
        Group {
            if !adultConfirmed {
                ContentUnavailableView { Label("仅限成年人", systemImage: "18.circle") } description: {
                    Text("仅在已满 18 岁且当地法律允许时浏览公开元数据。")
                } actions: { Button("我已满 18 岁，继续") { adultConfirmed = true } }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("独立来源 · \(source.base.host ?? "")").font(.caption).foregroundStyle(.secondary)
                        Picker("榜单", selection: $kind) { ForEach(JLRanking.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                        if !page.filters.isEmpty {
                            Picker("来源时间范围", selection: $filter) {
                                Text("来源默认").tag("")
                                ForEach(page.filters) { Text($0.title).tag($0.value) }
                            }
                        }
                        if loading { ProgressView("正在读取公开榜单…") }
                        if !message.isEmpty {
                            Text(message).foregroundStyle(.secondary)
                            Button("重试") { Task { await fetch(startURL, reset: true) } }.disabled(loading)
                        }
                        if challenge { Button("打开来源网站，手动完成验证") { verification = true } }
                        GeometryReader { geometry in
                            Color.clear.preference(key: JLWidthKey.self, value: geometry.size.width)
                        }.frame(height: 0)
                        JLVideoGrid(videos: page.videos)
                        ForEach(page.actors) { actor in
                            HStack {
                                if let rank = actor.rank { Text("#\(rank)").monospacedDigit() }
                                AsyncImage(url: actor.image) { $0.resizable().scaledToFit() } placeholder: { Image(systemName: "person") }.frame(width: 48, height: 64)
                                Text(actor.name)
                                Spacer()
                                Link("来源演员页", destination: actor.url)
                            }
                        }
                        if !page.actors.isEmpty { Text("演员身份未唯一验证，不猜测 JavDB ID；使用明确的来源演员页。该链接为网站浏览，不是原生内容容器。").font(.footnote).foregroundStyle(.secondary) }
                        if let next = page.next, !visited.contains(next) {
                            Button("下一页（来源分页）") { Task { await fetch(next, reset: false) } }.disabled(loading)
                        }
                    }.padding(AdaptiveLayout.horizontalPadding)
                }
                .refreshable { await fetch(startURL, reset: true) }
                .task(id: "\(kind.rawValue)|\(filter)|\(source.generation)") { await fetch(startURL, reset: true) }
            }
        }
        .navigationTitle("JavLibrary 榜单").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { settings = true } label: { Image(systemName: "gearshape") } }
        .sheet(isPresented: $settings) { NavigationStack { JLSettingsView(source: source) } }
        .sheet(isPresented: $verification) {
            JLVerificationView(source: source, url: startURL) {
                verification = false
                Task { await fetch(startURL, reset: true) }
            }
        }
    }
    @MainActor private func fetch(_ url: URL, reset: Bool) async {
        guard !loading else { return }
        loading = true; message = ""; challenge = false
        let epoch = source.generation
        defer { loading = false }
        if reset { page = JLPage(); visited = [] }
        do {
            let result = try await source.load(url)
            guard !Task.isCancelled, epoch == source.generation else { return }
            visited.insert(url)
            if reset { page = result } else {
                let ids = Set(page.videos.map(\.id)); let actors = Set(page.actors.map(\.id))
                page.videos += result.videos.filter { !ids.contains($0.id) }
                page.actors += result.actors.filter { !actors.contains($0.id) }
                page.next = result.next
            }
        } catch is CancellationError {} catch {
            guard epoch == source.generation else { return }
            message = error.localizedDescription
            if case JLError.verification = error { challenge = true }
        }
    }
}
private struct JLWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 390
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct JLVideoGrid: View {
    let videos: [JLVideo]
    @State private var width: CGFloat = 390
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: AdaptiveLayout.columnCount(width: width, padding: AdaptiveLayout.gridPadding, spacing: 12)), spacing: 16) {
            ForEach(videos) { video in
                NavigationLink { JLVideoDestination(video: video) } label: {
                    // The source-local ID is a display identity only; never sent to movieDetail.
                    MoviePosterCard(movie: Movie(id: "javlibrary:\(video.id)", number: video.code, title: video.title, thumbURL: video.image, coverURL: video.image))
                }.buttonStyle(.plain)
            }
        }.onPreferenceChange(JLWidthKey.self) { width = $0 }
    }
}
private struct JLVideoDestination: View {
    let video: JLVideo
    @State private var movie: Movie?
    @State private var loading = true
    @State private var message = ""
    var body: some View {
        Group {
            if let movie { MovieDetailView(movieID: movie.id) }
            else if loading { ProgressView("精确匹配番号 \(video.code)…") }
            else {
                ContentUnavailableView { Label(video.code, systemImage: "doc.text.magnifyingglass") } description: {
                    Text(message)
                } actions: { Link("在来源网站查看", destination: video.url) }
            }
        }.task {
            defer { loading = false }
            do {
                if let match = try await JavDBSDK.shared.exactMovie(code: video.code),
                   JRPolicy.exactCode(match.number ?? "") == JRPolicy.exactCode(video.code) { movie = match }
                else { message = "未找到唯一、精确的 JavDB 番号匹配；不会使用来源 ID 伪造影片。" }
            } catch { message = "匹配暂不可用：\(error.localizedDescription)" }
        }
    }
}
private struct JLSettingsView: View {
    @ObservedObject var source: JavLibrarySource
    @Environment(\.dismiss) private var dismiss
    @State private var domain = ""
    @State private var message = ""
    var body: some View {
        Form {
            Section("独立 JavLibrary 来源域名") {
                TextField("https://www.javlibrary.com", text: $domain).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("保存") { do { try source.configure(domain); dismiss() } catch { message = error.localizedDescription } }
                Text(message)
            }
            Section {
                Text("只接受 HTTPS 根域名，不改变 JavDB / 115。更换域名会取消旧请求并清除验证会话。只有您明确配置并信任的站点会接收该站点的验证 Cookie。")
                Text("验证会话仅驻留内存，不写磁盘、不记录 Cookie。验证是否适用于设备网络和原生请求由网站决定，不保证成功。")
            }.font(.footnote)
        }.onAppear { domain = source.base.absoluteString }.navigationTitle("JavLibrary 设置")
        .toolbar { Button("关闭") { dismiss() } }
    }
}

// Visible, user-operated website browser only; never used to render native ranking content.
private struct JLVerificationView: View {
    @ObservedObject var source: JavLibrarySource
    let url: URL
    let finished: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = WKWebsiteDataStore.nonPersistent()
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("网站验证 · \(url.host ?? "")\n请自行完成网站验证；关闭后可重试。不会自动解题或保证通过。").font(.footnote).padding()
                JLWebsiteBrowser(url: url, store: store)
            }.navigationTitle("来源网站验证")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成并重试") {
                        let host = url.host ?? ""
                        store.httpCookieStore.getAllCookies { cookies in
                            Task { @MainActor in
                                source.acceptVerifiedCookies(cookies, host: host)
                                finished()
                            }
                        }
                    }
                }
            }
        }
    }
}
private struct JLWebsiteBrowser: UIViewRepresentable {
    let url: URL
    let store: WKWebsiteDataStore
    func makeCoordinator() -> Coordinator { Coordinator(host: url.host ?? "") }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        let host: String
        init(host: String) { self.host = host }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, url.scheme == "https" else { decisionHandler(.cancel); return }
            // The verification provider may load HTTPS subframes; top-level navigation stays on the configured host.
            if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow) }
            else { decisionHandler(url.host == host && navigationAction.targetFrame != nil ? .allow : .cancel) }
        }
    }
}
