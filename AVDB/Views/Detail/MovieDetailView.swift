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
    @AppStorage("detail.showCoverTitle") private var showCoverTitle = true
    @ScaledMetric(relativeTo: .largeTitle) private var portraitTitleSize: CGFloat = 34
    @State private var play115 = false
    /// Build 280: 「从头播放」 for the next 115 session only.
    @State private var pan115FromStart = false
    /// Build 280: 观看历史 tap → resume on the same source (115 or re-resolved online line).
    private var autoLaunch: PlaybackAutoLaunch?
    @State private var autoLaunchDone = false
    @StateObject private var onlineResume = OnlineResumeRequest()
    @ObservedObject private var historyStore = PlaybackHistoryStore.shared
    @State private var showOnlinePlayback = false
    @State private var onlineVersions = false
    @StateObject private var onlinePlaybackModel = OnlinePlaybackModel()
    @State private var showTrailer = false
    @State private var posterPresentation: DetailPosterPresentation<DetailPosterArtwork>?
    // Build 285: on-device AI enhancement of a low-resolution hero cover.
    @StateObject private var aiCover = AICoverEnhanceModel()
    @State private var showCoverViewer = false
    @AppStorage(AICoverEnhanceMode.defaultsKey) private var aiCoverMode = AICoverEnhanceMode.auto.rawValue
    private var aiCoverKey: String {
        guard let art = posterArtwork, !usesLandscapeLayout else { return "none#" + aiCoverMode }
        return art.sourceURL + "#\(art.nativeWidth)x\(art.nativeHeight)#" + aiCoverMode
    }
    private let posterSeed: Movie?
    private var posterMovie: Movie? { posterSeed ?? vm.posterMovie ?? vm.movie }

    private var posterRequestKey: String {
        guard let movie = posterMovie else { return "pending#\(movieID)#\(posterAccountEpoch)" }
        let western = movie.type == "2" ? "#" + TPDBCoverSettings.shared.namespace.uuidString + "#" + (movie.originTitle ?? movie.title ?? "") + "#" + (movie.releaseDate ?? "") + "#" + String(movie.duration ?? 0) + "#" + (movie.originalURL ?? "") : ""
        return DetailPosterResolver.identity(movie: movie, account: APIClient.shared.token) + "#\(posterAccountEpoch)" + western
    }

    private var posterLayout: DetailPosterLayout<DetailPosterArtwork> {
        // Never paint a previous movie/account/source while a new task is scheduled.
        if let presentation = posterPresentation, presentation.key == posterRequestKey { return presentation.layout }
        guard let movie = posterMovie else { return .resolving }
        // Western artwork is always the independent landscape path, never DVD front.
        if movie.type == "2" { return .landscape }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--detail-hero-fixture") {
            if movie.id == "neutral-wide" { return .landscape }
            return DetailPosterResolver.fixtureLayout(movie: movie, account: APIClient.shared.token)
        }
        #endif
        return DetailPosterResolver.initialLayout(movie: movie, account: APIClient.shared.token)
    }

    private var posterArtwork: DetailPosterArtwork? { posterLayout.artwork }
    private var usesLandscapeLayout: Bool { posterLayout.isLandscape }
    @State private var showPosterResources = false
    @State private var tpdbArtwork: TPDBLandscape?
    @State private var tpdbArtworkKey = ""
    private var activeTPDBArtwork: TPDBLandscape? { tpdbArtworkKey == posterRequestKey ? tpdbArtwork : nil }
    @State private var posterAccountEpoch = UUID()
    @State private var reviewPanelHeight: CGFloat = 76
    @StateObject private var reviewsVM = ReviewsListViewModel()
    @ObservedObject private var externalSettings = ExternalLibrarySettings.shared
    @State private var showSearch = false
    @Environment(\.availableLayoutSize) private var layoutSize
    @Environment(\.dismiss) private var dismiss

    init(movieID: String, seed: Movie? = nil, autoLaunch: PlaybackAutoLaunch? = nil) {
        self.movieID = movieID
        self.autoLaunch = autoLaunch
        // A clicked list record with a complete poster identity can start image
        // discovery immediately, independently of the detail/review requests.
        // Incomplete records retain the existing metadata-first path.
        let trusted = seed.flatMap { DetailPosterResolver.navigationSeed($0, movieID: movieID) }
        posterSeed = trusted
        let model = MovieDetailViewModel(movieID: movieID)
        model.movie = trusted
        _vm = StateObject(wrappedValue: model)
    }

    init(movie: Movie) { self.init(movieID: movie.id, seed: movie) }

    #if DEBUG
    init(fixture: Movie) {
        movieID = fixture.id
        posterSeed = nil
        let model = MovieDetailViewModel(movieID: fixture.id)
        model.movie = fixture
        _vm = StateObject(wrappedValue: model)
    }
    #endif

    var body: some View {
        ScrollView(.vertical) {
            if let movie = vm.movie {
                detailContent(movie)
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
        .scrollIndicators(.hidden)
        .modifier(HorizontalScrollLock())
        .background {
            Group {
                if let movie = vm.movie {
                    detailBackground(movie)
                } else {
                    Color(.systemBackground)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if usesLandscapeLayout { detailChrome }
        }
        .ignoresSafeArea(edges: usesLandscapeLayout ? [] : .top)
        .overlay(alignment: .top) {
            if !usesLandscapeLayout { detailChrome }
        }
        .sheet(isPresented: $showOnlinePlayback, onDismiss: { onlinePlaybackModel.cancelPending() }) {
            if let movie = vm.movie {
                OnlinePlaybackSheet(number: movie.displayNumber, model: onlinePlaybackModel, versions: $onlineVersions)
                    .onAppear {
                        onlinePlaybackModel.historyMovie = movie
                        onlinePlaybackModel.historyArtwork = posterArtwork?.image ?? activeTPDBArtwork?.image
                    }
            }
        }
        .onChange(of: movieID) { _, _ in
            showOnlinePlayback = false; onlinePlaybackModel.reset(); onlineVersions = false
        }
        .onChange(of: vm.movie?.displayNumber) { _, _ in
            onlinePlaybackModel.reset(); onlineVersions = false
        }
        .sheet(isPresented: $showPosterResources) {
            if let movie = vm.movie {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 24) {
                            playSection(movie)
                            magnetsSection(movie)
                        }.padding(.vertical)
                    }
                    .navigationTitle("播放与下载资源")
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showPosterResources = false }
                    } }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .avdbCatalogAccountChanged)) { _ in
            var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
            withTransaction(transaction) { posterAccountEpoch = UUID(); posterPresentation = nil }
            showOnlinePlayback = false; onlinePlaybackModel.reset()
            Task { await vm.reloadReviewForAccount() }
        }
        .alert("操作未完成", isPresented: Binding(
            get: { vm.movie != nil && vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) { Button("好", role: .cancel) { vm.errorMessage = nil } }
        message: { Text(vm.errorMessage ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .tpdbCoverChanged)) { _ in
            tpdbArtwork = nil; tpdbArtworkKey = ""; posterAccountEpoch = UUID()
        }
        .task(id: posterRequestKey + "#tpdb") {
            let key = posterRequestKey
            tpdbArtwork = nil; tpdbArtworkKey = ""
            guard let movie = posterMovie, movie.type == "2" else { return }
            let result = await TPDBArtworkService.resolve(movie: movie, namespace: DetailPosterResolver.identity(movie: movie, account: APIClient.shared.token))
            guard !Task.isCancelled, posterRequestKey == key else { return }
            tpdbArtwork = result; tpdbArtworkKey = key
        }
        .task(id: posterRequestKey) {
            guard let movie = posterMovie else { return }
            let key = posterRequestKey
            let account = APIClient.shared.token
            let generation = UUID()
            let initial = posterLayout
            setPosterPresentation(.init(key: key, generation: generation, layout: initial))
            // Warm positive/negative and definite unsupported outcomes are final for
            // this visit. Metadata changes cannot reprobe or flip the chosen layout.
            guard case .resolving = initial else { return }
            let art: DetailPosterArtwork?
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--detail-hero-fixture") {
                art = await DetailPosterResolver.fixtureResolve(movie: movie, account: account) {
                    if ProcessInfo.processInfo.arguments.contains("--delayed-detail-poster") {
                        do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return nil }
                    }
                    return Self.neutralHeroArtwork(wide: false)
                }
            } else {
                art = await DetailPosterResolver.resolve(movie: movie, account: account)
            }
            #else
            art = await DetailPosterResolver.resolve(movie: movie, account: account)
            #endif
            guard !Task.isCancelled, posterRequestKey == key, APIClient.shared.token == account,
                  var presentation = posterPresentation else { return }
            presentation.complete(art, key: key, generation: generation)
            setPosterPresentation(presentation)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 76)
        }
        .overlay(alignment: .bottom) {
            if let movie = vm.movie, !ProcessInfo.processInfo.arguments.contains("--detail-hero-fixture") || ProcessInfo.processInfo.arguments.contains("--long-detail-title") {
                DraggableReviewsPanel(
                    movieID: movie.id,
                    total: movie.commentsCount ?? 0,
                    panelHeight: $reviewPanelHeight,
                    vm: reviewsVM,
                    availableHeight: max(280, layoutSize.height)
                )
                .frame(height: reviewPanelHeight, alignment: .top)
                .accessibilityIdentifier("detail-reviews-panel")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(AdaptiveLayout.isPad ? .visible : .hidden, for: .tabBar)
        .stationaryDetailBackGesture()
        .navigationDestination(isPresented: $showSearch) { SearchView() }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--detail-hero-fixture") { return }
            #endif
            await vm.load()
            // Build 281: the detail payload feeds the on-device recommender (no extra request).
            if let movie = vm.movie { RecommendationIngest.remember(movie) }
            if let autoLaunch, !autoLaunchDone, let movie = vm.movie {
                autoLaunchDone = true
                launchResume(autoLaunch, movie: movie)
            }
            if let movie = vm.movie {
                await reviewsVM.load(movieID: movie.id)
            }
        }
        .fullScreenCover(isPresented: $play115, onDismiss: { pan115FromStart = false }) {
            if let movie = vm.movie { Pan115PlayerView(movie: movie, historyArtwork: posterArtwork?.image ?? activeTPDBArtwork?.image, startFromBeginning: pan115FromStart) }
        }
        .fullScreenCover(item: $onlineResume.plan) { plan in
            OnlineQualityPlayer(plan: plan, historyMovie: vm.movie,
                                historyArtwork: posterArtwork?.image ?? activeTPDBArtwork?.image,
                                startFromBeginning: onlineResume.startFromBeginning)
                .id(plan.id)
        }
        .overlay(alignment: .top) { onlineResumeBanner }
        .onDisappear { onlineResume.cancel() }
        .task(id: aiCoverKey) {
            let art = usesLandscapeLayout ? nil : posterArtwork
            aiCover.prepare(image: art?.image, source: art?.sourceURL ?? "", nativeWidth: art?.nativeWidth ?? 0,
                            nativeHeight: art?.nativeHeight ?? 0, mode: AICoverEnhanceMode(rawValue: aiCoverMode) ?? .auto)
        }
        .fullScreenCover(isPresented: $showCoverViewer) {
            if let art = posterArtwork { AICoverViewer(image: art.image, model: aiCover) }
        }
        .fullScreenCover(isPresented: $showTrailer) {
            if let url = vm.movie?.previewVideoURL.flatMap(URL.init) {
                TrailerPlayerView(url: url, onClose: { showTrailer = false })
            }
        }
    }

    private func setPosterPresentation(_ presentation: DetailPosterPresentation<DetailPosterArtwork>) {
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) { posterPresentation = presentation }
    }

    private var detailChrome: some View {
        HStack {
            chromeButton("chevron.left") { dismiss() }
            Spacer(minLength: 0)
            chromeButton("magnifyingglass") { showSearch = true }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func chromeButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .background(.black.opacity(usesLandscapeLayout ? 0 : 0.30), in: Circle())
                .liquidGlassCircle(interactive: false)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .accessibilityLabel(icon == "chevron.left" ? "返回" : "搜索")
    }

    private func detailBackground(_ movie: Movie) -> some View {
        // Bitmap blur was pre-rendered once off-main; scrolling does not run a filter.
        if let art = posterArtwork {
            return AnyView(ZStack {
                Color(art.tint)
                Image(uiImage: art.backdrop).resizable().scaledToFill().opacity(0.22)
                Color(art.tint).opacity(0.65)
            }.clipped())
        }
        return AnyView(legacyDetailBackground(movie))
    }

    private func legacyDetailBackground(_ movie: Movie) -> some View {
        // 进详情时不要对整屏封面做实时 blur，否则 push 转场会掉帧。
        ZStack {
            Color(red: 0.12, green: 0.12, blue: 0.14)
            LinearGradient(
                colors: [
                    Color(red: 0.24, green: 0.22, blue: 0.25).opacity(0.85),
                    Color(red: 0.10, green: 0.10, blue: 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [.white.opacity(0.16), .clear, .black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func detailContent(_ movie: Movie) -> some View {
        VStack(spacing: 0) {
            if usesLandscapeLayout {
                heroHeader(movie)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("legacy-landscape-header")
            } else {
                // Resolving has exactly the portrait viewport and real metadata /
                // actions, but no speculative cover (especially no wide fallback).
                portraitHero(movie, art: posterArtwork)
                movieInfoCard(movie).padding(.horizontal, 20).padding(.top, 24)
            }

            VStack(alignment: .leading, spacing: 20) {
                if let tags = movie.tags, !tags.isEmpty { tagsSection(tags) }
                if let actors = movie.actors, !actors.isEmpty { actorsSection(actors) }
                if let summary = movie.summary, !summary.isEmpty { summarySection(summary) }
                if let trailer = movie.previewVideoURL, let url = URL(string: trailer) {
                    deferredSection { trailerSection(url) }
                }
                if let images = movie.previewImages, !images.isEmpty {
                    deferredSection { previewImagesSection(images) }
                }
                if (movie.magnetsCount ?? 0) > 0 || externalSettings.enabled {
                    deferredSection { magnetsSection(movie) }
                }
                if !vm.actorMovies.isEmpty {
                    deferredSection { actorMoviesSection(vm.actorMovies) }
                }
                if !vm.relatedMovies.isEmpty {
                    deferredSection { relatedSection(vm.relatedMovies) }
                }
                deferredSection { relatedListsSection }
            }
            .padding(.top, 26)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        }
        .frame(maxWidth: AdaptiveLayout.isPad ? 900 : AdaptiveLayout.contentMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private func portraitHero(_ movie: Movie, art: DetailPosterArtwork?) -> some View {
        let tint = art?.tint ?? UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
        let geometry = DetailPortraitGeometry(availableSize: layoutSize, isPad: AdaptiveLayout.isPad)
        let width = geometry.width
        let imageHeight = geometry.imageHeight
        let titleTop = geometry.titleTop
        return ZStack(alignment: .top) {
            Group {
                if let art {
                    Image(uiImage: aiCover.display(art.image)).resizable().scaledToFill()
                } else {
                    Color(tint).overlay(alignment: .top) {
                        ProgressView().tint(.white.opacity(0.65)).padding(.top, 120)
                    }
                }
            }
            .frame(width: width, height: imageHeight, alignment: .top)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { if art != nil, aiCover.viewerTapAllowed { showCoverViewer = true } }
            .modifier(AICoverPressToCompare(model: aiCover))
            .accessibilityHidden(true)
            .accessibilityIdentifier("detail-hero-artwork")
            LinearGradient(stops: [
                .init(color: .clear, location: 0.36),
                .init(color: Color(tint).opacity(0.24), location: 0.57),
                .init(color: Color(tint).opacity(0.83), location: 0.86),
                .init(color: Color(tint), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: imageHeight + 30)
            .allowsHitTesting(false)   // Build 286: taps / long-press reach the cover underneath.
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if showCoverTitle {
                        DetailReadableTitle(title: movie.displayTitle,
                                            identifier: art == nil ? "resolving-hero-title" : "portrait-hero-title",
                                            font: .system(size: portraitTitleSize * (AdaptiveLayout.isPad ? 1.24 : 1), weight: .bold),
                                            collapsedLines: 2)
                            .shadow(color: .black.opacity(0.25), radius: 8)
                            .padding(.horizontal, 32)
                    }
                    portraitMetadata(movie)
                        .padding(.horizontal, 18).padding(.top, 16)
                    // Build 286: AI 增强 sits under the metadata row, never on top of the cover art.
                    if art != nil, AICoverMetaChip.visible(aiCover) {
                        AICoverMetaChip(model: aiCover) { showCoverViewer = true }
                            .padding(.horizontal, 18).padding(.top, 10)
                            .transition(.opacity)
                    }
                }
                // Lower the entire control row to the reference's ~64% viewport
                // anchor. This is a minimum, never a fixed height or an overlay:
                // expanded / accessibility titles grow and push controls down.
                .frame(minHeight: max(0, geometry.controlsTop - titleTop - 18),
                       alignment: .bottom)
                portraitControls(movie)
                    .padding(.horizontal, 18).padding(.top, 18)
                if let summary = movie.summary, !summary.isEmpty {
                    Text(summary).font(.subheadline).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.top, 18)
                        .accessibilityIdentifier("portrait-hero-synopsis")
                } else {
                    Text("「\(movie.displayNumber)」").font(.system(size: 13))
                        .frame(maxWidth: .infinity).padding(.top, 22)
                }
                PlaybackResourceCards(configured115: Pan115Settings.shared.isConfigured,
                                       onlineAvailable: movie.type != "2" && OnlineIdentity.key(movie.displayNumber) != nil,
                                       externalAvailable: (movie.magnetsCount ?? 0) > 0 || externalSettings.enabled,
                                       play115: { play115 = true },
                                       openOnline: { showOnlinePlayback = true },
                                       openExternal: { showPosterResources = true })
                .padding(.horizontal, 18).padding(.top, 30)
                .buttonStyle(.plain)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("portrait-hero-resources")
            }
            .padding(.top, titleTop)
            .padding(.bottom, 10)
        }
        .foregroundStyle(.white)
        .frame(width: width)

    }



    // Text wraps at narrow widths / accessibility sizes instead of forcing the
    // metadata or controls outside the available detail width.
    private func portraitMetadata(_ movie: Movie) -> some View {
        let values = [movie.displayNumber, movie.releaseDate,
                      movie.duration.map { "\($0 / 60) 小时 \($0 % 60) 分钟" },
                      movie.hasCnsub == true ? "中字" : nil].compactMap { $0 }
        return Text(values.joined(separator: " · "))
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("portrait-hero-metadata")
    }

    private func portraitControls(_ movie: Movie) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                portraitPlayButton
                portraitActionGroup(movie)
            }
            // Large Dynamic Type can need a full-width play label. Never shrink
            // the four existing 44pt action hit targets to keep a single row.
            VStack(spacing: 12) {
                portraitPlayButton.frame(maxWidth: .infinity)
                portraitActionGroup(movie).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        // Do not apply an identifier to ViewThatFits: SwiftUI forwards it to
        // the selected branch and replaces the play button's stable AX identity.
    }

    /// Build 280: the detail play button offers 续播 when 观看历史 has a resumable position on 115 / online.
    private var historyResume: (launch: PlaybackAutoLaunch, title: String, compact: String, source: String, progress: Double?)? {
        guard let movie = vm.movie, let item = historyStore.items.first(where: { $0.movieID == movie.id }) else { return nil }
        let route = PlaybackHistoryRoute.route(source: item.source, isTangxin: false)
        switch route {
        case .pan115: break
        case .online: guard movie.type != "2", OnlineIdentity.key(movie.displayNumber) != nil else { return nil }
        default: return nil
        }
        let key = PlaybackResumeKey.make(number: movie.displayNumber, source: item.source)
        let entry = key.flatMap { PlaybackResumeStore.shared.entry($0, scope: historyStore.scope) }
        let position = entry?.position ?? item.position, length = entry?.length ?? item.length
        guard let title = PlaybackResumePolicy.buttonTitle(position: position, length: length, source: item.source),
              let compact = PlaybackResumePolicy.compactTitle(position: position, length: length) else { return nil }
        return (PlaybackAutoLaunch(route: route, fromBeginning: false, position: item.position, length: item.length), title, compact,
                item.source ?? "", PlaybackResumePolicy.progress(position: position, length: length))
    }

    private func playPrimary() {
        if let resume = historyResume, let movie = vm.movie { launchResume(resume.launch, movie: movie) }
        else { play115 = true }
    }

    private func launchResume(_ launch: PlaybackAutoLaunch, movie: Movie) {
        // Older (≤279) history entries only have the history position: seed the 番号+来源 book once.
        if case .online(let label) = launch.route, let key = PlaybackResumeKey.make(number: movie.displayNumber, source: label) {
            PlaybackResumeStore.shared.seed(key, position: launch.position, length: launch.length, scope: historyStore.scope)
        }
        switch launch.route {
        case .pan115:
            if let key = PlaybackResumeKey.make(number: movie.displayNumber, source: "115") {
                PlaybackResumeStore.shared.seed(key, position: launch.position, length: launch.length, scope: historyStore.scope)
            }
            pan115FromStart = launch.fromBeginning
            play115 = true
        case .online(let label):
            guard let source = OnlineSource.allCases.first(where: { $0.label == label }) else { showOnlinePlayback = true; return }
            onlineResume.start(source, number: movie.displayNumber, fromBeginning: launch.fromBeginning)
        case .javdb, .tangxin, .detailsOnly:
            break // stay on the detail page
        }
    }

    @ViewBuilder private var onlineResumeBanner: some View {
        switch onlineResume.phase {
        case .idle: EmptyView()
        case .working(let text):
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text(text).font(.footnote.weight(.semibold)).lineLimit(2)
                Button("取消") { onlineResume.cancel() }.font(.footnote.weight(.bold))
            }
            .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 10)
            .background(.black.opacity(0.75), in: Capsule())
            .padding(.top, 60)
            .accessibilityIdentifier("detail.resume.online")
        case .failed(let text):
            HStack(spacing: 10) {
                Text(text).font(.footnote).lineLimit(3)
                Button("手动选择") { onlineResume.cancel(); showOnlinePlayback = true }.font(.footnote.weight(.bold))
                Button { onlineResume.cancel() } label: { Image(systemName: "xmark") }
            }
            .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 10)
            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
            .padding(.top, 60).padding(.horizontal, 16)
            .accessibilityIdentifier("detail.resume.failed")
        }
    }

    /// Build 288: one compact pill for both 「▶ 播放」 and 「▶ 续播 02:25」 (source + 从头播放 in the long-press menu,
    /// watched fraction as a thin underline), so the icon group always stays on the same row.
    private var portraitPlayButton: some View {
        let resume = historyResume
        return Button {
            GlassHaptic.tap()
            playPrimary()
        } label: {
            DetailPlayPill(title: resume?.compact ?? "播放", progress: resume?.progress)
        }
        .buttonStyle(.plain)
        .contextMenu { playMenu }
        .accessibilityLabel(resume.map { $0.compact + ($0.source.isEmpty ? "" : "，来源 " + $0.source) } ?? "播放")
        .accessibilityHint(resume == nil ? "" : "长按可从头播放")
        .accessibilityIdentifier("portrait-hero-play")
    }

    @ViewBuilder private var playMenu: some View {
        if let resume = historyResume, let movie = vm.movie {
            Button { launchResume(resume.launch, movie: movie) } label: { Label(resume.title, systemImage: "clock.arrow.circlepath") }
            Button {
                var fromStart = resume.launch; fromStart.fromBeginning = true
                launchResume(fromStart, movie: movie)
            } label: { Label("从头播放", systemImage: "backward.end") }
        }
        Button { play115 = true } label: { Label("播放 115 原画", systemImage: "play.fill") }
    }

    private func portraitActionGroup(_ movie: Movie) -> some View {
        HStack(spacing: 0) {
            posterAction("arrow.down.circle", label: "下载资源") { showPosterResources = true }
            NavigationLink { MyListsView(movieID: movie.id) } label: {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 21, weight: .regular))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("存入清单")
            posterAction(vm.reviewStatus == "want_watch" ? "heart.fill" : "heart", label: "想看") {
                Task { await vm.setReviewStatus("want_watch") }
            }
            .accessibilityIdentifier("detail-want-watch")
            .accessibilityValue(vm.reviewPending ? "正在保存" : (vm.reviewStatus == "want_watch" ? "已选中" : "未选中"))
            .accessibilityHint(vm.reviewStatus == "want_watch" ? "再次轻点取消想看" : "轻点标记想看")
            .disabled(vm.reviewPending || !vm.reviewLoaded)
            posterAction(vm.reviewStatus == "watched" ? "checkmark.rectangle.fill" : "checkmark.rectangle", label: "看过") {
                Task { await vm.setReviewStatus("watched") }
            }
            .accessibilityIdentifier("detail-watched")
            .accessibilityValue(vm.reviewPending ? "正在保存" : (vm.reviewStatus == "watched" ? "已选中" : "未选中"))
            .accessibilityHint(vm.reviewStatus == "watched" ? "再次轻点取消看过" : "轻点标记看过")
            .disabled(vm.reviewPending || !vm.reviewLoaded)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6).padding(.vertical, 2)
        // Match play: a truly clear capsule, not glass or a material fill.
        .background(.clear, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 1.5).allowsHitTesting(false))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("portrait-hero-actions")
    }

    private func posterAction(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 23, weight: .regular))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
    }

    #if DEBUG
    private static func neutralHeroArtwork(wide: Bool) -> DetailPosterArtwork? {
        guard !wide else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 700, height: 1000), format: format).image { ctx in
            UIColor(red: 0.48, green: 0.36, blue: 0.29, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 700, height: 1000))
            UIColor(red: 0.74, green: 0.60, blue: 0.41, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 170, y: 100, width: 360, height: 360))
            UIColor(red: 0.21, green: 0.27, blue: 0.31, alpha: 1).setFill()
            ctx.cgContext.fill(CGRect(x: 130, y: 500, width: 440, height: 500))
        }
        return DetailPosterArtwork(image: image, backdrop: image, tint: UIColor(red: 0.59, green: 0.50, blue: 0.45, alpha: 1), provenance: PosterProvenance(source: "fixture://neutral"))
    }
    #endif

    private func heroHeader(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if showCoverTitle {
                DetailReadableTitle(title: movie.displayTitle, identifier: "landscape-detail-title",
                                    font: .system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }

            ZStack(alignment: .bottomTrailing) {
                if let art = activeTPDBArtwork {
                    Image(uiImage: art.image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("tpdb-landscape-artwork")
                } else {
                    JavDBImage(
                        // 优先顺序：JAVDB cover_url 无水印 → 首张剧照 → DMM 横版 → Tenhow 竖版
                        url: movie.coverURL,
                        fallbackURL: movie.previewImages?.first?.largeURL ?? movie.previewImages?.first?.thumbURL,
                        secondFallbackURL: movie.hdBackdropURL,
                        contentMode: .fill,
                        showsSourceLabel: true
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1.47, contentMode: .fit)
                    .clipped()
                }

                Button {
                    GlassHaptic.tap()
                    playPrimary()
                } label: {
                    Image(systemName: historyResume == nil ? "play.fill" : "clock.arrow.circlepath")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                        .frame(width: 56, height: 56)
                        .liquidGlassCircle()
                }
                .pressableGlass(scale: 0.9)
                .padding(12)
                .contextMenu { playMenu }
                .accessibilityLabel(historyResume?.title ?? "播放")
                .accessibilityIdentifier("landscape-hero-play")
            }
            .liquidCover(cornerRadius: 16)


            movieInfoCard(movie)

            HStack(spacing: 10) {
                GlassActionPill(
                    title: vm.reviewStatus == "want_watch" ? "已想看" : "想看",
                    icon: vm.reviewStatus == "want_watch" ? "heart.fill" : "heart",
                    isSelected: vm.reviewStatus == "want_watch",
                    tint: .pink,
                    minimumHitHeight: 44
                ) {
                    Task { await vm.setReviewStatus("want_watch") }
                }
                .disabled(vm.reviewPending || !vm.reviewLoaded)
                .accessibilityValue(vm.reviewPending ? "正在保存" : (vm.reviewStatus == "want_watch" ? "已选中" : "未选中"))
                GlassActionPill(
                    title: vm.reviewStatus == "watched" ? "已看過" : "看過",
                    icon: vm.reviewStatus == "watched" ? "checkmark.circle.fill" : "checkmark.circle",
                    isSelected: vm.reviewStatus == "watched",
                    tint: .green,
                    minimumHitHeight: 44
                ) {
                    Task { await vm.setReviewStatus("watched") }
                }
                .disabled(vm.reviewPending || !vm.reviewLoaded)
                .accessibilityValue(vm.reviewPending ? "正在保存" : (vm.reviewStatus == "watched" ? "已选中" : "未选中"))
                NavigationLink {
                    MyListsView(movieID: movie.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 14, weight: .semibold))
                        Text("存入清單")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                    .liquidGlass(interactive: false)
                }
                .pressableGlass(scale: 0.94)
            }
            .font(.caption)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func movieInfoCard(_ movie: Movie) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 20) {
                detailLinkLine("番号：", movie.displayNumber) {
                    SeriesNumberMoviesView(
                        number: movie.codePrefix,
                        title: movie.displayNumber,
                        type: movie.catalogType
                    )
                }
                if let date = movie.releaseDate { detailInfoLine("发行日期：", date) }
                if let duration = movie.duration { detailInfoLine("长度：", "\(duration) 分钟") }
                if let director = movie.directorName, !director.isEmpty {
                    if let id = movie.directorID, !id.isEmpty {
                        detailLinkLine("导演：", director) {
                            DirectorMoviesView(directorID: id, title: director, type: movie.catalogType)
                        }
                    } else {
                        detailInfoLine("导演：", director, underline: true)
                    }
                }
                if let maker = movie.makerName, !maker.isEmpty {
                    if let id = movie.makerID, !id.isEmpty {
                        detailLinkLine("制作商：", maker) {
                            MakerMoviesView(makerID: id, title: maker, type: movie.catalogType)
                        }
                    } else {
                        detailInfoLine("制作商：", maker, underline: true)
                    }
                }
                if let series = movie.seriesName, !series.isEmpty, let id = movie.seriesID, !id.isEmpty {
                    detailLinkLine("系列：", series) {
                        SeriesMoviesView(seriesID: id, title: series, type: movie.catalogType)
                    }
                }
                let count = movie.reviewsCount ?? movie.commentsCount ?? 0
                detailInfoLine("评分：", count > 0 ? "共\(count)人评分" : movie.scoreText)
                    .accessibilityIdentifier("detail-info-rating")
                if usesLandscapeLayout {
                    if let art = activeTPDBArtwork {
                        Text(art.label).font(.system(size: 18)).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("detail-cover-source")
                    }
                } else if let art = posterArtwork {
                    Text(art.provenance.text).font(.system(size: 18)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("detail-cover-source")
                }
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
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .frame(width: 72, height: 86)
                .background {
                    let shape = UnevenRoundedRectangle(
                        bottomLeadingRadius: 18,
                        bottomTrailingRadius: 18,
                        style: .continuous
                    )
                    GlassBody(shape: shape, tint: .orange, tintStrength: 0.58)
                }
                .overlay {
                    GlassRim(
                        shape: UnevenRoundedRectangle(
                            bottomLeadingRadius: 18,
                            bottomTrailingRadius: 18,
                            style: .continuous
                        )
                    )
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .padding(.trailing, 18)
            }
        }
        .foregroundStyle(Color(red: 0.16, green: 0.12, blue: 0.13))
        .glassSurface(
            in: RoundedRectangle(cornerRadius: 16, style: .continuous),
            tint: Color(red: 0.98, green: 0.96, blue: 0.95),
            tintStrength: 0.96,
            elevation: 0.8,
            scrolling: true
        )
    }

    private func deferredSection<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        DeferredDetailSection(content: content)
    }

    private func detailInfoLine(_ label: String, _ value: String, underline: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(label)
            Text(value).underline(underline)
        }
        .font(.system(size: 18, weight: .regular))
    }

    private func detailLinkLine<D: View>(_ label: String, _ value: String, @ViewBuilder destination: () -> D) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(label)
            NavigationLink(destination: destination()) {
                Text(value)
                    .underline()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: 18, weight: .regular))
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
                .liquidCover(cornerRadius: 10)

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
            GlassSectionHeader(title: "标签", icon: "tag.fill", trailingTitle: nil)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(tags.enumerated()), id: \.element.id) { idx, tag in
                    NavigationLink {
                        TagMoviesView(tag: tag, catalogType: vm.movie?.catalogType ?? "0")
                    } label: {
                        Text(tag.name ?? "")
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .glassSurface(in: Capsule(), elevation: 0.35, scrolling: true)
                            .contentShape(Capsule())
                    }
                    .pressableGlass(scale: 0.94)
                    }
            }
        }
        .padding(.horizontal)
    }

    private func actorsSection(_ actors: [Actor]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader(title: "演员", icon: "person.2.fill", trailingTitle: nil)
                .padding(.horizontal)

            // 静态自适应网格，避免横向 ScrollView 让头像被手指拖动。
            // 演员较多时自动换行，点击进入详情的行为保持不变。
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 70, maximum: 82), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(actors) { actor in
                    NavigationLink {
                        ActorDetailView(actorID: actor.id)
                    } label: {
                        VStack(spacing: 4) {
                            ActorAvatarArtwork(actor: actor, numbers: [vm.movie?.number].compactMap { $0 })
                                .frame(width: 70, height: 70)
                                .clipShape(Circle())
                            Text(actor.name ?? "")
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 70)
                        }
                        .frame(width: 70)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal)
        }
    }

    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader(title: "简介", icon: "text.alignleft", trailingTitle: nil)
            Text(summary)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous), elevation: 0.4, scrolling: true)
        }
        .padding(.horizontal)
    }

    private func previewImagesSection(_ images: [PreviewImage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader(title: "剧照", icon: "photo.on.rectangle", trailingTitle: nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { idx, img in
                        JavDBImage(url: img.largeURL ?? img.thumbURL, maxPixelSize: 720)
                            .frame(width: 260, height: 160)
                            .liquidCover(cornerRadius: 14)
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
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    private func trailerSection(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader(title: "预告片", icon: "play.rectangle.fill", trailingTitle: nil)
            Button {
                GlassHaptic.tap()
                showTrailer = true
            } label: {
                ZStack {
                    JavDBImage(url: vm.movie?.coverURL ?? vm.movie?.thumbURL, contentMode: .fill)
                        .frame(height: 180)
                        .clipped()
                    LinearGradient(
                        colors: [.black.opacity(0.15), .black.opacity(0.45)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .liquidGlassCircle()
                }
                .liquidCover(cornerRadius: 16)
            }
            .pressableGlass(scale: 0.98)
        }
        .padding(.horizontal)
    }

    private func magnetsSection(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader(
                title: "磁力链接",
                icon: "link",
                badge: "\(movie.magnetsCount ?? 0)",
                trailingTitle: nil
            )
            if vm.magnets.isEmpty && vm.loadingMagnets {
                ProgressView()
            } else {
                ForEach(vm.magnets, id: \.stableID) { magnet in
                    MagnetRow(magnet: magnet, movieID: movie.id, movieNumber: movie.displayNumber)
                }
            }
            if let status = vm.externalStatus {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .task(id: externalSettings.revision) { await vm.loadMagnets() }
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
            GlassSectionHeader(title: "相似推荐", icon: "sparkles", trailingTitle: nil)
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
            GlassSectionHeader(title: "Ta 还出演过", icon: "person.crop.rectangle.stack", trailingTitle: nil)
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
            GlassSectionHeader(title: "相关片单", icon: "list.bullet.rectangle", trailingTitle: nil)
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
                        .glassSurface(
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                            elevation: 0.35,
                            scrolling: true
                        )
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
    // Immutable native image identity for this visit; text enrichment cannot
    // restart the winner task, change geometry or publish a second winner.
    @Published private(set) var posterMovie: Movie?
    private var loadGeneration = UUID()
    @Published var relatedMovies: [Movie] = []
    @Published var actorMovies: [Movie] = []
    @Published var magnets: [Magnet] = []
    @Published var externalStatus: String?
    private var nativeMagnets: [Magnet] = []
    private var loadedNativeMagnets = false
    @Published var reviews: [Review] = []
    @Published var relatedLists: [MovieList] = []
    @Published var reviewStatus: String?
    @Published private(set) var reviewPending = false
    @Published private(set) var reviewLoaded = false
    private var reviewRevision = 0
    private let updateReview: (String, String?) async throws -> String?
    @Published var isLoading = false
    @Published var loadingMagnets = false
    @Published var loadingLists = false
    @Published var errorMessage: String?
    private var listsPage = 1
    private var listsHasMore = true

    private let sdk = JavDBSDK.shared

    init(movieID: String? = nil,
         updateReview: ((String, String?) async throws -> String?)? = nil) {
        self.movieID = movieID ?? ""
        self.updateReview = updateReview ?? { try await JavDBSDK.shared.updateMovieReview($0, status: $1) }
        reviewLoaded = updateReview != nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--detail-hero-fixture") { reviewLoaded = true }
        #endif
    }

    func load() async {
        guard !movieID.isEmpty else { return }
        let generation = UUID()
        let revision = reviewRevision
        loadGeneration = generation
        let account = APIClient.shared.token
        isLoading = true
        defer { if loadGeneration == generation { isLoading = false } }
        do {
            let full = try await sdk.movieDetailFull(movieID, onNative: { native in
                guard !Task.isCancelled, self.loadGeneration == generation,
                      APIClient.shared.token == account, native.movie?.id == self.movieID else { return }
                if self.posterMovie == nil { self.posterMovie = native.movie }
                self.movie = native.movie
            })
            guard !Task.isCancelled, loadGeneration == generation,
                  APIClient.shared.token == account, full.movie?.id == movieID else { return }
            movie = full.movie
            relatedMovies = full.movie?.relativeMovies
                ?? full.relativeMovies
                ?? []
            actorMovies = full.movie?.actorMovies
                ?? full.actorMovies
                ?? []
            let authenticatedStatus = try await sdk.movieReview(movieID)?.status
            guard !Task.isCancelled, loadGeneration == generation, APIClient.shared.token == account,
                  reviewRevision == revision, !reviewPending else { return }
            reviewStatus = authenticatedStatus
            reviewLoaded = true
        } catch {
            guard !Task.isCancelled, loadGeneration == generation, APIClient.shared.token == account else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadMagnets() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--detail-hero-fixture") { return }
        #endif
        guard !movieID.isEmpty else { return }
        let settings = ExternalLibrarySettings.shared
        let generation = settings.revision
        magnets = nativeMagnets // Drop old source results before fetching under a new configuration.
        externalStatus = nil
        loadingMagnets = true
        defer { if generation == settings.revision { loadingMagnets = false } }
        if !loadedNativeMagnets, let m = try? await sdk.movieMagnets(movieID) {
            guard !Task.isCancelled, generation == settings.revision else { return }
            nativeMagnets = m
            magnets = m
            loadedNativeMagnets = true
        }
        guard !Task.isCancelled, generation == settings.revision else { return }
        guard settings.enabled else { externalStatus = "外部数据库已停用"; return }
        let number = movie?.displayNumber ?? movie?.number ?? ""
        do {
            guard let token = try settings.token(), !token.isEmpty else {
                externalStatus = "外部数据库未配置令牌，请前往「我的 → 外部数据库」保存。"
                return
            }
            let links = try await ExternalLibraryClient.shared.fetchLinks(for: number)
            guard !Task.isCancelled, generation == settings.revision else { return }
            var existing = Set(magnets.compactMap(\.magnetURL))
            let extra = links.compactMap { link -> Magnet? in
                guard existing.insert(link.downloadURL).inserted else { return nil }
                return Magnet(link: link)
            }
            magnets.append(contentsOf: extra)
            externalStatus = links.isEmpty ? "外部数据库查询成功，暂无资源" : "外部数据库已加载"
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == settings.revision else { return }
            externalStatus = error.localizedDescription
        }
    }

    func loadReviews() async {
        guard !movieID.isEmpty, reviews.isEmpty else { return }
        if let r = try? await sdk.movieReviews(movieID) {
            reviews = r
        }
    }

    func reloadReviewForAccount() async {
        reviewRevision += 1
        let revision = reviewRevision
        let account = APIClient.shared.token
        reviewStatus = nil; reviewLoaded = false; reviewPending = false
        guard account?.isEmpty == false else { return }
        do {
            let status = try await sdk.movieReview(movieID)?.status
            guard reviewRevision == revision, APIClient.shared.token == account else { return }
            reviewStatus = status; reviewLoaded = true
        } catch {
            guard reviewRevision == revision, APIClient.shared.token == account else { return }
            errorMessage = error.localizedDescription
        }
    }

    func setReviewStatus(_ status: String) async {
        guard !movieID.isEmpty, reviewLoaded, !reviewPending else { return }
        // Both controls share one pending lock because the server has ONE review status.
        let old = reviewStatus
        let desired: String? = old == status ? nil : status
        let account = APIClient.shared.token
        reviewRevision += 1
        let revision = reviewRevision
        reviewPending = true
        reviewStatus = desired
        defer { if reviewRevision == revision { reviewPending = false } }
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--detail-hero-fixture") {
                try await Task.sleep(nanoseconds: 150_000_000)
                return
            }
            #endif
            let actual = try await updateReview(movieID, desired)
            guard reviewRevision == revision else { return }
            guard APIClient.shared.token == account else { reviewStatus = nil; reviewLoaded = false; return }
            guard actual == desired else {
                throw JavDBError.apiError(action: nil, message: "状态未确认，请重试")
            }
            reviewStatus = actual
        } catch {
            guard reviewRevision == revision else { return }
            guard APIClient.shared.token == account else { reviewStatus = nil; reviewLoaded = false; return }
            reviewStatus = old
            errorMessage = "操作未确认，已恢复原显示：\(error.localizedDescription)"
        }
    }

    func loadRelatedLists() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--detail-hero-fixture") { return }
        #endif
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
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .glassSurface(in: RoundedRectangle(cornerRadius: 12, style: .continuous), elevation: 0.45, scrolling: true)
        .glassPressFeedback()
        .onTapGesture {
            GlassHaptic.tap()
            Task { await pushTo115() }
        }
        .onLongPressGesture {
            GlassHaptic.success()
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
        guard DownloadLinkDetector.isOfflineResource(url) else {
            toast = "仅支持有效 magnet / ed2k 资源，网页或播放流不可推送"
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
            let result = try await Pan115Client.shared.addOfflineTask(
                url: url,
                cookie: settings.cookie,
                folderCID: settings.folderCID
            )
            if !movieID.isEmpty {
                Pan115PlaybackCache.save(movieID: movieID, magnet: url)
            }
            toast = result.message
        } catch {
            toast = error.localizedDescription
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
        VStack(alignment: .leading, spacing: 10) {
            // 用户信息行
            HStack(spacing: 8) {
                Text((review.userName ?? "匿名").prefix(1))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(Color(.secondarySystemBackground))
                        Circle().fill(Color.blue.opacity(0.16))
                        Circle().fill(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.4), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1.5)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.userName ?? "匿名")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    if let date = review.createdAt {
                        Text(Self.shortDate(date))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if let score = review.score {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(score)")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.orange.gradient)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassSurface(
                        in: Capsule(),
                        tint: .orange,
                        tintStrength: 0.16,
                        elevation: 0.3
                    )
                }
            }

            // 评论内容
            if let content = review.content {
                Text(content)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }

            // 识别到的下载链接
            if !links.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                        linkRow(link)
                    }
                }
                .padding(.top, 4)
            }

            // 识别到的番号（点击复制）
            if !numbers.isEmpty {
                FlowTags(numbers: numbers) { number in
                    copyNumber(number)
                }
                .padding(.top, 4)
            }

            if let toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.15), in: Capsule())
            }
        }
    }

    private func linkRow(_ link: DownloadLinkKind) -> some View {
        let key = link.rawValue
        let state = linkStates[key] ?? .idle
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: link.isDownloadLink ? "link.circle.fill" : "number.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(link.isDownloadLink ? Color.green : Color.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(link.rawValue)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    copyText(link.rawValue)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                        Text("复制")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                if link.isDownloadLink {
                    Button {
                        Task { await push(to: link) }
                    } label: {
                        HStack(spacing: 4) {
                            if case .pushing = state {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "icloud.and.arrow.up")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("推送到115")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(linkStates[key] != nil)
                }
            }
        }
        .padding(10)
        .glassSurface(in: RoundedRectangle(cornerRadius: 12, style: .continuous), elevation: 0.5)
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
            let result = try await Pan115Client.shared.addOfflineTask(
                url: link.rawValue,
                cookie: settings.cookie,
                folderCID: settings.folderCID
            )
            if !movieID.isEmpty {
                Pan115PlaybackCache.save(movieID: movieID, magnet: link.rawValue)
            }
            toast = result.message
        } catch {
            toast = error.localizedDescription
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
                        .glassSurface(in: Capsule(), elevation: 0.3)
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary)
            }
        }
    }
}

