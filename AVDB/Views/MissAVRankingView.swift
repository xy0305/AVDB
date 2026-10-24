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
    @StateObject private var metadata = MissAVMetadata(resolver: Self.fixtureResolver)
    private static var fixtureResolver: ((MissAVMetadata.Request) async throws -> MissAVMetadata.Result)? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--missav-scroll-fixture") {
            return { request in
                if case .movie(let video) = request {
                    return MissAVMetadata.Result(movie: Movie(id: video.path, number: video.code, title: video.title, coverURL: "fixture://poster/1"), loading: false)
                }
                return MissAVMetadata.Result(loading: false)
            }
        }
        #endif
        return nil
    }
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
        .onDisappear { state.pageTask?.cancel(); state.revision = UUID(); state.paging = false; metadata.suspend() }
        .onChange(of: appState.currentUser?.id) { _, _ in metadata.reset(); state.attempt += 1 }
        .onChange(of: appState.isLoggedIn) { _, _ in metadata.reset(); state.attempt += 1 }
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
                Text("MissAV 提供排序和身份；精确匹配后封面、标题、演员资料替换为 AVDB 数据，不改变排名。")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
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
                    MissAVActressGrid(actors: state.actresses, metadata: metadata)
                } else {
                    MissAVGrid(videos: state.videos, metadata: metadata, scrollTargets: true)
                }
                if state.next != nil && !state.loading {
                    Button { loadNext() } label: {
                        if state.paging { AnyView(ProgressView()) } else { AnyView(Text("加载下一页")) }
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
        metadata.reset()
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
                state.visited.insert(MissAVHTML.actressRanking); state.loadedKey = key
                return
            }
            let path = source.routes[state.period] ?? MissAVHTML.routes[state.period]!
            let page = try await source.page(path)
            guard !Task.isCancelled, state.revision == token, epoch == source.generation, key == requestKey else { return }
            state.videos = page.videos; state.next = page.next; state.visited.insert(path); state.loadedKey = key
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
                    state.next = page.next.flatMap { state.visited.contains($0) ? nil : $0 }
                    return
                }
                let page = try await source.page(path)
                guard !Task.isCancelled, state.revision == token, epoch == source.generation, key == requestKey else { return }
                let ids = Set(state.videos.map(\.path))
                let fresh = page.videos.filter { !ids.contains($0.path) }
                guard !fresh.isEmpty else { throw JRError.message("来源下一页没有新条目；保留已载入列表，请重试或刷新。") }
                state.videos.append(contentsOf: fresh); state.visited.insert(path)
                state.next = page.next.flatMap { state.visited.contains($0) ? nil : $0 }
            } catch { if !Task.isCancelled && state.revision == token && epoch == source.generation && key == requestKey { state.error = error.localizedDescription } }
        }
    }
}
struct MissAVGrid: View {
    let videos: [JRVideo]
    @ObservedObject var metadata: MissAVMetadata
    var sourceName = "MissAV"
    var ranks: [String: Int] = [:]
    var identityPrefix = "missav"
    var scrollTargets = false
    @State private var width: CGFloat = 390
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: AdaptiveLayout.columnCount(width: width, padding: AdaptiveLayout.gridPadding, spacing: 12)), spacing: 16) {
            ForEach(Array(videos.enumerated()), id: \.element.path) { index, video in
                let result = metadata.value(.movie(video))
                VStack(alignment: .leading, spacing: 4) {
                    NavigationLink {
                        #if DEBUG
                        if sourceName == "MissAV" && ProcessInfo.processInfo.arguments.contains("--missav-scroll-fixture") {
                            Text("Neutral detail \(index + 1)").accessibilityIdentifier("missav-detail-\(index + 1)")
                        } else if sourceName == "JAVLibrary" && ProcessInfo.processInfo.arguments.contains("--javlibrary-navigation-fixture") {
                            Text("Synthetic detail \(ranks[video.path] ?? (index + 1))")
                                .accessibilityIdentifier("javlibrary-detail-\(ranks[video.path] ?? (index + 1))")
                        } else {
                            if let movie = result.movie { MovieDetailView(movieID: movie.id) }
                            else { MissAVMovieRoute(video: video, sourceName: sourceName) }
                        }
                        #else
                        if let movie = result.movie { MovieDetailView(movieID: movie.id) }
                        else { MissAVMovieRoute(video: video, sourceName: sourceName) }
                        #endif
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            // Source covers are intentionally NOT used as AVDB covers.
                            MoviePosterCard(movie: result.movie ?? Movie(id: identityPrefix + ":" + video.path, number: video.code, title: video.title))
                            Text("\(sourceName) 顺序 \(ranks[video.path] ?? (index + 1))").font(.caption2).foregroundStyle(.secondary)
                            Text(result.message).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                            if result.loading { ProgressView("匹配 AVDB 封面…").font(.caption2) }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("\(identityPrefix)-movie-\(ranks[video.path] ?? (index + 1))")
                    if !result.loading && result.movie == nil {
                        Button("重试 AVDB 匹配") { metadata.enqueue(.movie(video), retry: true) }.font(.caption)
                    }
                }.frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading).clipped()
                    .onAppear { metadata.enqueue(.movie(video)) }.id(video.path)
            }
        }.scrollTargetLayout(isEnabled: scrollTargets).padding(.horizontal, AdaptiveLayout.gridPadding)
        .background { GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, value in width = value } } }
    }
}
struct MissAVMovieRoute: View {
    let video: JRVideo
    var sourceName = "MissAV"
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var source = MissAVSource.shared
    @State private var code = ""
    @State private var movie: Movie?
    @State private var loading = true
    @State private var message = ""
    @State private var attempt = 0
    var body: some View {
        Group {
            if let movie { MovieDetailView(movieID: movie.id) }
            else {
                ScrollView {
                    VStack(spacing: 16) {
                        Text(video.title).font(.headline)
                        Text(code.isEmpty ? "来源尚无可核验完整番号" : code).textSelection(.enabled)
                        if loading { ProgressView("用番号搜索 AVDB 数据源并精确核验…") }
                        else {
                            Text(message).font(.callout)
                            Text("未取得唯一精确匹配，115 推送不可用；不会把网页或播放流当磁链。")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("重试核验") { attempt += 1 }
                            if !code.isEmpty {
                                NavigationLink("查看 AVDB 该番号搜索结果（手动核对）") { SearchMovieResultView(keyword: code) }
                            }
                        }
                    }.padding()
                }.navigationTitle("\(sourceName) 番号核验")
            }
        }
        .onChange(of: appState.currentUser?.id) { _, _ in movie = nil; attempt += 1 }
        .onChange(of: appState.isLoggedIn) { _, _ in movie = nil; attempt += 1 }
        .task(id: "\(source.generation):\(video.path):\(attempt)") {
            let owner = APIClient.shared.token
            let epoch = source.generation, request = attempt
            loading = true; movie = nil; message = ""; code = video.code
            defer { if request == attempt && epoch == source.generation { loading = false } }
            do {
                if code.isEmpty && sourceName == "MissAV" {
                    let detail = try await source.detail(video)
                    guard !Task.isCancelled, epoch == source.generation, request == attempt, owner == APIClient.shared.token else { return }
                    code = detail.video.code
                }
                guard JRPolicy.exactCode(code) != nil else { message = "来源未提供可信完整番号，无法自动匹配。"; return }
                let match = try await JavDBSDK.shared.exactMovie(code: code, refresh: attempt > 0, verifyAllPages: true)
                guard !Task.isCancelled, epoch == source.generation, request == attempt, owner == APIClient.shared.token else { return }
                movie = match
                if match == nil { message = "AVDB 数据源搜索前 3 页未找到唯一精确番号结果；不代表影片不存在。" }
            } catch {
                if !Task.isCancelled, epoch == source.generation, request == attempt, owner == APIClient.shared.token { message = error.localizedDescription }
            }
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

struct MissAVActressGrid: View {
    let actors: [MissAVActress]
    @ObservedObject var metadata: MissAVMetadata
    var sourceName = "MissAV"
    var identityPrefix = "missav"
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 20) {
            ForEach(Array(actors.enumerated()), id: \.element.path) { index, source in
                let result = metadata.value(.actor(source))
                VStack(alignment: .leading, spacing: 8) {
                    if let actor = result.actor {
                        NavigationLink { ActorDetailView(actorID: actor.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                JavDBImage(url: actor.avatarURL ?? actor.coverURL ?? result.avatarURL)
                                    .frame(height: 150).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
                                Text(actor.displayName).font(.headline)
                            }
                        }.buttonStyle(.plain)
                    } else {
                        Image(systemName: "person.crop.square")
                            .font(.system(size: 44)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).frame(height: 150)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        Text(source.name).font(.headline)
                    }
                    Text("\(sourceName) 顺序 \(source.rank ?? (index + 1))").font(.caption).foregroundStyle(.secondary)
                    if result.loading { ProgressView("匹配 AVDB…") }
                    else {
                        Text(result.message).font(.caption).foregroundStyle(.secondary)
                        if result.actor == nil {
                            if !result.candidates.isEmpty {
                                NavigationLink("核对 AVDB 候选") {
                                    List(result.candidates) { actor in
                                        NavigationLink { ActorDetailView(actorID: actor.id) } label: {
                                            VStack(alignment: .leading) {
                                                Text(actor.displayName)
                                                Text(actor.name ?? "").font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }.navigationTitle("请核对女优身份")
                                }
                            }
                            NavigationLink("搜索 AVDB 演员（手动核对）") { SearchActorResultView(keyword: source.name) }
                                .font(.caption).frame(minHeight: 44)
                            Button("重试匹配") { metadata.enqueue(.actor(source), retry: true) }
                                .font(.caption).frame(minHeight: 44)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
                    .onAppear { metadata.enqueue(.actor(source)) }
                    .accessibilityIdentifier("\(identityPrefix)-actress-\(source.rank ?? (index + 1))")
            }
        }.padding(.horizontal)
    }
}
