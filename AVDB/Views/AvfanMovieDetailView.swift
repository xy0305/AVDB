import SwiftUI

/// Build 353: the avfan detail page the five external boards open.
/// Metadata, casts and this site's magnets (with sizes) come from
/// the avfan detail page itself. Magnets can be pushed to the user's
/// own 115 through AVDB's existing Pan115Client, and played through
/// the same Pan115PlayerView the normal detail uses. Nothing here
/// touches JavDB.
/// Build 354: the hero and works posters run the standard poster
/// chain by number (HD portrait over the stored JavDB feed cover
/// over the avfan original) instead of pinning the tapped card's
/// raw cover.
struct AvfanMovieDetailView: View {
    let card: AvfanMovieCard

    @State private var detail: AvfanMovieDetail?
    @State private var failed = false
    @State private var failureText = "AVFan 详情加载失败"
    @State private var toast: String?
    @State private var pushingURL: String?
    @State private var playingMagnet: AvfanMagnetItem?
    @State private var showLogin = false
    @ObservedObject private var session = AvfanSession.shared
    @ObservedObject private var matcher = AvfanMatchStore.shared

    private var heroCover: String? { card.coverURL ?? detail?.coverURL }
    /// The poster-chain movie for the hero: identity stays the
    /// tapped card's, the number drives the HD resolution.
    private var heroMovie: Movie {
        matcher.posterMovie(
            id: card.pathID,
            code: detail?.displayCode ?? card.displayCode,
            title: card.title,
            fallbackCover: heroCover
        )
    }
    /// Identity the 115 player and its playback cache use for this
    /// page — namespaced so it never collides with a JavDB movie id.
    private var playerMovie: Movie {
        Movie(
            id: "avfan-" + card.pathID,
            type: "0",
            number: detail?.displayCode ?? card.displayCode,
            title: heroTitle,
            coverURL: heroCover
        )
    }
    private var heroTitle: String {
        if let detail, !detail.title.isEmpty { return detail.title }
        return card.titleWithoutCodePrefix
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                if let detail {
                    metaSection(detail)
                    if !detail.casts.isEmpty { castSection(detail) }
                    magnetSection(detail)
                    if !detail.alsoStarred.isEmpty {
                        worksSection(title: "还出演过", cards: detail.alsoStarred)
                    }
                    if !detail.relatedWorks.isEmpty {
                        worksSection(title: "相关作品", cards: detail.relatedWorks)
                    }
                } else if failed {
                    VStack(spacing: 10) {
                        Text(failureText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("重试") { Task { await load(bypassCache: true) } }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ProgressView("正在加载 AVFan 详情…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
                if !session.isSignedIn {
                    loginHint
                }
            }
            .padding(16)
        }
        .navigationTitle(card.displayCode)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("AVFan", isPresented: Binding(get: { toast != nil }, set: { if !$0 { toast = nil } })) {
            Button("好", role: .cancel) { toast = nil }
        } message: {
            Text(toast ?? "")
        }
        .sheet(isPresented: $showLogin) {
            AvfanLoginView()
        }
        .fullScreenCover(item: $playingMagnet) { magnet in
            Pan115PlayerView(movie: playerMovie, magnetURL: magnet.url)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Build 354: portrait HD hero like the normal detail —
            // the poster chain resolves by number; the tapped card's
            // raw avfan cover is only the last fallback.
            ClippedAspectFill(aspectRatio: 0.7, cornerRadius: 12) {
                MoviePosterImage(movie: heroMovie, maxPixelSize: 1200, upgradesVisibleHQ: true)
            }
            Text(heroTitle)
                .font(.headline)
                .textSelection(.enabled)
            Text(card.displayCode)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func metaSection(_ detail: AvfanMovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let rating = detail.rating {
                metaRow("评分", ratingCountText(rating: rating, count: detail.ratingCount))
            }
            if let date = detail.releaseDate { metaRow("发行日期", date) }
            if let duration = detail.duration { metaRow("片长", duration) }
            linkRow("制作商", detail.makers)
            linkRow("发行商", detail.publishers)
            linkRow("导演", detail.directors)
            linkRow("系列", detail.series)
            if !detail.tags.isEmpty {
                metaRow("标签", detail.tags.map(\.name).joined(separator: "、"))
            }
            if let summary = detail.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func ratingCountText(rating: Double, count: Int?) -> String {
        if let count { return String(format: "%.1f（%d 人）", rating, count) }
        return String(format: "%.1f", rating)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private func linkRow(_ label: String, _ links: [AvfanNamedLink]) -> some View {
        if !links.isEmpty {
            metaRow(label, links.map(\.name).joined(separator: "、"))
        }
    }

    private func castSection(_ detail: AvfanMovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("演员")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(detail.casts) { link in
                        NavigationLink {
                            AvfanActorView(name: link.name, href: link.href)
                        } label: {
                            Text(link.name)
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func magnetSection(_ detail: AvfanMovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("磁力链接（AVFan）")
                .font(.headline)
            if detail.magnets.isEmpty {
                // Explicit empty states: signed-in means the page
                // truly lists none; signed-out points at the login,
                // since avfan may only show magnets to members.
                if session.isSignedIn {
                    Text("本站暂无磁链")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("这个页面没有解析到磁链；avfan 的磁链可能需要登录后才显示。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("登录 avfan 后查看") { showLogin = true }
                            .font(.subheadline)
                    }
                }
            } else {
                ForEach(detail.magnets) { magnet in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(magnet.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        if !magnet.displayMeta.isEmpty {
                            Text(magnet.displayMeta)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !magnet.tags.isEmpty {
                            Text(magnet.tags.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            Button("复制") {
                                UIPasteboard.general.string = magnet.url
                                toast = "磁力链接已复制"
                            }
                            .font(.subheadline)
                            Button {
                                Task { await pushTo115(magnet) }
                            } label: {
                                if pushingURL == magnet.url {
                                    ProgressView()
                                } else {
                                    Text("推送到 115")
                                }
                            }
                            .font(.subheadline)
                            .disabled(pushingURL != nil)
                            // Build 354: play, like the normal detail —
                            // the player searches 115 by number first,
                            // pushes this magnet if the file is not
                            // there yet, then plays it.
                            Button {
                                let settings = Pan115Settings.shared
                                if settings.isConfigured {
                                    playingMagnet = magnet
                                } else {
                                    toast = settings.missingHint
                                }
                            } label: {
                                Label("播放", systemImage: "play.circle")
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func worksSection(title: String, cards: [AvfanMovieCard]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(cards) { item in
                    NavigationLink {
                        AvfanMovieDetailView(card: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            ClippedAspectFill(aspectRatio: 2.0 / 3.0, cornerRadius: 8) {
                                MoviePosterImage(
                                    movie: matcher.posterMovie(
                                        id: item.pathID,
                                        code: item.displayCode,
                                        title: item.title,
                                        fallbackCover: item.coverURL
                                    ),
                                    upgradesVisibleHQ: true
                                )
                            }
                            Text(item.displayCode)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var loginHint: some View {
        Button {
            showLogin = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.plus")
                Text("登录 avfan 后，磁链等内容更完整")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: Loading

    private func load(bypassCache: Bool = false) async {
        if detail != nil && !bypassCache { return }
        failed = false
        matcher.ensureFeedCovers()
        do {
            let url = await AvfanClient.shared.movieURL(pathID: card.pathID)
            var html = try await AvfanClient.shared.html(for: url, expectCatalog: true, bypassCache: bypassCache)
            var parsed = await AvfanHTMLParser.detached {
                AvfanHTMLParser.movieDetail(from: html, url: url)
            }
            // Identity guard: the fetched page must declare itself as
            // the tapped card (canonical id). One cache-bypassing
            // refetch, then stop instead of showing the wrong movie.
            let canonical = await AvfanHTMLParser.detached {
                AvfanHTMLParser.canonicalPathID(in: html)
            }
            if let canonical, canonical != card.pathID, !bypassCache {
                html = try await AvfanClient.shared.html(for: url, expectCatalog: true, bypassCache: true)
                let retryCanonical = await AvfanHTMLParser.detached {
                    AvfanHTMLParser.canonicalPathID(in: html)
                }
                if let retryCanonical, retryCanonical != card.pathID {
                    failed = true
                    return
                }
                parsed = await AvfanHTMLParser.detached {
                    AvfanHTMLParser.movieDetail(from: html, url: url)
                }
            }
            detail = parsed
        } catch {
            if let avfanError = error as? AvfanError, case .rateLimited = avfanError {
                failureText = "avfan 限流中，请约十分钟后再试"
            } else {
                failureText = "AVFan 详情加载失败"
            }
            failed = true
        }
    }

    private func pushTo115(_ magnet: AvfanMagnetItem) async {
        guard DownloadLinkDetector.isOfflineResource(magnet.url) else {
            toast = "仅支持有效 magnet / ed2k 资源，网页或播放流不可推送"
            return
        }
        let settings = Pan115Settings.shared
        guard settings.isConfigured else {
            toast = settings.missingHint
            return
        }
        pushingURL = magnet.url
        defer { pushingURL = nil }
        do {
            let auth = settings.cookie
            let result = try await Pan115Client.shared.addOfflineTask(
                url: magnet.url,
                cookie: auth,
                folderCID: settings.folderCID
            )
            // Same bookkeeping as the normal detail's magnet rows:
            // the player finds this magnet again by the movie id.
            Pan115PlaybackCache.save(movieID: playerMovie.id, magnet: magnet.url)
            toast = result.message
        } catch {
            toast = error.localizedDescription
        }
    }
}

/// Build 353: simple avfan actor page — avatar, name, works grid.
struct AvfanActorView: View {
    let name: String
    let href: String

    @State private var profile: AvfanCastProfile?
    @State private var failed = false
    @State private var failureText = "演员页加载失败"
    @ObservedObject private var matcher = AvfanMatchStore.shared

    private var displayName: String {
        if let profile, !profile.name.isEmpty { return profile.name }
        return name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.secondary.opacity(0.12))
                        if let avatar = profile?.avatarURL {
                            JavDBImage(url: avatar, contentMode: .fill)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.title3.weight(.semibold))
                        if let count = profile?.worksCount {
                            Text("\(count) 部作品")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let profile {
                    if profile.works.isEmpty {
                        Text("暂无可显示的作品")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(profile.works) { item in
                                NavigationLink {
                                    AvfanMovieDetailView(card: item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ClippedAspectFill(aspectRatio: 2.0 / 3.0, cornerRadius: 8) {
                                            MoviePosterImage(
                                                movie: matcher.posterMovie(
                                                    id: item.pathID,
                                                    code: item.displayCode,
                                                    title: item.title,
                                                    fallbackCover: item.coverURL
                                                ),
                                                upgradesVisibleHQ: true
                                            )
                                        }
                                        Text(item.displayCode)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else if failed {
                    VStack(spacing: 10) {
                        Text(failureText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("重试") { Task { await load(bypassCache: true) } }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ProgressView("正在加载演员页…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .padding(16)
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load(bypassCache: Bool = false) async {
        if profile != nil && !bypassCache { return }
        failed = false
        matcher.ensureFeedCovers()
        do {
            let url = await AvfanClient.shared.pageURL(href)
            let html = try await AvfanClient.shared.html(for: url, bypassCache: bypassCache)
            profile = await AvfanHTMLParser.detached {
                AvfanHTMLParser.castProfile(in: html)
            }
        } catch {
            if let avfanError = error as? AvfanError, case .rateLimited = avfanError {
                failureText = "avfan 限流中，请约十分钟后再试"
            } else {
                failureText = "演员页加载失败"
            }
            failed = true
        }
    }
}

/// Route for a board entry identified only by code: shows the avfan
/// detail once matched; while matching is pending it waits; on a miss
/// it says so plainly — it NEVER falls back to a JavDB search.
struct AvfanRouteView: View {
    let code: String
    var title: String = ""
    /// Optional extra content under the miss message (e.g. JAV
    /// Ranking's own source-page link).
    var missDestination: AnyView? = nil

    @ObservedObject private var matcher = AvfanMatchStore.shared
    @State private var attempted = false

    var body: some View {
        if let card = matcher.card(forCode: code) {
            AvfanMovieDetailView(card: card)
        } else {
            VStack(spacing: 12) {
                if matcher.rateLimitResumeAt != nil {
                    ProgressView("avfan 限流中，约十分钟后自动恢复…")
                    Text(code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if matcher.isMiss(code: code) || attempted {
                    Image(systemName: "film.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("AVFan 暂无此作")
                        .font(.headline)
                    Text(code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let missDestination {
                        missDestination
                    }
                } else {
                    ProgressView("正在匹配 AVFan…")
                    Text(code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .navigationTitle(code)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if matcher.match(forCode: code) == nil && !matcher.isMiss(code: code) {
                    _ = await matcher.resolveNow(code: code)
                }
                attempted = true
            }
        }
    }
}