/// 评论面板：把手拖动改高度，列表用系统 ScrollView，互不抢手势。
struct DraggableReviewsPanel: View {
    let movieID: String
    let total: Int
    @Binding var panelHeight: CGFloat
    @ObservedObject var vm: ReviewsListViewModel
    let availableHeight: CGFloat

    private let collapsedHeight: CGFloat = 76
    private var maximumHeight: CGFloat {
        let top = max(59, safeTop + 12)
        return max(300, availableHeight - top)
    }

    private var safeTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 59
    }
    private var mediumHeight: CGFloat { collapsedHeight + (maximumHeight - collapsedHeight) * 0.55 }

    @State private var panelState: PanelState = .collapsed
    @State private var dragStartHeight: CGFloat?

    enum PanelState {
        case collapsed, medium, expanded

        func height(collapsed: CGFloat, medium: CGFloat, max: CGFloat) -> CGFloat {
            switch self {
            case .collapsed: return collapsed
            case .medium: return medium
            case .expanded: return max
            }
        }
    }

    /// 展开中：高度略高于收起就显示列表，拖动过程内容跟着长高，避免「松手才蹦出来」
    private var isContentVisible: Bool {
        panelHeight > collapsedHeight + 6 || panelState != .collapsed
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .frame(height: collapsedHeight)
                .contentShape(Rectangle())
                .gesture(handleDrag, including: .all)
                .onTapGesture { toggleFromHeader() }

            if isContentVisible {
                sortSection
                reviewsList
            }
        }
        .frame(height: panelHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        .contentShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 10, y: -2)
        .safeAreaPadding(.bottom)
    }

    private var handleDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let dx = abs(value.translation.width)
                let dy = abs(value.translation.height)
                guard dy >= dx else { return }
                if dragStartHeight == nil { dragStartHeight = panelHeight }
                let next = (dragStartHeight ?? panelHeight) - value.translation.height
                // 拖动过程直接改高度，不套动画，保证跟手
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    panelHeight = min(maximumHeight, max(collapsedHeight, next))
                }
            }
            .onEnded { value in
                defer { dragStartHeight = nil }
                guard abs(value.translation.height) >= abs(value.translation.width) else { return }
                let start = dragStartHeight ?? panelHeight
                let predicted = start - value.predictedEndTranslation.height
                let velocityY = value.predictedEndTranslation.height - value.translation.height
                snap(to: predicted, velocityY: velocityY)
            }
    }

    private func toggleFromHeader() {
        let next: PanelState = panelState == .collapsed ? .medium : .collapsed
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.88)) {
            panelState = next
            panelHeight = next.height(collapsed: collapsedHeight, medium: mediumHeight, max: maximumHeight)
        }
    }

    private func snap(to predicted: CGFloat, velocityY: CGFloat) {
        let span = max(1, maximumHeight - collapsedHeight)
        let next: PanelState
        if velocityY < -900 {
            next = .expanded
        } else if velocityY > 900 {
            next = .collapsed
        } else if predicted < collapsedHeight + span * 0.28 {
            next = .collapsed
        } else if predicted < collapsedHeight + span * 0.72 {
            next = .medium
        } else {
            next = .expanded
        }
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.88)) {
            panelState = next
            panelHeight = next.height(collapsed: collapsedHeight, medium: mediumHeight, max: maximumHeight)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 9) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 42, height: 5)
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("评论")
                        .font(.system(size: 18, weight: .bold))
                }
                if total > 0 {
                    Text("\(total.formatted())")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(panelState == .collapsed ? 0 : 180))
            }
            .padding(.horizontal, 22)
        }
    }

    private var sortSection: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("排序方式")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Picker("排序方式", selection: $vm.sortBy) {
                    Text("最热").tag("hotly")
                    Text("最新").tag("recently")
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .onChange(of: vm.sortBy) { _, _ in
                    Task { await vm.load(movieID: movieID, force: true) }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            Divider()
        }
    }

    private var reviewsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if vm.reviews.isEmpty && !vm.isLoading {
                    Text("暂无评论")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 50)
                }
                ForEach(vm.reviews, id: \.stableReviewID) { review in
                    ReviewRow(review: review, movieID: movieID)
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onAppear {
                            if review.stableReviewID == vm.reviews.last?.stableReviewID {
                                Task { await vm.loadMore(movieID: movieID) }
                            }
                        }
                }
                if vm.isLoading {
                    ProgressView().padding()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// 影评独立列表，可滚动翻页
struct ReviewsListView: View {
    let movieID: String
    var total: Int = 0
    @StateObject private var vm = ReviewsListViewModel()

    var body: some View {
        List {
            ForEach(vm.reviews, id: \.stableReviewID) { review in
                ReviewRow(review: review, movieID: movieID)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .onAppear {
                        if review.stableReviewID == vm.reviews.last?.stableReviewID {
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
    @Published var sortBy = "hotly"
    private var page = 1
    private var hasMore = true

    func load(movieID: String, force: Bool = false) async {
        if !force, !reviews.isEmpty { return }
        page = 1
        hasMore = true
        await fetch(movieID: movieID, replace: true)
    }

    func loadMore(movieID: String) async {
        guard hasMore, !isLoading else { return }
        page += 1
        await fetch(movieID: movieID, replace: false)
    }

    private func fetch(movieID: String, replace: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await JavDBSDK.shared.movieReviews(
                movieID, page: page, sortBy: sortBy, limit: 24
            )
            if replace {
                reviews = next
            } else if !next.isEmpty {
                let ids = Set(reviews.map(\.stableReviewID))
                reviews.append(contentsOf: next.filter { !ids.contains($0.stableReviewID) })
            }
            hasMore = !next.isEmpty
        } catch {
            if replace {
                page = 1
            } else {
                page = max(1, page - 1)
            }
        }
    }
}

/// 预告片播放器：系统 AVKit，m3u8 免费预览（sign 已含在 URL，无需登录）。
struct TrailerPlayerView: View {
    let url: URL
    var onClose: (() -> Void)? = nil
    @StateObject private var playback: TrailerPlayback

    init(url: URL, onClose: (() -> Void)? = nil) {
        self.url = url
        self.onClose = onClose
        _playback = StateObject(wrappedValue: TrailerPlayback(url: url))
    }

    var body: some View {
        AudioOwnedTrailerPlayer(playback: playback)
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
            // Player/model destruction, not transient disappearance, stops and releases this preview.
    }
}

/// 滑到附近才创建重区块，避免打开详情时一次绘制全部玻璃和图片。
private struct DeferredDetailSection<Content: View>: View {
    let content: () -> Content
    @State private var isVisible = false

    var body: some View {
        Group {
            if isVisible {
                content()
            } else {
                Color.clear.frame(height: 180)
            }
        }
        .onAppear { isVisible = true }
    }
}

/// 固定详情页，避免整页被左右拖动。
private struct HorizontalScrollLock: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
    }
}

// Build226: pure policy shared verbatim with the macOS Swift regression.
struct DetailBackGesturePolicy {
    static let edge: CGFloat = 26
    static func starts(x: CGFloat, width: CGFloat, rtl: Bool) -> Bool {
        let leading = rtl ? width - x : x
        return width > 0 && leading >= 0 && leading <= edge
    }
    static func horizontal(x: CGFloat, y: CGFloat, rtl: Bool) -> Bool {
        let forward = rtl ? -x : x
        return forward > 0 && forward > abs(y) * 1.5
    }
    static func commits(x: CGFloat, y: CGFloat, velocity: CGFloat, width: CGFloat, rtl: Bool) -> Bool {
        let forward = rtl ? -x : x
        let speed = rtl ? -velocity : velocity
        guard horizontal(x: x, y: y, rtl: rtl), speed > -100 else { return false }
        return forward >= min(120, max(72, width * 0.22)) || (forward >= 36 && speed >= 650)
    }
}

/// A completion-only leading-edge pan. Never drives a percent transition or a
/// view transform; even the committed pop is unanimated to keep artwork fixed.
struct StationaryDetailBackGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.install() }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.uninstall() }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var installedNavigation: UINavigationController?
        private weak var detailController: UIViewController?
        private var previousPopEnabled: Bool?
        private var pan: UIPanGestureRecognizer?
        private var committed = false
        private var rtl: Bool { installedNavigation?.view.effectiveUserInterfaceLayoutDirection == .rightToLeft }
        override func loadView() {
            view = UIView(); view.backgroundColor = .clear; view.isUserInteractionEnabled = false
        }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install() }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); uninstall() }
        func install() {
            guard viewIfLoaded?.window != nil, pan == nil, let nav = navigationController,
                  let top = nav.topViewController else { return }
            var ancestor: UIViewController? = self
            while ancestor != nil && ancestor !== top { ancestor = ancestor?.parent }
            guard ancestor === top else { return }
            installedNavigation = nav; detailController = top; committed = false
            previousPopEnabled = nav.interactivePopGestureRecognizer?.isEnabled
            nav.interactivePopGestureRecognizer?.isEnabled = false
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            recognizer.maximumNumberOfTouches = 1; recognizer.delegate = self
            recognizer.cancelsTouchesInView = true
            nav.view.addGestureRecognizer(recognizer); pan = recognizer
        }
        func uninstall() {
            if let pan { pan.view?.removeGestureRecognizer(pan) }
            if let enabled = previousPopEnabled { installedNavigation?.interactivePopGestureRecognizer?.isEnabled = enabled }
            pan = nil; previousPopEnabled = nil; installedNavigation = nil; detailController = nil
        }
        private var canPop: Bool {
            guard let nav = installedNavigation, let detail = detailController else { return false }
            return !committed && nav.topViewController === detail && nav.viewControllers.count > 1
                && nav.presentedViewController == nil && detail.presentedViewController == nil
                && nav.transitionCoordinator == nil && detail.viewIfLoaded?.window != nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard canPop, let view = gestureRecognizer.view else { return false }
            return DetailBackGesturePolicy.starts(x: touch.location(in: view).x, width: view.bounds.width, rtl: rtl)
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard canPop, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return DetailBackGesturePolicy.horizontal(x: velocity.x, y: velocity.y, rtl: rtl)
        }
        // Give only edge-origin, horizontal-intent back pans priority over a
        // scroll pan. Vertical intent fails shouldBegin, releasing the scroller;
        // no simultaneous scrolling may move artwork during an accepted pan.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard canPop, let scroll = other.view as? UIScrollView else { return false }
            return other === scroll.panGestureRecognizer
        }
        @objc private func handle(_ sender: UIPanGestureRecognizer) {
            #if DEBUG
            recordProbe(sender)
            #endif
            guard sender.state == .ended, canPop, let nav = installedNavigation else { return }
            let delta = sender.translation(in: nav.view), velocity = sender.velocity(in: nav.view)
            guard DetailBackGesturePolicy.commits(x: delta.x, y: delta.y, velocity: velocity.x, width: nav.view.bounds.width, rtl: rtl) else { return }
            committed = true
            nav.popViewController(animated: false)
        }
        #if DEBUG
        private var startFrames: [CGRect] = []
        private var startOffsets: [CGPoint] = []
        private var probeSamples = 0
        private var probeStable = true
        private var probeInteractive = false
        private func recordProbe(_ sender: UIPanGestureRecognizer) {
            guard ProcessInfo.processInfo.arguments.contains("--detail-back-probe"), let root = detailController?.view else { return }
            func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { views($0) } }
            let all = views(root)
            let frames = all.map { $0.layer.presentation()?.frame ?? $0.layer.frame }
            let offsets = all.compactMap { ($0 as? UIScrollView)?.contentOffset }
            let interactive = installedNavigation?.interactivePopGestureRecognizer?.isEnabled == true
                || installedNavigation?.transitionCoordinator?.isInteractive == true
            if sender.state == .began {
                startFrames = frames; startOffsets = offsets; probeSamples = 0; probeStable = true
                probeInteractive = interactive
            } else if sender.state == .changed {
                probeSamples += 1
                probeInteractive = probeInteractive || interactive
                probeStable = probeStable && frames == startFrames && offsets == startOffsets
                if probeSamples == 1, let window = root.window {
                    // Native window render while touches are active, not a web
                    // recreation. Only enabled by the neutral fixture UI test.
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
                    }
                    let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    try? image.pngData()?.write(to: folder.appendingPathComponent("226-mid-pan-\(Int(window.bounds.width))x\(Int(window.bounds.height)).png"))
                }
            }
            if sender.state == .ended || sender.state == .cancelled {
                UserDefaults.standard.set("samples=\(probeSamples);stable=\(probeStable);interactive=\(probeInteractive)", forKey: "detail-back-probe")
                NotificationCenter.default.post(name: Notification.Name("detail-back-probe"), object: nil)
            }
        }
        #endif
    }
}

