import SwiftUI
import UIKit

@MainActor final class TangxinListModel: ObservableObject {
    @Published private(set) var videos: [TangxinVideo] = []
    @Published private(set) var next: URL?
    @Published private(set) var heading: String?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var pageState: TangxinPageState?
    @Published private(set) var report: TangxinPageReport?
    private var loaded = false
    private var generation = UUID()
    private var task: Task<Void,Never>?
    private var visited = Set<URL>()
    let root: URL
    let client: TangxinClient
    init(root: URL, client: TangxinClient) { self.root = root; self.client = client }
    deinit { task?.cancel() }
    func start() async { if !loaded { await refresh() } }
    func cancel() {
        let interrupted = loading
        task?.cancel(); task = nil; generation = UUID(); loading = false
        if interrupted { error = "加载已取消；返回本页会重新加载，也可点重试。" }
        // Successful pages survive navigation; incomplete requests can be re-entered.
        loaded = !visited.isEmpty
    }
    func refresh() async {
        task?.cancel(); generation = UUID(); loading = false
        visited = []; next = nil; loaded = false; pageState = nil; report = nil
        await load(root, replacing:true)
    }
    func more() async { if let next { await load(next,replacing:false) } }
    func retry() async { if loaded { await more() } else { await refresh() } }
    private func load(_ url: URL, replacing: Bool) async {
        guard !loading, !visited.contains(url) else { return }
        let token = generation; loading = true; error = nil
        task = Task { [weak self, client] in
            do {
                let page = try await client.list(url)
                try Task.checkCancellation()
                guard let self, token == self.generation else { return }
                var seen = Set(replacing ? [] : self.videos.map(\.id))
                let fresh = page.videos.filter { seen.insert($0.id).inserted }
                self.videos = replacing ? fresh : self.videos + fresh
                self.visited.insert(url)
                self.next = page.next.flatMap { self.visited.contains($0) ? nil : $0 }
                self.heading = page.heading; self.pageState = page.state; self.report = page.report
                self.loaded = true; self.loading = false
            } catch {
                guard let self, token == self.generation else { return }
                self.loading = false
                self.error = Task.isCancelled ? "加载已取消，请重试" : error.localizedDescription
            }
        }
        let current = task
        await withTaskCancellationHandler { await current?.value } onCancel: { current?.cancel() }
    }
}

struct TangxinRootView: View {
    @AppStorage("tangxin.systemProxyCompatibility") private var compatibility = false
    @State private var networkSettings = false
    let client: TangxinClient
    init(client: TangxinClient = TangxinClient()) { self.client = client }
    var body: some View {
        let selected = client.withDNSMode(compatibility ? .systemProxy : .strict)
        NavigationStack {
            TangxinListView(root:TangxinPolicy.featured,title:"糖心",client:selected)
                .toolbar {
                    ToolbarItem(placement:.topBarTrailing) {
                        Button { networkSettings = true } label: { Label("网络设置/诊断",systemImage:"network") }
                            .accessibilityIdentifier("tangxin.network.open")
                    }
                }
                .navigationDestination(for:TangxinVideo.self) { TangxinDetailView(video:$0,client:selected) }
                .navigationDestination(for:TangxinAuthor.self) { author in
                    TangxinListView(root:author.url,title:author.name,client:selected,isAuthor:true)
                }
        }.id(compatibility)
        .sheet(isPresented:$networkSettings) { TangxinNetworkSettings(client:client,compatibility:$compatibility) }
    }
}

