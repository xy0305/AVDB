//
//  MovieDetailView.swift
//  AVDB
//
//  影片详情页：封面/剧照/信息/磁力/预览/播放/影评。
//

import SwiftUI
import AVKit

struct MovieDetailView: View {
    let movieID: String
    @StateObject private var vm: MovieDetailViewModel
    @State private var play115 = false
    @State private var showTrailer = false
    @State private var tenhowCoverURL: String?
    @State private var reviewPanelHeight: CGFloat = 76
    @StateObject private var reviewsVM = ReviewsListViewModel()
    @State private var showSearch = false
    @Environment(\.dismiss) private var dismiss

    init(movieID: String) {
        self.movieID = movieID
        _vm = StateObject(wrappedValue: MovieDetailViewModel(movieID: movieID))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let movie = vm.movie {
                    detailBackground(movie)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Color(.systemBackground).ignoresSafeArea()
                }

                ScrollView(.vertical) {
                    if let movie = vm.movie {
                        detailContent(movie, width: proxy.size.width)
                            .frame(width: proxy.size.width)
                            .padding(.bottom, 60)
                    } else if vm.isLoading {
                        ProgressView().tint(.white).padding(.top, 120)
                    } else if let err = vm.errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40)).foregroundColor(.orange)
                            Text(err).foregroundStyle(.white)
                            Button("重试") { Task { await vm.load() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 120)
                    }
                }
                .frame(width: proxy.size.width)
                .ignoresSafeArea(edges: .top)

                if let movie = vm.movie {
                    // ContentView 的悬浮 Tab Bar 在详情页外层，必须为它预留高度，
                    // 否则 76pt 的评论折叠栏会被约 94pt 的 Tab Bar 完整遮住。
                    DraggableReviewsPanel(
                        movieID: movie.id,
                        total: movie.reviewsCount ?? movie.commentsCount ?? 0,
                        panelHeight: $reviewPanelHeight,
                        vm: reviewsVM,
                        availableHeight: max(300, proxy.size.height - 94)
                    )
                    .frame(width: proxy.size.width)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: -94)
                    .zIndex(10)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSearch) { SearchView() }
        .task {
            await vm.load()
            if let movie = vm.movie {
                await reviewsVM.load(movieID: movie.id)
            }
        }
        .fullScreenCover(isPresented: $play115) {
            if let movie = vm.movie { Pan115PlayerView(movie: movie) }
        }
        .fullScreenCover(isPresented: $showTrailer) {
            if let url = vm.movie?.previewVideoURL.flatMap(URL.init) {
                TrailerPlayerView(url: url, onClose: { showTrailer = false })
            }
        }
    }

    private func detailBackground(_ movie: Movie) -> some View {
        ZStack {
            JavDBImage(
                url: movie.hdBackdropURL ?? movie.coverURL ?? movie.thumbURL,
                fallbackURL: tenhowCoverURL,
                contentMode: .fill
            )
            .scaleEffect(1.35)
            .blur(radius: 42)
            .opacity(0.58)
            Color(red: 0.43, green: 0.13, blue: 0.15).opacity(0.68)
            LinearGradient(
                colors: [.white.opacity(0.20), .clear, .black.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func detailContent(_ movie: Movie, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            heroHeader(movie, width: width)

            VStack(alignment: .leading, spacing: 20) {
                if let tags = movie.tags, !tags.isEmpty { tagsSection(tags) }
                if let actors = movie.actors, !actors.isEmpty { actorsSection(actors) }
                if let summary = movie.summary, !summary.isEmpty { summarySection(summary) }
                if let trailer = movie.previewVideoURL, let url = URL(string: trailer) { trailerSection(url) }
                if let images = movie.previewImages, !images.isEmpty { previewImagesSection(images) }
                if (movie.magnetsCount ?? 0) > 0 { magnetsSection(movie) }
                if !vm.actorMovies.isEmpty { actorMoviesSection(vm.actorMovies) }
                if !vm.relatedMovies.isEmpty { relatedSection(vm.relatedMovies) }
                relatedListsSection
            }
            .padding(.top, 26)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34))
        }
    }

    private func heroHeader(_ movie: Movie, width: CGFloat) -> some View {
        let contentWidth = max(0, width - 40)
        return VStack(alignment: .leading, spacing: 22) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 27, weight: .medium))
                        .frame(width: 46, height: 46)
                }
                Spacer()
                Button {
                    Task { _ = try? await JavDBSDK.shared.codeCollectActions(movie.id) }
                } label: {
                    Image(systemName: "bookmark.square")
                        .font(.system(size: 25, weight: .regular))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .padding(2).background(.white, in: Circle())
                                .foregroundStyle(Color(red: 0.45, green: 0.18, blue: 0.19))
                                .offset(x: 4, y: 4)
                        }
                        .frame(width: 46, height: 46)
                }
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .regular))
                        .frame(width: 46, height: 46)
                }
            }
            .foregroundStyle(.white)
            .padding(.top, 54)

            Text(movie.displayTitle)
                .font(.system(size: 28, weight: .bold))
                .lineSpacing(5)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .bottomTrailing) {
                JavDBImage(
                    url: movie.hdBackdropURL ?? movie.coverURL ?? movie.thumbURL,
                    fallbackURL: tenhowCoverURL,
                    secondFallbackURL: movie.hdCoverURL,
                    contentMode: .fill
                )
                .frame(width: contentWidth, height: contentWidth / 1.47)
                .clipped()

                Button { play115 = true } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                        .frame(width: 56, height: 56)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.28), lineWidth: 0.8)
                        }
                        .shadow(color: .white.opacity(0.12), radius: 10)
                        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 5)
            .task(id: movie.id) {
                let names = movie.actors?.compactMap(\.name) ?? movie.actorNames ?? []
                tenhowCoverURL = await TenhowCoverResolver.shared.coverURL(
                    number: movie.displayNumber,
                    releaseDate: movie.releaseDate,
                    actorNames: names
                )
            }

            movieInfoCard(movie)
        }
        .frame(width: contentWidth, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private func movieInfoCard(_ movie: Movie) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 20) {
                detailInfoLine("番号：", movie.displayNumber, underline: true)
                if let date = movie.releaseDate { detailInfoLine("发行日期：", date) }
                if let duration = movie.duration { detailInfoLine("长度：", "\(duration) 分钟") }
                if let director = movie.directorName, !director.isEmpty {
                    detailInfoLine("导演：", director, underline: true)
                }
                if let maker = movie.makerName, !maker.isEmpty {
                    detailInfoLine("制作商：", maker, underline: true)
                }
                let count = movie.reviewsCount ?? movie.commentsCount ?? 0
                detailInfoLine("评分：", count > 0 ? "共\(count)人评分" : movie.scoreText)
            }
            .padding(20)
            .padding(.trailing, movie.score == nil ? 0 : 62)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let score = movie.score, score > 0 {
                VStack(spacing: 1) {
                    Text("AvPlay").font(.caption2.weight(.bold))
                    Text(String(format: "%.1f", score)).font(.system(size: 28, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(width: 72, height: 86)
                .background(Color.orange.opacity(0.90))
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
                .padding(.trailing, 18)
            }
        }
        .foregroundStyle(.white)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailInfoLine(_ label: String, _ value: String, underline: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(label)
            Text(value).underline(underline)
        }
        .font(.system(size: 18, weight: .regular))
        .textSelection(.enabled)
    }

    private func heroAction(_ systemName: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.title3.weight(.medium))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func headerSection(_ movie: Movie) -> some View {
        HStack(alignment: .top, spacing: 12) {
            JavDBImage(url: movie.coverURL ?? movie.thumbURL, fallbackURL: movie.hdCoverURL)
                .frame(width: 120, height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(movie.displayNumber)
                    .font(.title3.bold())
                    .textSelection(.enabled)
                    .onTapGesture {
                        UIPasteboard.general.string = movie.displayNumber
                    }

                Text(movie.displayTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    if let score = movie.score, score > 0 {
                        Label(String(format: "%.2f", score), systemImage: "star.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    if let date = movie.releaseDate {
                        Label(date, systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    if let duration = movie.duration {
                        Label("\(duration)分钟", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if movie.hasCnsub == true {
                        Label("中字", systemImage: "character.bubble.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    if movie.hasPreviewVideo == true {
                        Label("预览", systemImage: "play.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }

                // 制作信息
                VStack(alignment: .leading, spacing: 3) {
                    if let maker = movie.makerName { infoRow("片商", maker) }
                    if let director = movie.directorName { infoRow("导演", director) }
                    if let publisher = movie.publisherName { infoRow("发行", publisher) }
                    if let series = movie.seriesName { infoRow("系列", series) }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label).foregroundColor(.gray)
            Text(value).lineLimit(2)
        }
    }

    private func tagsSection(_ tags: [Tag]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("标签").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(tags) { tag in
                    NavigationLink {
                        TagMoviesView(tag: tag, catalogType: vm.movie?.type ?? "0")
                    } label: {
                        Text(tag.name ?? "")
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }

    private func actorsSection(_ actors: [Actor]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("演员").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(actors) { actor in
                        NavigationLink {
                            ActorDetailView(actorID: actor.id)
                        } label: {
                            VStack(spacing: 4) {
                                JavDBImage(url: actor.avatarURL ?? actor.coverURL)
                                    .frame(width: 70, height: 70)
                                    .clipShape(Circle())
                                Text(actor.name ?? "")
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(width: 70)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("简介").font(.headline)
            Text(summary)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }

    private func previewImagesSection(_ images: [PreviewImage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("剧照").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(images) { img in
                        JavDBImage(url: img.largeURL ?? img.thumbURL)
                            .frame(width: 260, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func playSection(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("播放").font(.headline)
                Text("115 原画")
                    .font(.caption)
                    .foregroundColor(JAVDBPalette.accent)
            }

            Button {
                play115 = true
            } label: {
                HStack {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(JAVDBPalette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("播放 115 原画")
                            .foregroundColor(.primary)
                        Text(Pan115Settings.shared.isConfigured
                             ? "等待离线完成后自动播放"
                             : "请先在「我的」填写 115 Cookie")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    private func trailerSection(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("预告片").font(.headline)
            Button {
                showTrailer = true
            } label: {
                ZStack {
                    JavDBImage(url: vm.movie?.coverURL ?? vm.movie?.thumbURL, contentMode: .fill)
                        .frame(height: 180)
                        .clipped()
                        .overlay(Color.black.opacity(0.35))
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    private func magnetsSection(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("磁力链接 (\(movie.magnetsCount ?? 0))")
                .font(.headline)
            if vm.magnets.isEmpty && vm.loadingMagnets {
                ProgressView()
            } else {
                ForEach(vm.magnets, id: \.stableID) { magnet in
                    MagnetRow(magnet: magnet, movieID: movie.id, movieNumber: movie.displayNumber)
                }
            }
        }
        .padding(.horizontal)
        .task { await vm.loadMagnets() }
    }

    private func reviewsSection(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                ReviewsListView(movieID: movie.id, total: vm.reviews.count)
            } label: {
                HStack {
                    Text("影评 (\(vm.reviews.count))")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("全部")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            if vm.reviews.isEmpty {
                Text("暂无影评")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.reviews.prefix(3)) { review in
                    ReviewRow(review: review, movieID: movie.id)
                }
            }
        }
        .padding(.horizontal)
        .task { await vm.loadReviews() }
    }

    private func relatedSection(_ movies: [Movie]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("相似推荐").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(movies) { movie in
                        NavigationLink {
                            MovieDetailView(movieID: movie.id)
                        } label: {
                            MovieCoverCard(movie: movie)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func actorMoviesSection(_ movies: [Movie]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ta 还出演过").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(movies) { movie in
                        NavigationLink {
                            MovieDetailView(movieID: movie.id)
                        } label: {
                            MovieCoverCard(movie: movie)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var relatedListsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("相关片单")
                .font(.headline)
            if vm.relatedLists.isEmpty {
                if vm.loadingLists {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } else {
                ForEach(vm.relatedLists) { list in
                    NavigationLink {
                        ListDetailView(listID: list.id, title: list.displayName)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 8) {
                                    if let n = list.movieCount { Text("\(n) 部") }
                                    if let c = list.collectionsCount { Text("\(c) 收藏") }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if list.id == vm.relatedLists.last?.id {
                            Task { await vm.loadMoreRelatedLists() }
                        }
                    }
                }
                if vm.loadingLists { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .padding(.horizontal)
        .task { await vm.loadRelatedLists() }
    }
}

@MainActor
final class MovieDetailViewModel: ObservableObject {
    let movieID: String
    @Published var movie: Movie?
    @Published var relatedMovies: [Movie] = []
    @Published var actorMovies: [Movie] = []
    @Published var magnets: [Magnet] = []
    @Published var reviews: [Review] = []
    @Published var relatedLists: [MovieList] = []
    @Published var isLoading = false
    @Published var loadingMagnets = false
    @Published var loadingLists = false
    @Published var errorMessage: String?
    private var listsPage = 1
    private var listsHasMore = true

    private let sdk = JavDBSDK.shared

    init(movieID: String? = nil) {
        self.movieID = movieID ?? ""
    }

    func load() async {
        guard !movieID.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let full = try await sdk.movieDetailFull(movieID)
            movie = full.movie
            relatedMovies = full.movie?.relativeMovies
                ?? full.relativeMovies
                ?? []
            actorMovies = full.movie?.actorMovies
                ?? full.actorMovies
                ?? []
            WatchedStore.mark(movieID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMagnets() async {
        guard !movieID.isEmpty, magnets.isEmpty else { return }
        loadingMagnets = true
        defer { loadingMagnets = false }
        if let m = try? await sdk.movieMagnets(movieID) {
            magnets = m
        }
    }

    func loadReviews() async {
        guard !movieID.isEmpty, reviews.isEmpty else { return }
        if let r = try? await sdk.movieReviews(movieID) {
            reviews = r
        }
    }

    func loadRelatedLists() async {
        guard !movieID.isEmpty, relatedLists.isEmpty else { return }
        listsPage = 1
        listsHasMore = true
        await fetchRelatedLists()
    }

    func loadMoreRelatedLists() async {
        guard listsHasMore, !loadingLists else { return }
        listsPage += 1
        await fetchRelatedLists()
    }

    private func fetchRelatedLists() async {
        loadingLists = true
        defer { loadingLists = false }
        let next = (try? await sdk.relatedLists(movieID, page: listsPage, limit: 24)) ?? []
        if next.isEmpty {
            listsHasMore = false
            return
        }
        if listsPage == 1 {
            relatedLists = next
        } else {
            let ids = Set(relatedLists.map(\.id))
            relatedLists.append(contentsOf: next.filter { !ids.contains($0.id) })
        }
    }
}

/// 磁力行：点击推送到 115 离线；长按复制
struct MagnetRow: View {
    let magnet: Magnet
    var movieID: String = ""
    var movieNumber: String = ""
    @State private var pushing = false
    @State private var toast: String?

    private var magnetURL: String? { magnet.magnetURL }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(magnet.displayName)
                    .font(.caption)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let size = magnet.sizeText {
                        Text(size).font(.caption2).foregroundColor(.secondary)
                    }
                    if magnet.isHd == true {
                        Text("HD").font(.caption2).foregroundColor(.blue)
                    }
                    if magnet.hasCnsub == true {
                        Text("中字").font(.caption2).foregroundColor(.green)
                    }
                    if let toast {
                        Text(toast)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            Spacer()
            Button {
                copyMagnet()
                toast = "已复制"
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)

            Button {
                Task { await pushTo115() }
            } label: {
                if pushing {
                    ProgressView()
                } else {
                    Image(systemName: "icloud.and.arrow.up")
                        .foregroundColor(.blue)
                }
            }
            .buttonStyle(.plain)
            .disabled(pushing)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await pushTo115() }
        }
        .onLongPressGesture {
            copyMagnet()
            toast = "已复制"
        }
    }

    private func copyMagnet() {
        UIPasteboard.general.string = magnetURL
    }

    private func pushTo115() async {
        guard let url = magnetURL else {
            toast = "无磁力链接"
            return
        }
        let settings = Pan115Settings.shared
        guard settings.isConfigured else {
            toast = settings.missingHint
            return
        }
        pushing = true
        defer { pushing = false }
        do {
            let folderSnapshot = await Pan115Client.shared.folderSnapshot(
                cid: settings.folderCID, cookie: settings.cookie)
            let result = try await Pan115Client.shared.addOfflineTask(
                url: url,
                cookie: settings.cookie,
                folderCID: settings.folderCID
            )
            if !movieID.isEmpty {
                Pan115PlaybackCache.save(movieID: movieID, magnet: url)
            }
            toast = result.message
            // 推送成功后，等待离线完成并清理 <115MB 的小文件
            await autoCleanSmallFiles(existingFolderIDs: folderSnapshot)
        } catch {
            toast = error.localizedDescription
        }
    }

    /// 推送成功后，等待离线完成，进入离线产物文件夹删除 <115MB 的小文件。
    private func autoCleanSmallFiles(existingFolderIDs: Set<String>) async {
        let settings = Pan115Settings.shared
        let keyword = movieNumber.isEmpty ? magnet.displayName : movieNumber
        do {
            let deleted = try await Pan115Client.shared.waitAndCleanSmallFiles(
                keyword: keyword,
                cookie: settings.cookie,
                folderCID: settings.folderCID,
                existingFolderIDs: existingFolderIDs
            )
            if deleted > 0 {
                toast = "已清理 \(deleted) 个小于 115MB 的小文件"
            }
        } catch {
            toast = "自动清理失败：\(error.localizedDescription)"
        }
    }
}

/// 影评行：正文可识别磁力/ed2k 链接（复制/推送115），番号可点击复制。
struct ReviewRow: View {
    let review: Review
    var movieID: String = ""

    @State private var linkStates: [String: LinkState] = [:]
    @State private var toast: String?

    enum LinkState {
        case idle
        case pushing
    }

    /// 从正文提取的下载链接（磁力/ed2k）
    private var links: [DownloadLinkKind] {
        DownloadLinkDetector.downloadLinks(in: review.content ?? "")
    }
    /// 从正文提取的番号
    private var numbers: [String] {
        DownloadLinkDetector.numbers(in: review.content ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(review.userName ?? "匿名")
                    .font(.caption.bold())
                if let score = review.score {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("\(score)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                Spacer()
                if let date = review.createdAt {
                    Text(Self.shortDate(date)).font(.caption2).foregroundColor(.secondary)
                }
            }

            if let content = review.content {
                Text(content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(5)
                    .textSelection(.enabled)
            }

            // 识别到的下载链接
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                linkRow(link)
            }

            // 识别到的番号（点击复制）
            if !numbers.isEmpty {
                FlowTags(numbers: numbers) { number in
                    copyNumber(number)
                }
            }

            if let toast {
                Text(toast)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func linkRow(_ link: DownloadLinkKind) -> some View {
        let key = link.rawValue
        let state = linkStates[key] ?? .idle
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: link.isDownloadLink ? "link" : "number")
                    .font(.caption2)
                    .foregroundColor(.blue)
                Text(link.label)
                    .font(.caption2.bold())
                    .foregroundColor(.blue)
                Text(link.rawValue)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    copyText(link.rawValue)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.orange)

                Button {
                    if link.isDownloadLink {
                        Task { await push(to: link) }
                    }
                } label: {
                    if case .pushing = state {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("推送到115", systemImage: "icloud.and.arrow.up")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                .disabled(linkStates[key] != nil)
            }
        }
        .padding(8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func copyText(_ text: String) {
        UIPasteboard.general.string = text
        toast = "已复制"
    }

    private func copyNumber(_ number: String) {
        UIPasteboard.general.string = number
        toast = "已复制番号 \(number)"
    }

    private func push(to link: DownloadLinkKind) async {
        let key = link.rawValue
        let settings = Pan115Settings.shared
        guard settings.isConfigured else {
            toast = settings.missingHint
            return
        }
        linkStates[key] = .pushing
        defer { linkStates[key] = nil }
        do {
            let folderSnapshot = await Pan115Client.shared.folderSnapshot(
                cid: settings.folderCID, cookie: settings.cookie)
            let result = try await Pan115Client.shared.addOfflineTask(
                url: link.rawValue,
                cookie: settings.cookie,
                folderCID: settings.folderCID
            )
            if !movieID.isEmpty {
                Pan115PlaybackCache.save(movieID: movieID, magnet: link.rawValue)
            }
            toast = result.message
            // 推送成功后，等待离线完成并清理 <115MB 的小文件
            await autoCleanSmallFiles(link: link, existingFolderIDs: folderSnapshot)
        } catch {
            toast = error.localizedDescription
        }
    }

    /// 推送成功后，等待离线完成，进入离线产物文件夹删除 <115MB 的小文件。
    private func autoCleanSmallFiles(link: DownloadLinkKind, existingFolderIDs: Set<String>) async {
        let settings = Pan115Settings.shared
        do {
            let deleted = try await Pan115Client.shared.waitAndCleanSmallFiles(
                keyword: link.rawValue,
                cookie: settings.cookie,
                folderCID: settings.folderCID,
                existingFolderIDs: existingFolderIDs
            )
            if deleted > 0 {
                toast = "已清理 \(deleted) 个小于 115MB 的小文件"
            }
        } catch {
            toast = "自动清理失败：\(error.localizedDescription)"
        }
    }

    private static func shortDate(_ raw: String) -> String {
        if raw.count >= 10 { return String(raw.prefix(10)) }
        return raw
    }
}

/// 简单流式标签（自动换行）
struct FlowTags: View {
    let numbers: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(numbers, id: \.self) { number in
                Button {
                    onTap(number)
                } label: {
                    Text(number)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary)
            }
        }
    }
}

/// 详情页内部的连续拖动评论面板。折叠态只显示把手和标题，避免内容漏出。
struct DraggableReviewsPanel: View {
    let movieID: String
    let total: Int
    @Binding var panelHeight: CGFloat
    @ObservedObject var vm: ReviewsListViewModel
    let availableHeight: CGFloat
    @GestureState private var dragDelta: CGFloat = 0

    private let collapsedHeight: CGFloat = 76
    private var maximumHeight: CGFloat { max(300, availableHeight - 8) }
    private var displayedHeight: CGFloat {
        min(maximumHeight, max(collapsedHeight, panelHeight - dragDelta))
    }
    private var expanded: Bool { displayedHeight > collapsedHeight + 35 }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 9) {
                Capsule()
                    .fill(Color.secondary.opacity(0.38))
                    .frame(width: 42, height: 5)
                HStack(spacing: 12) {
                    Text("评论").font(.system(size: 18, weight: .bold))
                    if total > 0 {
                        Text("\(total.formatted())")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22)
            }
            .frame(height: collapsedHeight)
            .contentShape(Rectangle())
            .onTapGesture { snap(to: panelHeight <= collapsedHeight + 10 ? maximumHeight * 0.62 : collapsedHeight) }
            .gesture(panelDrag)

            if expanded {
                Divider()
                HStack {
                    Text("排序方式").font(.headline)
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text("热门")
                    }
                    .font(.subheadline)
                }
                .padding(.horizontal, 22)
                .frame(height: 70)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if vm.reviews.isEmpty && !vm.isLoading {
                            Text("暂无评论")
                                .foregroundStyle(.secondary)
                                .padding(.top, 50)
                        }
                        ForEach(vm.reviews) { review in
                            ReviewRow(review: review, movieID: movieID)
                                .padding(14)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                                .onAppear {
                                    if review.id == vm.reviews.last?.id {
                                        Task { await vm.loadMore(movieID: movieID) }
                                    }
                                }
                        }
                        if vm.isLoading { ProgressView().padding() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .background(Color(.systemGroupedBackground))
                .refreshable { await vm.load(movieID: movieID, force: true) }
            }
        }
        .frame(height: displayedHeight, alignment: .top)
        .background(Color(.systemBackground))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
        .shadow(color: .black.opacity(0.18), radius: 18, y: -5)
    }

    private var panelDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragDelta) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let projected = panelHeight - value.predictedEndTranslation.height
                let medium = maximumHeight * 0.58
                let target: CGFloat
                if projected < (collapsedHeight + medium) / 2 { target = collapsedHeight }
                else if projected < (medium + maximumHeight) / 2 { target = medium }
                else { target = maximumHeight }
                snap(to: target)
            }
    }

    private func snap(to height: CGFloat) {
        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.88)) {
            panelHeight = min(maximumHeight, max(collapsedHeight, height))
        }
    }
}

/// 影评独立列表，可滚动翻页
struct ReviewsListView: View {
    let movieID: String
    var total: Int = 0
    @StateObject private var vm = ReviewsListViewModel()

    var body: some View {
        List {
            ForEach(vm.reviews) { review in
                ReviewRow(review: review, movieID: movieID)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .onAppear {
                        if review.id == vm.reviews.last?.id {
                            Task { await vm.loadMore(movieID: movieID) }
                        }
                    }
            }
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
        .navigationTitle("影评 (\(total > 0 ? "\(total)" : "\(vm.reviews.count)"))")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(movieID: movieID) }
        .refreshable { await vm.load(movieID: movieID, force: true) }
    }
}

@MainActor
final class ReviewsListViewModel: ObservableObject {
    @Published var reviews: [Review] = []
    @Published var isLoading = false
    private var page = 1
    private var hasMore = true

    func load(movieID: String, force: Bool = false) async {
        if !force, !reviews.isEmpty { return }
        page = 1
        hasMore = true
        reviews = []
        await fetch(movieID: movieID)
    }

    func loadMore(movieID: String) async {
        guard hasMore, !isLoading else { return }
        page += 1
        await fetch(movieID: movieID)
    }

    private func fetch(movieID: String) async {
        isLoading = true
        defer { isLoading = false }
        let next = (try? await JavDBSDK.shared.movieReviews(movieID, page: page)) ?? []
        if next.isEmpty {
            hasMore = false
        } else if page == 1 {
            reviews = next
        } else {
            let ids = Set(reviews.map(\.stableReviewID))
            reviews.append(contentsOf: next.filter { !ids.contains($0.stableReviewID) })
        }
    }
}

/// 预告片播放器：系统 AVKit，m3u8 免费预览（sign 已含在 URL，无需登录）。
struct TrailerPlayerView: View {
    let url: URL
    var onClose: (() -> Void)? = nil

    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .padding()
                }
            }
            .onDisappear {
                // 播放器随视图销毁自动释放
            }
    }
}