extension View {
    func stationaryDetailBackGesture() -> some View {
        background { StationaryDetailBackGesture().frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true) }
    }
}

#if DEBUG
/// Self-authored geometric artwork and fictional catalog metadata (CC0).
/// Uses MovieDetailView itself, not an HTML recreation or a screenshot mock.
struct DetailHeroFixtureGallery: View {
    var nested = false
    @State private var backProbe = ""

    private func movie(wide: Bool) -> Movie {
        let title = ProcessInfo.processInfo.arguments.contains("--long-detail-title")
            ? String(repeating: "静かな庭園と四季の光をめぐる幾何学の物語。中性排版测试，完整封面与可阅读的信息。", count: 8)
            : "静谧之光\\nNeutral Study"
        let json = """
        {"id":"neutral-\(wide ? "wide" : "portrait")","type":"0","number":"DEMO-123",
        "title":"\(title)","cover_url":"fixture://poster/\(wide ? "wrap" : "portrait")",
        "release_date":"2026-10-15","duration":134,"magnets_count":0,
        "summary":"自制几何图形用于验证海报详情层级与安全区域，不含真实影片或人物。",
        "tags":[{"id":"neutral-tag","name":"几何艺术"}]}
        """
        return try! JSONDecoder().decode(Movie.self, from: Data(json.utf8))
    }
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--detail-back-root") {
            MovieDetailView(fixture: movie(wide: false))
        } else {
            gallery
        }
    }
    private var gallery: some View {
        List {
            CoverTitleSettingsSection()
            NavigationLink("Portrait detail") { MovieDetailView(fixture: movie(wide: false)) }
                .accessibilityIdentifier("neutral-portrait-link")
            NavigationLink("Wide detail") { MovieDetailView(fixture: movie(wide: true)) }
                .accessibilityIdentifier("neutral-wide-link")
            if ProcessInfo.processInfo.arguments.contains("--detail-back-probe") {
                if nested {
                    Text("Existing intermediate level").accessibilityIdentifier("detail-back-intermediate")
                } else {
                    NavigationLink("Nested fixtures") { DetailHeroFixtureGallery(nested: true) }
                        .accessibilityIdentifier("detail-back-nested-link")
                }
                Text(backProbe).accessibilityIdentifier("detail-back-probe-result")
            }
        }.navigationTitle("Neutral Detail Fixtures")
        .onAppear { backProbe = UserDefaults.standard.string(forKey: "detail-back-probe") ?? "" }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("detail-back-probe"))) { _ in
            backProbe = UserDefaults.standard.string(forKey: "detail-back-probe") ?? ""
        }
    }
}
#endif