/// Local to Tangxin. No system settings, fixed IPs, TLS or private-network exceptions.
struct TangxinNetworkSettings: View {
    let client: TangxinClient
    @Binding var compatibility: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var status = "尚未运行诊断；请在出错的同一网络下运行。"
    @State private var running = false
    @State private var request = UUID()
    var body: some View {
        NavigationStack {
            Form {
                Section("糖心网络策略") {
                    Toggle("系统代理/Fake-IP兼容",isOn:$compatibility)
                        .accessibilityIdentifier("tangxin.network.compatibility")
                    Text(compatibility ? "当前：系统代理兼容（用户选择）" : "当前：严格模式（默认）")
                    Text("仅在信任当前 VPN/系统代理时开启。只允许已核准来源的 198.18.0.0/15 合成地址；私网、ULA、fd27 等仍拒绝。不代表已确认当前网络使用 Fake-IP，也不保证能修复。仅影响糖心；不会修改系统 DNS、代理、TLS 或其他栏目。切换后重建糖心页面与请求。")
                        .font(.footnote)
                }
                Section("只读诊断") {
                    Text(status).font(.footnote).textSelection(.enabled)
                        .accessibilityIdentifier("tangxin.network.status")
                    if running { ProgressView("检查来源连接") }
                    Button("运行诊断/重试") { request = UUID() }
                        .disabled(running).accessibilityIdentifier("tangxin.network.run")
                    Link("在 Safari 核对来源",destination:TangxinPolicy.featured)
                        .accessibilityIdentifier("tangxin.network.source")
                    Text("仅请求公开列表，不渲染网页、不绕验证。诊断不显示完整 URL、查询、Cookie、密钥或地址。原生播放器会自行解析/连接分片，应用的预检不是 DNS 固定，不能承诺播放期每次解析与重定向均被拦截。")
                        .font(.footnote)
                }
            }.navigationTitle("网络设置/诊断")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
        }
        .task(id:request) {
            running = true
            status = "正在检查 tangxinvlog.app · 查询 · " + (compatibility ? "系统代理兼容" : "严格模式")
            do {
                let page = try await client.withDNSMode(compatibility ? .systemProxy : .strict).list(TangxinPolicy.featured)
                try Task.checkCancellation()
                status = "tangxinvlog.app · 查询：HTTP 200 · 状态 " + page.state.rawValue + " · 可显示 \(page.videos.count) 项（不等于播放验收）"
            } catch { status = Task.isCancelled ? "诊断已取消，请重试" : error.localizedDescription }
            running = false
        }
        .onChange(of:compatibility) { _, _ in request = UUID() }
    }
}
struct TangxinListView: View {
    @StateObject private var model: TangxinListModel
    let title: String
    let isAuthor: Bool
    init(root:URL,title:String,client:TangxinClient,isAuthor:Bool = false) {
        self.title = title; self.isAuthor = isAuthor
        _model = StateObject(wrappedValue:TangxinListModel(root:root,client:client))
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:16) {
                if isAuthor {
                    Label(model.heading ?? title,systemImage:"person.crop.circle")
                        .font(.title2.bold()).padding(.horizontal)
                        .accessibilityIdentifier("tangxin.author.heading")
                    Text("作者作品 · 仅显示当前已加载且通过内容筛查的视频")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }
                Link("在 Safari 核对来源",destination:model.root)
                    .font(.caption).padding(.horizontal).accessibilityIdentifier("tangxin.source")
                Text("来源：糖心Vlog · 限合法、自愿成人内容")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                LazyVGrid(columns:[GridItem(.adaptive(minimum:160),spacing:14)],spacing:18) {
                    ForEach(model.videos) { video in
                        VStack(alignment:.leading,spacing:6) {
                            NavigationLink(value:video) {
                                VStack(alignment:.leading,spacing:8) {
                                    TangxinImage(url:video.poster,client:model.client)
                                        .aspectRatio(16/9,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:12))
                                    Text(video.title).font(.subheadline.weight(.medium)).lineLimit(3)
                                        .frame(maxWidth:.infinity,alignment:.leading)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("tangxin.video.\(video.url.lastPathComponent)")
                            if let author = video.author {
                                NavigationLink(value:author) { Label(author.name,systemImage:"person.crop.circle").font(.caption).frame(minHeight:44) }
                                    .buttonStyle(.plain).accessibilityIdentifier("tangxin.author.\(video.url.lastPathComponent)")
                            }
                        }
                    }
                }.padding(.horizontal)
                if model.loading { ProgressView("正在加载来源").frame(maxWidth:.infinity,minHeight:44) }
                if !model.loading, model.error == nil, model.pageState == nil {
                    Text("尚未加载完成，请重试。")
                    Button("重试加载") { Task { await model.refresh() } }.frame(minHeight:44)
                        .accessibilityIdentifier("tangxin.idle.retry")
                }
                if !model.loading, model.error == nil, let state = model.pageState, state != .content {
                    VStack(alignment:.leading,spacing:8) {
                        switch state {
                        case .sourceEmpty:
                            Label("源暂无数据",systemImage:"tray")
                            Text("来源返回空列表，未发生内容筛除。")
                        case .filtered:
                            Label("当前页无可显示内容",systemImage:"hand.raised")
                            Text("当前页可解析的视频均未通过年龄或同意风险筛查。")
                        case .structureChanged:
                            Label("来源结构变化",systemImage:"exclamationmark.triangle")
                            Text("未能完整识别视频卡片，不能将其判定为筛查空页。")
                        case .content: EmptyView()
                        }
                        if model.next != nil { Text("可手动加载下一页；每次仅请求一页。") }
                        Button("重新加载首页") { Task { await model.refresh() } }
                            .frame(minHeight:44).accessibilityIdentifier("tangxin.empty.refresh")
                    }.font(.footnote).frame(maxWidth:.infinity,alignment:.leading).padding()
                        .accessibilityIdentifier("tangxin.state.\(state.rawValue)")
                }
                if let error = model.error {
                    VStack { Text(error).font(.footnote); Button("重试") { Task { await model.retry() } }.frame(minWidth:44,minHeight:44) }
                        .frame(maxWidth:.infinity).padding().accessibilityIdentifier("tangxin.retry")
                } else if model.next != nil {
                    Button("加载更多") { Task { await model.more() } }
                        .frame(maxWidth:.infinity,minHeight:44).disabled(model.loading)
                        .accessibilityIdentifier("tangxin.more")
                }
            }.padding(.vertical)
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }.task { await model.start() }
        .onDisappear { model.cancel() }
        .accessibilityIdentifier(isAuthor ? "tangxin.author.page" : "tangxin.list")
    }
}

