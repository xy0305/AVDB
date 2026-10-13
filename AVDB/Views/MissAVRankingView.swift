import SwiftUI

// Additional source only: never changes JavDB ranking/search/playback state.
struct MissAVRankingView: View {
    @ObservedObject private var source = MissAVSource.shared
    @AppStorage("missav.adultConfirmed") private var adultConfirmed = false
    @StateObject private var metadata = MissAVMetadata()
    @EnvironmentObject private var appState: AppState
    @State private var actresses: [MissAVActress] = []
    @State private var actressTitle = "MissAV 女优排行"
    @State private var period = "weekly-hot"
    @State private var attempt = 0
    @State private var videos: [JRVideo] = []
    @State private var next: String?
    @State private var visited = Set<String>()
    @State private var error = ""
    @State private var loading = false
    @State private var paging = false
    @State private var pageTask: Task<Void, Never>?
    @State private var revision = UUID()
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
        .onDisappear { pageTask?.cancel(); revision = UUID(); metadata.suspend() }
        .onChange(of: appState.currentUser?.id) { _, _ in metadata.reset(); attempt += 1 }
        .onChange(of: appState.isLoggedIn) { _, _ in metadata.reset(); attempt += 1 }
    }
    private var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("MissAV · 原站顺序").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink { MissAVSettingsView() } label: { Image(systemName: "gearshape") }
                }.padding(.horizontal)
                CapsuleChipBar(tabs: MissAVHTML.periods + [("actresses", "女优排行")], selection: $period)
                    .accessibilityIdentifier("missav-periods")
                Text("MissAV 提供排序和身份；精确匹配后封面、标题、演员资料替换为 AVDB 数据，不改变排名。")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                if loading { ProgressView("载入 MissAV 排行…") }
                if !error.isEmpty {
                    Text(error).font(.callout).padding(.horizontal)
                    Button(videos.isEmpty ? "重试排行" : "重试下一页") {
                        if videos.isEmpty { attempt += 1 } else { loadNext() }
                    }.buttonStyle(.bordered)
                    Link("在浏览器核对来源（不导入 Cookie）", destination: source.base)
                }
                if period == "actresses" {
                    Text(actressTitle).font(.headline)
                    Text("当前站点月榜；未发现独立日榜 / 周榜或分页，不虚构参数。")
                        .font(.caption).foregroundStyle(.secondary)
                    MissAVActressGrid(actors: actresses, metadata: metadata)
                } else {
                    MissAVGrid(videos: videos, metadata: metadata)
                }
                if next != nil && !loading {
                    Button { loadNext() } label: {
                        if paging { AnyView(ProgressView()) } else { AnyView(Text("加载下一页")) }
                    }.disabled(paging).buttonStyle(.bordered)
                }
            }.padding(.vertical, 8)
        }
        .refreshable { attempt += 1 }
        .task(id: "\(source.generation):\(period):\(attempt)") { await reload() }
    }
    @MainActor private func reload() async {
        pageTask?.cancel(); let token = UUID(); revision = token
        metadata.reset()
        videos = []; actresses = []; next = nil; visited = []; error = ""; loading = true; paging = false
        let epoch = source.generation
        defer { if revision == token { loading = false } }
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--missav-navigation-fixture") {
                videos = [JRVideo(path: "/cn/test-101", code: "TEST-101", title: "Synthetic source", image: nil, subtitle: "")]
                actresses = [MissAVActress(path: "/cn/actresses/Synthetic", name: "Synthetic actor", aliases: ["Synthetic"], rank: 1)]
                actressTitle = "Synthetic monthly ranking (not live)"
                return
            }
            #endif
            if period == "actresses" {
                let page = try await source.actressPage()
                guard !Task.isCancelled, revision == token, epoch == source.generation else { return }
                actresses = page.actors; actressTitle = page.title; next = page.next
                visited.insert(MissAVHTML.actressRanking)
                return
            }
            let path = source.routes[period] ?? MissAVHTML.routes[period]!
            let page = try await source.page(path)
            guard !Task.isCancelled, revision == token, epoch == source.generation else { return }
            videos = page.videos; next = page.next; visited.insert(path)
        } catch { if !Task.isCancelled && revision == token && epoch == source.generation { self.error = error.localizedDescription } }
    }
    @MainActor private func loadNext() {
        guard !loading, !paging, let path = next else { return }
        let token = revision, epoch = source.generation
        paging = true; error = ""
        pageTask = Task { @MainActor in
            defer { if revision == token { paging = false } }
            do {
                guard !visited.contains(path) else { throw JRError.message("来源返回重复分页，请刷新。") }
                if period == "actresses" {
                    let page = try await source.actressPage(path)
                    guard !Task.isCancelled, revision == token, epoch == source.generation else { return }
                    let ids = Set(actresses.map(\.path))
                    let fresh = page.actors.filter { !ids.contains($0.path) }
                    guard !fresh.isEmpty else { throw JRError.message("来源返回重复女优分页，请刷新。") }
                    actresses.append(contentsOf: fresh); visited.insert(path)
                    next = page.next.flatMap { visited.contains($0) ? nil : $0 }
                    return
                }
                let page = try await source.page(path)
                guard !Task.isCancelled, revision == token, epoch == source.generation else { return }
                let ids = Set(videos.map(\.path))
                let fresh = page.videos.filter { !ids.contains($0.path) }
                guard !fresh.isEmpty else { throw JRError.message("来源下一页没有新条目；保留已载入列表，请重试或刷新。") }
                videos.append(contentsOf: fresh); visited.insert(path)
                next = page.next.flatMap { visited.contains($0) ? nil : $0 }
            } catch { if !Task.isCancelled && revision == token && epoch == source.generation { self.error = error.localizedDescription } }
        }
    }
}
private struct MissAVGrid: View {
    let videos: [JRVideo]
    @ObservedObject var metadata: MissAVMetadata
    @State private var width: CGFloat = 390
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: AdaptiveLayout.columnCount(width: width, padding: AdaptiveLayout.gridPadding, spacing: 12)), spacing: 16) {
            ForEach(Array(videos.enumerated()), id: \.element.path) { index, video in
                let result = metadata.value(.movie(video))
                VStack(alignment: .leading, spacing: 4) {
                    NavigationLink {
                        if let movie = result.movie { MovieDetailView(movieID: movie.id) }
                        else { MissAVMovieRoute(video: video) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            // Source covers are intentionally NOT used as AVDB covers.
                            MoviePosterCard(movie: result.movie ?? Movie(id: "missav:" + video.path, number: video.code, title: video.title))
                            Text("MissAV 顺序 \(index + 1)").font(.caption2).foregroundStyle(.secondary)
                            Text(result.message).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                            if result.loading { ProgressView("匹配 AVDB 封面…").font(.caption2) }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("missav-movie-\(index + 1)")
                    if !result.loading && result.movie == nil {
                        Button("重试 AVDB 匹配") { metadata.enqueue(.movie(video), retry: true) }.font(.caption)
                    }
                }.frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading).clipped()
                    .onAppear { metadata.enqueue(.movie(video)) }.id(video.path)
            }
        }.padding(.horizontal, AdaptiveLayout.gridPadding)
        .background { GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, value in width = value } } }
    }
}
struct MissAVMovieRoute: View {
    let video: JRVideo
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
                }.navigationTitle("MissAV 番号核验")
            }
        }
        .task(id: "\(source.generation):\(video.path):\(attempt)") {
            let epoch = source.generation, request = attempt
            loading = true; movie = nil; message = ""; code = video.code
            defer { if request == attempt && epoch == source.generation { loading = false } }
            do {
                if code.isEmpty {
                    let detail = try await source.detail(video)
                    guard !Task.isCancelled, epoch == source.generation, request == attempt else { return }
                    code = detail.video.code
                }
                guard JRPolicy.exactCode(code) != nil else { message = "来源未提供可信完整番号，无法自动匹配。"; return }
                let match = try await JavDBSDK.shared.exactMovie(code: code, refresh: attempt > 0, verifyAllPages: true)
                guard !Task.isCancelled, epoch == source.generation, request == attempt else { return }
                movie = match
                if match == nil { message = "AVDB 数据源搜索前 3 页未找到唯一精确番号结果；不代表影片不存在。" }
            } catch {
                if !Task.isCancelled, epoch == source.generation, request == attempt { message = error.localizedDescription }
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

private struct MissAVActressGrid: View {
    let actors: [MissAVActress]
    @ObservedObject var metadata: MissAVMetadata
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 20) {
            ForEach(Array(actors.enumerated()), id: \.element.path) { index, source in
                let result = metadata.value(.actor(source))
                VStack(alignment: .leading, spacing: 8) {
                    if let actor = result.actor {
                        NavigationLink { ActorDetailView(actorID: actor.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                JavDBImage(url: actor.avatarURL ?? actor.coverURL)
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
                    Text("MissAV 顺序 \(index + 1)").font(.caption).foregroundStyle(.secondary)
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
                            Button("重试匹配") { metadata.enqueue(.actor(source), retry: true) }
                                .font(.caption).frame(minHeight: 44)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
                    .onAppear { metadata.enqueue(.actor(source)) }
                    .accessibilityIdentifier("missav-actress-\(index + 1)")
            }
        }.padding(.horizontal)
    }
}