// MARK: - Portrait viewport policy (also exercised by the native regression)
struct DetailPortraitGeometry {
    let width: CGFloat
    let imageHeight: CGFloat
    let titleTop: CGFloat
    let controlsTop: CGFloat

    init(availableSize: CGSize, isPad: Bool) {
        width = max(1, min(availableSize.width, isPad ? 900 : 600))
        imageHeight = min(width * 1.58, max(600, availableSize.height * 0.8))
        // Scene geometry excludes safe-area bars. The width-based lower-hero
        // cap and 56% scene anchor keep the title near 50% of the full display.
        titleTop = min(width * 1.06, max(390, availableSize.height * 0.56))
        // Reserve a readable two-line title + metadata interval even when the
        // scene is shorter than the display. This puts the whole row near 64%
        // on tall phones instead of the previous ~51–59% placement.
        controlsTop = max(titleTop + 132, min(width * 1.42, availableSize.height * 0.64))
    }
}

// Two invisible measurements use the exact same SwiftUI font and wrapping width
// as the readable title, including Japanese and accessibility Dynamic Type.
private struct DetailTitleHeights: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct DetailReadableTitle: View {
    let title: String
    let identifier: String
    var font: Font = .title2.weight(.bold)
    var collapsedLines: Int = 3
    @State private var expanded = false
    @State private var truncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleText.lineLimit(expanded ? nil : collapsedLines)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
                .background(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        titleText.lineLimit(collapsedLines).fixedSize(horizontal: false, vertical: true)
                            .background { GeometryReader { proxy in
                                Color.clear.preference(key: DetailTitleHeights.self, value: ["collapsed": proxy.size.height])
                            } }
                        titleText.fixedSize(horizontal: false, vertical: true)
                            .background { GeometryReader { proxy in
                                Color.clear.preference(key: DetailTitleHeights.self, value: ["full": proxy.size.height])
                            } }
                    }.hidden().accessibilityHidden(true).allowsHitTesting(false)
                }
            if truncated {
                Button { expanded.toggle() } label: {
                    Text(expanded ? "收起标题" : "展开全文")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("detail-title-toggle")
                    .accessibilityValue(expanded ? "已展开" : "已收起")
            }
        }
        .onPreferenceChange(DetailTitleHeights.self) { heights in
            truncated = (heights["full"] ?? 0) > (heights["collapsed"] ?? 0) + 1
        }
    }
    private var titleText: some View {
        Text(title).font(font).lineSpacing(4).multilineTextAlignment(.leading)
    }
}
