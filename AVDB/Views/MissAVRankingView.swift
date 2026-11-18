import SwiftUI

// Route-owned lifetime: no shared URL cache or account metadata is persisted.
private final class MissAVRankingState: ObservableObject {
    @Published var actresses: [MissAVActress] = []
    @Published var actressTitle = "MissAV 女优排行"
    @Published var period = "weekly-hot"
    @Published var attempt = 0
    @Published var videos: [JRVideo] = []
    @Published var next: String?
    @Published var visited = Set<String>()
    @Published var error = ""
    @Published var loading = false
    @Published var paging = false
    var pageTask: Task<Void, Never>?
    var revision = UUID()
    @Published var anchor: String?
    var loadedKey: String?
    var requests = 0
}

// Additional source only: never changes JavDB ranking/search/playback state.
struct MissAVRankingView: View {
    @ObservedObject private var source = MissAVSource.shared
    @AppStorage("missav.adultConfirmed") private var adultConfirmed = false
    @ObservedObject private var matcher = AvfanMatchStore.shared
    @EnvironmentObject private var appState: AppState
    @StateObject private var state = MissAVRankingState()
    private var requestKey: String { "\(source.generation):\(state.period):\(state.attempt)" }
    var body: some View {
        Group {
            if adultConfirmed { content }
            else {
                ContentUnavailableView {
                    Label("仅限成年人", systemImage: "18.circle")
                } description: { Text("MissAV 含成人影片资料。仅在已满 18 岁且所在地法律允许时进入。") }
                actions: { Button("我已满 18 岁，继续") { adultConfirmed = true } }
            }
        }
        .onDisappear { state.pageTask?.cancel(); state.revision = UUID(); state.paging = false }
    }
    private var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("MissAV · 原站顺序").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink { MissAVSettingsView() } label: { Image(systemName: "gearshape") }
                }.padding(.horizontal)
                CapsuleChipBar(tabs: MissAVHTML.periods + [("actresses", "女优排行")], selection: $state.period)
                    .accessibilityIdentifier("missav-periods")
                Text("MissAV 提供排序和身份；封面、标题与详情来自 AVFan 按番号匹配，不改变排名。")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                if let status = matcher.statusText { Text(status).font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
                if state.loading { ProgressView("载入 MissAV 排行…") }
                if !state.error.isEmpty {
                    Text(state.error).font(.callout).padding(.horizontal)
                    Button(state.videos.isEmpty ? "重试排行" : "重试下一页") {
                        if state.videos.isEmpty { state.attempt += 1 } else { loadNext() }
                    }.buttonStyle(.bordered)
                    Link("在浏览器核对来源（不导入 Cookie）", destination: source.base)
                }
                if state.period == "actresses" {
                    Text(state.actressTitle).font(.headline)
                    Text("当前站点月榜；未发现独立日榜 / 周榜或分页，不虚构参数。")
                        .font(.caption).foregroundStyle(.secondary)
                    AvfanBoardActorGrid(actors: state.actresses)
                } else {
                    AvfanBoardGrid(videos: state.videos, scrollTargets: true, matchCode: { AvfanMatchStore.missAVMatchCode($0.code) }, onAppearLast: {
                        if state.next != nil { loadNext() }
                    })
                }
                if state.next != nil && !state.loading {
                    Button { loadNext() } label: {
                        if state.paging { AnyView(ProgressView()) } else { AnyView(Text("加载下一页（滑到底也会自动加载）")) }
                    }.disabled(state.paging).buttonStyle(.bordered).accessibilityIdentifier("missav-load-more")
                }
            }.padding(.vertical, 8)
        }
        .scrollPosition(id: $state.anchor, anchor: .top)
        .refreshable { await reload() }
        .task(id: requestKey) {
            // A pushed detail changes visibility, not the list query. SwiftUI
            // restarts tasks on pop; retain the same data and scroll container.
            if state.loadedKey != requestKey { await reload() }
        }
        .overlay(alignment: .topTrailing) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--missav-scroll-fixture") {
                Text("period=\(state.period) items=\(state.videos.count) requests=\(state.requests)")
                    .font(.caption2).accessibilityIdentifier("missav-diagnostics")
            }
            #endif
        }
    }
    @MainActor private func reload() async {
        state.pageTask?.cancel(); let token = UUID(); state.revision = token
        let key = requestKey
        state.loadedKey = nil; state.anchor = nil; state.requests += 1
        state.videos = []; state.actresses = []; state.next = nil; state.visited = []; state.error = ""; state.loading = true; state.paging = false
        let epoch = source.generation
        defer { if state.revision == token { state.loading = false } }
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--missav-scroll-fixture") {
                state.videos = fixtureVideos(1...24)
                state.next = "fixture-page-2"
                state.loadedKey = key
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--missav-navigation-fixture") {
                state.videos = [JRVideo(path: "/cn/test-101", code: "TEST-101", title: "Synthetic source", image: nil, subtitle: "")]
                state.actresses = [MissAVActress(path: "/cn/actresses/Synthetic", name: "Synthetic actor", aliases: ["Synthetic"], rank: 1)]
                state.actressTitle = "Synthetic monthly ranking (not live)"
                state.loadedKey = key
                return
            }
            #endif
            if state.period == "actresses" {
                let page = try await source.actressPage()
                guard !Task.isCancelled, state.revision == token, epoch == source.generation, key == requestKey else { return }
                state.actresses = page.actors; state.actressTitle = page.title; state.next = page.next
            for actress in page.actors { matcher.enqueueActor(name: actress.name) }
                state.visited.insert(MissAVHTML.actressRanking); state.loadedKey = key
                return
            }
            let path = source.routes[state.period] ?? MissAVHTML.routes[state.period]!
            let page = try await source.page(path)
            guard !Task.isCancelled, state.revision == token, epoch == source.generation, key == requestKey else { return }
            state.videos = page.videos; state.next = page.next; state.visited.insert(path); state.loadedKey = key
            // Build 353: queue avfan matching in display order (visible first).
            matcher.enqueue(codes: page.videos.map { AvfanMatchStore.missAVMatchCode($0.code) })
        } catch { if !Task.isCancelled && state.revision == token && epoch == source.generation && key == requestKey { state.error = error.localizedDescription } }
    }
    #if DEBUG
    private func fixtureVideos(_ range: ClosedRange<Int>) -> [JRVideo] {
        range.map { JRVideo(path: "/\(state.period)/neutral/\($0)", code: "TEST-\($0)", title: "Neutral film \($0)", image: nil, subtitle: "") }
    }
    #endif
    @MainActor private func loadNext() {
        guard !state.loading, !state.paging, let path = state.next else { return }
        let token = state.revision, epoch = source.generation, key = requestKey
        state.paging = true; state.error = ""
        state.pageTask = Task { @MainActor in
            defer { if state.revision == token { state.paging = false } }
            do {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--missav-scroll-fixture") {
                    // Deliberately slow and cancellation-resistant, so switching
                    // query while paging tests the production revision guard.
                    try? await Task.sleep(for: .seconds(ProcessInfo.processInfo.arguments.contains("--missav-slow-page") ? 20 : 2))
                    guard !Task.isCancelled, state.revision == token, epoch == source.generation, key == requestKey else { return }
                    state.videos.append(contentsOf: fixtureVideos(25...48))
                    state.next = nil; state.visited.insert(path)
                    return
                }
                #endif
                guard !state.visited.contains(path) else { throw JRError.message("来源返回重复分页，请刷新。") }
                if state.period == "actresses" {
                    let page = try await source.actressPage(path)
                    guard !Task.isCancelled, state.revision == token, epoch == source.generation, key == requestKey else { return }
                    let ids = Set(state.actresses.map(\.path))
                    let fresh = page.actors.filter { !ids.contains($0.path) }
                    guard !fresh.isEmpty else { throw JRError.message("来源返回重复女优分页，请刷新。") }
                    state.actresses.append(contentsOf: fresh); state.visited.insert(path)
                    for actress in fresh { matcher.enqueueActor(name: actress.name) }
                    state.next = page.next.flatMap { state.visited.contains($0) ? nil : $0 }
                    return
                }
                let page = try await source.page(path)
                guard !Task.isCancelled, state.revision == token, epoch == source.generation, key == requestKey else { return }
                let ids = Set(state.videos.map(\.path))
                let fresh = page.videos.filter { !ids.contains($0.path) }
                guard !fresh.isEmpty else { throw JRError.message("来源下一页没有新条目；保留已载入列表，请重试或刷新。") }
                state.videos.append(contentsOf: fresh); state.visited.insert(path)
                matcher.enqueue(codes: fresh.map { AvfanMatchStore.missAVMatchCode($0.code) })
                state.next = page.next.flatMap { state.visited.contains($0) ? nil : $0 }
            } catch { if !Task.isCancelled && state.revision == token && epoch == source.generation && key == requestKey { state.error = error.localizedDescription } }
        }
    }
}
struct MissAVSettingsView: View {
    @ObservedObject private var source = MissAVSource.shared
    @State private var domain = ""
    @State private var message = ""
    var body: some View {
        Form {
            Section("MissAV 来源域名") {
                TextField(MissAVHTML.defaultDomain, text: $domain).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("保存并取消旧请求") {
                    do { try source.configure(domain); message = "已保存" }
                    catch { message = error.localizedDescription }
                }
                Button("恢复默认 missav.fans") { domain = MissAVHTML.defaultDomain }
                Text(message).font(.footnote)
            }
            Section {
                Text("仅影响新增 MissAV 入口。不改变 AVDB、115 Cookie / 目录或播放器。仅 HTTPS 根域名；跨域跳转拒绝，需要您核对后手动修改。")
                Text("HTTP 403 / Cloudflare 时显示可重试错误，不绕过验证码、不注入脚本、不导入验证 Cookie。浏览器能访问不代表原生 URLSession 能访问。")
                Text("使用隔离的内存站点会话，仅接受 HTTP Set-Cookie；切换域名即清空。不读取 AVDB、115 或浏览器 Cookie。默认 missav.fans 已验证列表，网络与地区仍可能影响访问；不会自动切换镜像。")
                Link("在浏览器核对当前来源", destination: source.base)
                Button("取消请求并重新加载") { source.reset() }
            }.font(.footnote)
        }.navigationTitle("MissAV 来源设置").onAppear { domain = source.base.absoluteString }
    }
}
