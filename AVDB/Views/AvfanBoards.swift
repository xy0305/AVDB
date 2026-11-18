import SwiftUI

/// Build 353 shared grids for the external boards (MissAV / JAVLibrary
/// / 中指通）, mirroring the layout of the grids they replace: posters
/// and status come from the avfan match, unmatched entries show the
/// code placeholder, and every tap routes through AvfanRouteView —
/// matched entries open the avfan detail, unmatched ones say
/// 「AVFan 暂无此作」. No JavDB view, SDK call or verification appears
/// anywhere in these paths. Build 354: posters go through the
/// standard poster chain (AvfanMatchStore.posterMovie) — the visible
/// HQ upgrade resolves the DMM/MGS HD portrait by number (image CDN
/// only, not a JavDB request), over the stored JavDB feed cover,
/// over the avfan original cover.
struct AvfanBoardGrid: View {
    let videos: [JRVideo]
    var sourceName = "MissAV"
    var ranks: [String: Int] = [:]
    var identityPrefix = "missav"
    var scrollTargets = false
    /// Board-specific code normalization (MissAV strips its variant
    /// suffixes); identity for the other boards.
    var matchCode: (JRVideo) -> String = { $0.code }
    var onAppearLast: (() -> Void)? = nil

    @ObservedObject private var matcher = AvfanMatchStore.shared
    @State private var width: CGFloat = 390

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: AdaptiveLayout.columnCount(width: width, padding: AdaptiveLayout.gridPadding, spacing: 12)), spacing: 16) {
            ForEach(Array(videos.enumerated()), id: \.element.path) { index, video in
                let code = matchCode(video)
                let rank = ranks[video.path] ?? (index + 1)
                let match = matcher.match(forCode: code)
                let miss = matcher.isMiss(code: code)
                VStack(alignment: .leading, spacing: 4) {
                    NavigationLink {
                        destination(video: video, index: index, rank: rank, code: code)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            MoviePosterCard(
                                movie: matcher.posterMovie(
                                    id: identityPrefix + ":" + video.path,
                                    code: code,
                                    title: video.title,
                                    fallbackCover: fixtureCover
                                ),
                                upgradesVisibleHQ: true
                            )
                            Text("\(sourceName) 顺序 \(rank)").font(.caption2).foregroundStyle(.secondary)
                            Text(statusText(match: match, miss: miss)).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                            if match == nil && !miss { ProgressView("匹配 AVFan 封面…").font(.caption2) }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("\(identityPrefix)-movie-\(rank)")
                    if miss {
                        Button("重试 AVFan 匹配") { matcher.retry(code: code) }.font(.caption)
                    }
                }.frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading).clipped()
                    .onAppear {
                        matcher.prioritize(codes: [code])
                        if index == videos.count - 1 { onAppearLast?() }
                    }.id(video.path)
            }
        }.scrollTargetLayout(isEnabled: scrollTargets).padding(.horizontal, AdaptiveLayout.gridPadding)
        .background { GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, value in width = value } } }
    }

    private func statusText(match: AvfanMatchStore.MovieMatch?, miss: Bool) -> String {
        if match != nil { return "AVFan 资料 · \(sourceName) 顺序" }
        if miss { return "未匹配：AVFan 暂无此作" }
        return "等待 AVFan 匹配…"
    }

    private var fixtureCover: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if sourceName == "MissAV" && args.contains("--missav-scroll-fixture") { return "fixture://poster/1" }
        if sourceName == "JAVLibrary" && args.contains("--javlibrary-navigation-fixture") { return "fixture://poster/1" }
        #endif
        return nil
    }

    @ViewBuilder
    private func destination(video: JRVideo, index: Int, rank: Int, code: String) -> some View {
        #if DEBUG
        if sourceName == "MissAV" && ProcessInfo.processInfo.arguments.contains("--missav-scroll-fixture") {
            Text("Neutral detail \(index + 1)").accessibilityIdentifier("missav-detail-\(index + 1)")
        } else if sourceName == "JAVLibrary" && ProcessInfo.processInfo.arguments.contains("--javlibrary-navigation-fixture") {
            Text("Synthetic detail \(rank)").accessibilityIdentifier("javlibrary-detail-\(rank)")
        } else {
            AvfanRouteView(code: code, title: video.title)
        }
        #else
        AvfanRouteView(code: code, title: video.title)
        #endif
    }
}

/// Actress grid for the boards: avatar + name matched to avfan by
/// exact name; taps open the simple avfan actor page via the route.
struct AvfanBoardActorGrid: View {
    let actors: [MissAVActress]
    var sourceName = "MissAV"
    var identityPrefix = "missav"
    var onAppearLast: (() -> Void)? = nil

    @ObservedObject private var matcher = AvfanMatchStore.shared

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 20) {
            ForEach(Array(actors.enumerated()), id: \.element.path) { index, actor in
                let matched = matcher.actorMatch(forName: actor.name)
                let miss = matcher.isActorMiss(name: actor.name)
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink { AvfanActorRouteView(name: actor.name) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            if let avatar = matched?.avatarURL {
                                JavDBImage(url: avatar)
                                    .frame(height: 150).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
                            } else {
                                Image(systemName: "person.crop.square")
                                    .font(.system(size: 44)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity).frame(height: 150)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                            }
                            Text(actor.name).font(.headline).foregroundStyle(.primary)
                        }
                    }.buttonStyle(.plain)
                    Text("\(sourceName) 顺序 \(actor.rank ?? (index + 1))").font(.caption).foregroundStyle(.secondary)
                    if matched != nil {
                        Text("AVFan 演员资料 · \(sourceName) 顺序").font(.caption).foregroundStyle(.secondary)
                    } else if miss {
                        Text("未匹配：AVFan 暂无此演员").font(.caption).foregroundStyle(.secondary)
                        Button("重试匹配") { matcher.retryActor(name: actor.name) }
                            .font(.caption).frame(minHeight: 44)
                    } else {
                        ProgressView("匹配 AVFan…").font(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
                    .onAppear {
                        matcher.enqueueActor(name: actor.name)
                        if index == actors.count - 1 { onAppearLast?() }
                    }
                    .accessibilityIdentifier("\(identityPrefix)-actress-\(actor.rank ?? (index + 1))")
            }
        }.padding(.horizontal)
    }
}

/// Actor equivalent of AvfanRouteView: resolves the name match on
/// demand, then opens the avfan actor page; a miss says so plainly.
struct AvfanActorRouteView: View {
    let name: String

    @ObservedObject private var matcher = AvfanMatchStore.shared
    @State private var attempted = false

    var body: some View {
        if let match = matcher.actorMatch(forName: name) {
            AvfanActorView(name: name, href: match.href)
        } else {
            VStack(spacing: 12) {
                if matcher.isActorMiss(name: name) || attempted {
                    Image(systemName: "person.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("AVFan 暂无此演员")
                        .font(.headline)
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView("正在匹配 AVFan…")
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if matcher.actorMatch(forName: name) == nil && !matcher.isActorMiss(name: name) {
                    _ = await matcher.resolveActorNow(name: name)
                }
                attempted = true
            }
        }
    }
}