struct TangxinImage: View {
    let url: URL?
    let client: TangxinClient
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image { Image(uiImage:image).resizable().scaledToFill() }
            else { Image(systemName:"film").foregroundStyle(.secondary) }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
            .task(id:url) {
                image = nil
                guard let url else { return }
                do { let data = try await client.image(url); try Task.checkCancellation(); image = UIImage(data:data) } catch { }
            }
    }
}

struct TangxinDetailView: View {
    let video: TangxinVideo
    let client: TangxinClient
    @State private var detail: TangxinDetail?
    @State private var error: String?
    @State private var loading = false
    @State private var playback: TangxinPlayback?
    @State private var request = UUID()
    @State private var playTask: Task<Void,Never>?
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                if let detail {
                    TangxinImage(url:detail.video.poster,client:client).aspectRatio(16/9,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:16))
                    Text(detail.video.title).font(.title2.bold())
                    if let author = detail.video.author {
                        NavigationLink(value:author) { Label(author.name,systemImage:"person.crop.circle").frame(minHeight:44) }
                            .accessibilityIdentifier("tangxin.detail.author")
                    }
                    if !detail.summary.isEmpty { Text(detail.summary).font(.body) }
                    Text(detail.tags.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
                    Button {
                        guard !loading else { return }; loading = true; error = nil
                        playTask = Task {
                            do { let plan = try await client.playback(detail); try Task.checkCancellation(); playback = plan }
                            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                            loading = false
                        }
                    } label: { Label("播放",systemImage:"play.fill").frame(maxWidth:.infinity,minHeight:44) }
                    .buttonStyle(.borderedProminent).disabled(loading).accessibilityIdentifier("tangxin.play")
                }
                if loading { ProgressView() }
                if let error { Text(error).font(.footnote); Button("重试") { request = UUID() }.frame(minWidth:44,minHeight:44) }
            }.padding()
        }
        .navigationTitle("视频详情").navigationBarTitleDisplayMode(.inline)
        .task(id:request) {
            loading = true; error = nil; detail = nil
            do { let value = try await client.detail(video.url); try Task.checkCancellation(); detail = value }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            loading = false
        }
        .onDisappear { playTask?.cancel() }
        .fullScreenCover(item:$playback) { plan in
            // The existing player owns subtitle/gesture/audio/LUT/orientation behavior.
            // No Movie/JavDB query, 115 operation, cookies or global header mutation.
            KSChromePlayer(url:plan.url,title:detail?.video.title ?? video.title,subtitle:"糖心 · HLS",headers:plan.headers,progressID:"tangxin:"+video.url.lastPathComponent,publicSubtitleQuery:"")
        }
    }
}
