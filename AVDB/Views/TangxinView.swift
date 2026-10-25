import SwiftUI
import UIKit

@MainActor final class TangxinListModel: ObservableObject {
    @Published private(set) var videos: [TangxinVideo] = []
    @Published private(set) var next: URL?
    @Published private(set) var heading: String?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var loaded = false
    private var generation = UUID()
    private var task: Task<Void,Never>?
    private var visited = Set<URL>()
    let root: URL
    let client: TangxinClient
    init(root: URL, client: TangxinClient) { self.root = root; self.client = client }
    deinit { task?.cancel() }
    func start() async { if !loaded { await refresh() } }
    func refresh() async {
        task?.cancel(); generation = UUID(); loading = false
        visited = []; next = nil; loaded = false
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
                self.heading = page.heading; self.loaded = true; self.loading = false
            } catch {
                guard let self, token == self.generation else { return }
                self.loading = false
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
        let current = task
        await withTaskCancellationHandler { await current?.value } onCancel: { current?.cancel() }
    }
}

struct TangxinRootView: View {
    let client: TangxinClient
    init(client: TangxinClient = TangxinClient()) { self.client = client }
    var body: some View {
        NavigationStack {
            TangxinListView(root:TangxinPolicy.featured,title:"糖心",client:client)
                .navigationDestination(for:TangxinVideo.self) { TangxinDetailView(video:$0,client:client) }
                .navigationDestination(for:TangxinAuthor.self) { author in
                    TangxinListView(root:author.url,title:author.name,client:client,isAuthor:true)
                }
        }
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
                if model.loading { ProgressView().frame(maxWidth:.infinity,minHeight:44) }
                if let error = model.error {
                    VStack { Text(error).font(.footnote); Button("重试") { Task { await model.retry() } }.frame(minWidth:44,minHeight:44) }
                        .frame(maxWidth:.infinity).padding().accessibilityIdentifier("tangxin.retry")
                } else if model.next != nil {
                    Button("加载更多") { Task { await model.more() } }
                        .frame(maxWidth:.infinity,minHeight:44).disabled(model.loading)
                        .accessibilityIdentifier("tangxin.more")
                } else if !model.loading && model.videos.isEmpty {
                    ContentUnavailableView("暂无可显示内容",systemImage:"film",description:Text("当前页面无通过筛查的视频；可下拉刷新。"))
                }
            }.padding(.vertical)
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }.task { await model.start() }
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
                            catch { if !Task.isCancelled { error = error.localizedDescription } }
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
            catch { if !Task.isCancelled { error = error.localizedDescription } }
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
