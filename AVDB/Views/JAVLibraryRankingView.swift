import SwiftUI

struct JAVLibraryRankingView: View {
    @ObservedObject private var settings = ExternalLibrarySettings.shared
    @EnvironmentObject private var appState: AppState
    @AppStorage("javlibrary.adultConfirmed") private var adultConfirmed = false
    // Separate view-owned cache; same tested queue as MissAV, no MissAV enrichment.
    @StateObject private var metadata = MissAVMetadata(sourceName: "JAVLibrary", generation: {
        Int(truncatingIfNeeded: ExternalLibrarySettings.shared.revision)
    }, enrichMissAV: false, resolver: Self.fixtureResolver)
    private static var fixtureResolver: ((MissAVMetadata.Request) async throws -> MissAVMetadata.Result)? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--javlibrary-navigation-fixture") {
            return { request in
                switch request {
                case .movie(let video): return MissAVMetadata.Result(movie: Movie(id: video.path, number: video.code, title: "Synthetic AVDB metadata", coverURL: "fixture://poster/1"), loading: false)
                case .actor: return MissAVMetadata.Result(message: "Synthetic unmatched actor (no network)", loading: false)
                }
            }
        }
        #endif
        return nil
    }
    @State private var kind: JAVLibraryKind = .mostwanted
    @State private var snapshot: JAVLibrarySnapshot?
    @State private var visibleCount = 25
    @State private var attempt = 0
    @State private var loading = false
    @State private var message = ""
    @State private var revision = UUID()
    @State private var loadedKey: String?
    private var requestKey: String { "\(settings.revision):\(kind.rawValue):\(attempt)" }
    var body: some View {
        Group {
            if adultConfirmed { content }
            else {
                ContentUnavailableView {
                    Label("仅限成年人", systemImage: "18.circle")
                } description: { Text("JAVLibrary 含成人资料。仅在已满 18 岁且所在地法律允许时进入。") }
                actions: { Button("我已满 18 岁，继续") { adultConfirmed = true } }
            }
        }
        .navigationTitle("JAVLibrary 排行")
        .onDisappear { revision = UUID(); metadata.suspend() }
        .onChange(of: appState.currentUser?.id) { _, _ in metadata.reset(); attempt += 1 }
        .onChange(of: appState.isLoggedIn) { _, _ in metadata.reset(); attempt += 1 }
    }
    private var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("JAVLibrary · 服务器原榜顺序").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink { ExternalLibrarySettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityIdentifier("javlibrary-settings")
                }.padding(.horizontal)
                CapsuleChipBar(tabs: JAVLibraryKind.allCases.map { ($0, $0.title) }, selection: $kind)
                    .accessibilityIdentifier("javlibrary-kinds")
                Text("替换为 AVDB 资料，不替换排名。每 8 小时服务器刷新；不是日 / 周 / 月榜，也不自动订阅或下载。")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                if loading { ProgressView("载入 JAVLibrary 快照…") }
                if !message.isEmpty {
                    Text(message).font(.callout).padding(.horizontal)
                    Button("重试排行") { attempt += 1 }.buttonStyle(.bordered)
                }
                if let snapshot {
                    Text("抓取时间：\(snapshot.fetchedAt) · 来源 \(snapshot.pages) 页 / \(snapshot.count) 条")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if snapshot.stale || snapshot.lastAttempt?.ok == 0 {
                        Text("快照已过期或最近抓取失败，当前保留上次成功榜单。下拉只重读快照，不触发服务器爬取。")
                            .font(.caption).foregroundStyle(.orange).padding(.horizontal)
                    }
                    if snapshot.items.isEmpty { Text("服务器当前快照为空") }
                    let entries = Array(snapshot.items.prefix(visibleCount))
                    if kind == .actors {
                        MissAVActressGrid(actors: entries.map(\.actor), metadata: metadata, sourceName: "JAVLibrary", identityPrefix: "javlibrary", onAppearLast: {
                            if visibleCount < snapshot.items.count { visibleCount += 25 }
                        })
                    } else {
                        MissAVGrid(videos: entries.map(\.video), metadata: metadata, sourceName: "JAVLibrary", ranks: Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.rank) }), identityPrefix: "javlibrary", onAppearLast: {
                            if visibleCount < snapshot.items.count { visibleCount += 25 }
                        })
                    }
                    if visibleCount < snapshot.items.count {
                        Button("加载下一页（本次快照 · 滑到底也会自动加载）") { visibleCount += 25 }
                            .buttonStyle(.bordered).accessibilityIdentifier("javlibrary-load-more")
                    }
                }
            }.padding(.vertical, 8)
        }
        .refreshable { attempt += 1 }
        .task(id: requestKey) {
            if loadedKey != requestKey || snapshot == nil { await reload() }
        }
    }
    @MainActor private func reload() async {
        let token = UUID(); revision = token
        let generation = settings.revision, selected = kind
        metadata.reset(); snapshot = nil; visibleCount = 25; message = ""; loading = true
        defer { if revision == token { loading = false } }
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--javlibrary-navigation-fixture") {
                let entity = selected == .actors ? "actor" : "movie"
                let rows: [[String: Any]] = (1...(selected == .actors ? 2 : 40)).map { rank in
                    ["rank": rank, "entity_type": entity, "number": "TEST-\(rank)", "name": "Synthetic actor \(rank)", "title": "Synthetic source \(rank)", "source_url": "https://fixture.invalid/\(rank)"]
                }
                let bytes = try JSONSerialization.data(withJSONObject: ["code": 0, "data": ["source": "javlibrary", "kind": selected.rawValue, "entity_type": entity, "fetched_at": "Synthetic fixture, not live", "source_url": "https://fixture.invalid", "pages": 5, "count": rows.count, "stale": false, "items": rows]])
                snapshot = try JAVLibrarySnapshot.decode(bytes, kind: selected)
                loadedKey = requestKey
                return
            }
            #endif
            let value = try await ExternalLibraryClient.shared.javlibrary(selected)
            guard !Task.isCancelled, revision == token, generation == settings.revision, kind == selected else { return }
            snapshot = value; loadedKey = requestKey
        } catch {
            if !Task.isCancelled, revision == token, generation == settings.revision { message = error.localizedDescription }
        }
    }
}
