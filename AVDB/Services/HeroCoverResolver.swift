import Foundation
import UIKit
import Network

extension Notification.Name {
    /// Posted when the path monitor flips from unsatisfied to satisfied.
    /// Hero retries items that stayed in blur because a previous attempt failed.
    static let heroCoverNetworkRecovered = Notification.Name("avdb.hero.cover.networkRecovered")
}

/// Build 326 hero-only cover policy. Independent of VisibleHQPosterPolicy
/// (no 900 px cap, no one-URL fan-in, no 8 s timeout, no Low Power skip,
/// no 10-minute list negative cache).
enum HeroCoverPolicy {
    static let decodeCap = 2048
    static let sourceTimeout: TimeInterval = 4
    /// In-flight sharp loads may outlive the 6s provisional settle so a late
    /// A/B (e.g. a CDN that answers at 15s) can still upgrade the floor.
    static let upgradeTimeout: TimeInterval = 20
    static let overallBudget: TimeInterval = 6
    #if DEBUG
    /// Tests inject a shorter per-item deadline (MIDE-991 stand-in).
    static var overallBudgetOverride: TimeInterval?
    static var effectiveOverallBudget: TimeInterval { overallBudgetOverride ?? overallBudget }
    #else
    static var effectiveOverallBudget: TimeInterval { overallBudget }
    #endif
    static let graceWindow: TimeInterval = 0.4
    static let crossfadeDuration: TimeInterval = 0.45
    static let prefetchConcurrency = 3
    /// Build 330: DetailPosterResolver scheduler cap (current → +1 → −1 → +2 → −2).
    static let resolverConcurrency = 2
    static let lowPowerPrefetchConcurrency = 1
    static let negativeTTL: TimeInterval = 60
    static let foregroundRetryInterval: TimeInterval = 60
    /// height / width of the decoded, cropped portrait bitmap.
    static let aspectMin = 1.30
    static let aspectMax = 1.55
    static let tierAWidth = 1000
    static let tierBWidth = 700
    static let tierCWidth = 360
    /// Same-tier width difference at or below this fraction: native portrait `ps` wins.
    static let sameTierWidthEpsilon = 0.10

    static func prefetchLimit(lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled) -> Int {
        lowPower ? lowPowerPrefetchConcurrency : resolverConcurrency
    }

    static func pixelWidth(_ image: UIImage) -> Int {
        image.cgImage?.width ?? Int((image.size.width * image.scale).rounded())
    }

    static func pixelHeight(_ image: UIImage) -> Int {
        image.cgImage?.height ?? Int((image.size.height * image.scale).rounded())
    }

    /// True when height/width is in 1.30...1.55.
    static func hasHeroAspect(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        let aspect = Double(height) / Double(width)
        return (aspectMin...aspectMax).contains(aspect)
    }

    static func tier(width: Int, height: Int, verifiedFrontCrop: Bool) -> HeroCoverTier {
        guard hasHeroAspect(width: width, height: height) else { return .none }
        if width >= tierAWidth { return .a }
        if width >= tierBWidth { return .b }
        if width >= tierCWidth, verifiedFrontCrop { return .c }
        return .none
    }

    /// pics.dmm.co.jp `ps` (the 147×200 thumb) and any thumb URL may never be a sharp hero.
    static func isBannedAsSharpURL(_ source: String) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else { return trimmed.isEmpty }
        let path = url.path.lowercased()
        if path.contains("/small_covers/") { return true }
        if path.contains("/thumb/") || path.contains("/thumbs/") { return true }
        if host == "pics.dmm.co.jp", path.hasSuffix("ps.jpg") { return true }
        return false
    }

    static func isPicsDMMThumb(source: String, width: Int, height: Int) -> Bool {
        if width == 147 && height == 200 {
            return source.contains("pics.dmm.co.jp") || URL(string: source)?.host == "pics.dmm.co.jp"
        }
        return false
    }

    /// Higher tier wins; same tier compares pixel width; width difference ≤ 10% prefers native portrait `ps`.
    static func prefers(_ incoming: HeroCoverCandidate, to current: HeroCoverCandidate) -> Bool {
        if incoming.tier != current.tier { return incoming.tier > current.tier }
        let maxWidth = max(incoming.pixelWidth, current.pixelWidth)
        if maxWidth > 0 {
            let delta = Double(abs(incoming.pixelWidth - current.pixelWidth)) / Double(maxWidth)
            if delta <= sameTierWidthEpsilon, incoming.isNativePortraitPS != current.isNativePortraitPS {
                return incoming.isNativePortraitPS
            }
        }
        return incoming.pixelWidth > current.pixelWidth
    }
}

enum HeroCoverTier: Int, Comparable, Sendable {
    case none = 0
    case c = 1
    case b = 2
    case a = 3
    static func < (lhs: HeroCoverTier, rhs: HeroCoverTier) -> Bool { lhs.rawValue < rhs.rawValue }
    var isAB: Bool { self == .a || self == .b }
}

enum HeroCoverSourceKind: String, Sendable {
    case disk
    case dmmPS
    case dmmPL
    case amazon
    case tenhowAvbase
    case javdb
}

struct HeroCoverCandidate: @unchecked Sendable {
    let image: UIImage
    let pixelWidth: Int
    let pixelHeight: Int
    let source: String
    let kind: HeroCoverSourceKind
    let tier: HeroCoverTier
    let isNativePortraitPS: Bool
    let verifiedFrontCrop: Bool
}

/// Title-scoped accepted HQ in the shared HQPosterDiskCache, so the hero can
/// hit priority 1 after a detail-page write-back without knowing the URL.
enum HeroCoverDisk {
    static func key(number: String) -> String {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "hero-hq-326#\(trimmed)#\(HeroCoverPolicy.decodeCap)"
    }

    static func image(for number: String?) -> UIImage? {
        guard let number, !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return HQPosterDiskCache.image(forKey: key(number: number))
    }

    /// Write an already-accepted C+ portrait. Never stores thumbs or sub-C rasters.
    static func storeAccepted(_ image: UIImage, number: String?, source: String = "") {
        guard let number, !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let width = HeroCoverPolicy.pixelWidth(image)
        let height = HeroCoverPolicy.pixelHeight(image)
        let tier = HeroCoverPolicy.tier(width: width, height: height, verifiedFrontCrop: true)
        guard tier >= .c else { return }
        guard !HeroCoverPolicy.isBannedAsSharpURL(source) || source.isEmpty else { return }
        HQPosterDiskCache.store(image, forKey: key(number: number))
    }
}

/// Hero-only negative cache (own namespace). ≤ 60 s. Pull-to-refresh clears it.
/// This is not the list-cell 10-minute ListHQCoverCache.
enum HeroCoverNegativeCache {
    private static let lock = NSLock()
    private static var until: [String: TimeInterval] = [:]

    private static func key(_ number: String) -> String? {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }
        return "hero-hq-326#" + trimmed
    }

    static func isNegative(number: String?) -> Bool {
        guard let number, let key = key(number) else { return false }
        lock.lock(); defer { lock.unlock() }
        guard let deadline = until[key] else { return false }
        if ProcessInfo.processInfo.systemUptime >= deadline {
            until[key] = nil
            return false
        }
        return true
    }

    static func store(number: String?, ttl: TimeInterval = HeroCoverPolicy.negativeTTL) {
        guard let number, let key = key(number), ttl > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        until[key] = ProcessInfo.processInfo.systemUptime + ttl
    }

    static func clearAll() {
        lock.lock(); until.removeAll(); lock.unlock()
    }

    #if DEBUG
    static func resetForTests() { clearAll() }
    #endif
}

/// Quick-blur and (historical) sharp source lists for one title. Reuses DMM /
/// DetailPoster URL rules with hero-tier parameters; does not call VisibleHQPosterPolicy.
/// Build 330: `sharp` is no longer the authoritative sharp target. The official
/// iPhone detail-page winner from DetailPosterResolver is. The independent
/// queue is a resolver scheduler, not a hero-only DMM ps/pl race.
enum HeroCoverSources {
    struct Source: Sendable {
        let url: String
        let kind: HeroCoverSourceKind
        var isNativePortraitPS: Bool { kind == .dmmPS }
    }

    static func sharp(movie: Movie) -> [Source] {
        var result: [Source] = []
        var seen = Set<String>()
        func append(_ raw: String?, _ kind: HeroCoverSourceKind) {
            guard let raw else { return }
            let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, seen.insert(url).inserted else { return }
            guard !HeroCoverPolicy.isBannedAsSharpURL(url) else { return }
            result.append(Source(url: url, kind: kind))
        }

        let original = FrontPosterPolicy.usesOriginal(type: movie.type, number: movie.number)
        if !original {
            for url in DetailPosterPolicy.candidates(number: movie.number) {
                if url.hasSuffix("ps.jpg"), url.contains("awsimgsrc.dmm.co.jp") { append(url, .dmmPS) }
                else if url.hasSuffix("pl.jpg") { append(url, .dmmPL) }
            }
        }
        for image in movie.catalogueMetadata?.images ?? [] {
            for hq in DMMCoverURLs.upgrade(image) {
                if hq.hasSuffix("ps.jpg") { append(hq, .dmmPS) }
                else if hq.hasSuffix("pl.jpg") { append(hq, .dmmPL) }
            }
            guard let parsed = URL(string: image) else { continue }
            if AmazonPoster.allowedImage(parsed) {
                append(AmazonPoster.originalImage(parsed)?.absoluteString ?? image, .amazon)
            } else if TenhowPoster.allowedImage(parsed) || AvbaseMetadata.allowedDiscoveredImage(parsed) {
                append(image, .tenhowAvbase)
            }
        }
        if let learned = ListHQCoverCache.url(for: movie.number), let parsed = URL(string: learned) {
            if AmazonPoster.allowedImage(parsed) {
                append(AmazonPoster.originalImage(parsed)?.absoluteString ?? learned, .amazon)
            } else if TenhowPoster.allowedImage(parsed) || AvbaseMetadata.allowedDiscoveredImage(parsed) {
                append(learned, .tenhowAvbase)
            } else if learned.contains("awsimgsrc.dmm.co.jp") || learned.contains("pics.dmm.co.jp") {
                for hq in DMMCoverURLs.upgrade(learned) {
                    if hq.hasSuffix("ps.jpg") { append(hq, .dmmPS) }
                    else if hq.hasSuffix("pl.jpg") { append(hq, .dmmPL) }
                }
            }
        }
        if let cover = movie.coverURL, !cover.contains("/small_covers/") {
            append(cover, .javdb)
        }
        return result
    }

    /// Thumbs are allowed here: they paint unblurred as the hero floor.
    /// Quality tiers still refuse them as a finalized A/B sharp.
    static func blur(movie: Movie) -> [String] {
        ListCoverPolicy.sources(movie: movie)
    }
}

enum HeroCoverPhase: String, Equatable, Sendable {
    case empty
    case blur
    case provisional
    case finalized
}

struct HeroCoverPresentation: Equatable {
    var phase: HeroCoverPhase = .empty
    var blurImage: UIImage?
    /// Middle step of the Build 330 floor: enrich-merged detail `cover_url`
    /// (real cover, not `small_covers`).
    var enrichImage: UIImage?
    var sharpImage: UIImage?
    var tier: HeroCoverTier = .none
    var pixelWidth: Int = 0
    var ambient: HomeHSB?
    /// 已定案（可升级）：the 6s budget has provisionally settled. Late A/B may
    /// still replace the floor. Keyed with the rest of the presentation by movie id.
    var settled: Bool = false

    var isAB: Bool { phase == .finalized && tier.isAB }
    var hasQuick: Bool { blurImage != nil || enrichImage != nil || sharpImage != nil }

    var token: String {
        "\(phase.rawValue)#\(tier.rawValue)#\(pixelWidth)#\(blurImage != nil)#\(enrichImage != nil)#\(sharpImage != nil)#\(settled)"
    }

    static func == (lhs: HeroCoverPresentation, rhs: HeroCoverPresentation) -> Bool { lhs.token == rhs.token }
}

/// Optional CoverSR post-process seam. Build 326 does not run live SR:
/// acceptance is never gated on enhancement, Low Power keeps it off, and a
/// completed upscale (when wired later) may only be written to disk for the
/// *next* time the page is shown — never a hot-swap of the current page.
enum HeroCoverSRHook {
    /// Live SR is deferred in 326. Keep this false; do not flip it to gate paint.
    static let liveSREnabled = false

    static func scheduleIdleUpscaleIfNeeded(movie: Movie, image: UIImage, tier: HeroCoverTier) {
        // TODO(Build 326+): when idle, not Low Power, and AICoverSREngine.bundledModelURL()
        // is available, upscale a C-tier (or soft B) raster and write the result to
        // HeroCoverDisk / HQPosterDiskCache. Do not replace the in-memory current page.
        _ = (movie.id, image, tier, liveSREnabled, AICoverSREngine.bundledModelURL(),
             ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}

/// Official portrait from DetailPosterResolver is the primary sharp layer.
/// `hdBackdrop` / `pl` jackets must not be chosen over that winner, and the
/// home hero never uses the artwork backdrop or AICover-enhanced display raster.
enum HeroResolverSharp {
    static func primaryImage(from art: DetailPosterArtwork) -> UIImage {
        art.rawImage ?? art.image
    }

    static func isBackdropOrJacket(_ source: String) -> Bool {
        let lower = source.lowercased()
        if lower.contains("hdbackdrop") || lower.contains("hd_backdrop") { return true }
        if lower.hasSuffix("pl.jpg") { return true }
        return false
    }
}

/// Main-actor façade the hero carousel reads. Prefetch starts when the
/// recommend list returns. Memory keeps only the current + next decoded bitmaps.
@MainActor
final class HeroCoverStore: ObservableObject {
    static let shared = HeroCoverStore()

    @Published private(set) var presentations: [String: HeroCoverPresentation] = [:]

    private var movies: [Movie] = []
    private var currentIndex = 0
    private var generation = UUID()
    private var tasks: [String: Task<Void, Never>] = [:]
    private var lastAttempt: [String: TimeInterval] = [:]
    private var pathMonitor: NWPathMonitor?
    private var lastPathSatisfied = true
    private let gate = HeroCoverPrefetchGate()
    private var enrichFinished = false
    private var enrichedIDs: Set<String> = []
    private var settleStarted: Set<String> = []
    #if DEBUG
    static var testDetailProvider: ((Movie) async -> Movie?)?
    static var testResolverProvider: ((Movie) async -> DetailPosterArtwork?)?
    #endif

    func presentation(for id: String) -> HeroCoverPresentation {
        presentations[id] ?? HeroCoverPresentation()
    }

    func start(movies: [Movie], currentIndex: Int) {
        self.movies = movies
        self.currentIndex = min(max(currentIndex, 0), max(movies.count - 1, 0))
        generation = UUID()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        enrichFinished = false
        enrichedIDs.removeAll()
        settleStarted.removeAll()
        startNetworkWatchIfNeeded()
        // DTO floor + cached official winners paint immediately. The resolver
        // scheduler starts only after enrich has merged cover / actors / CID.
        enqueueFloorAndCachedSharp()
        Task { await self.enrichThenResolve() }
    }

    func setCurrentIndex(_ index: Int, movies: [Movie]? = nil) {
        if let movies { self.movies = movies }
        currentIndex = min(max(index, 0), max(self.movies.count - 1, 0))
        evictNonAdjacentBitmaps()
        // Current ±1: restore unblurred floor + sharp from in-memory floor cache,
        // HeroCoverDisk, and the DetailPosterResolver cache so a swipe back is never a smear.
        for movie in adjacentMovies() {
            restoreBitmaps(for: movie)
        }
        enqueueFloorAndCachedSharp()
        if enrichFinished { enqueueResolver() }
    }

    func clearNegatives() {
        HeroCoverNegativeCache.clearAll()
    }

    func clearNegativesAndRetry() {
        HeroCoverNegativeCache.clearAll()
        generation = UUID()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        settleStarted.removeAll()
        enqueueFloorAndCachedSharp()
        if enrichFinished {
            enqueueResolver(force: true)
        } else {
            Task { await self.enrichThenResolve() }
        }
    }

    func retryOnForeground() {
        let now = ProcessInfo.processInfo.systemUptime
        var needed = false
        for movie in movies {
            let state = presentations[movie.id]
            guard state?.isAB != true else { continue }
            let last = lastAttempt[movie.id] ?? 0
            if now - last > HeroCoverPolicy.foregroundRetryInterval { needed = true }
        }
        if needed, enrichFinished { enqueueResolver(force: true) }
    }

    func noteNetworkRecovered() {
        let needsUpgrade = movies.contains { presentations[$0.id]?.isAB != true }
        if needsUpgrade, enrichFinished { enqueueResolver(force: true) }
    }

    #if DEBUG
    func resetForTests() {
        generation = UUID()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        presentations.removeAll()
        lastAttempt.removeAll()
        floorCache.removeAll()
        movies = []
        currentIndex = 0
        enrichFinished = false
        enrichedIDs.removeAll()
        settleStarted.removeAll()
        Self.testDetailProvider = nil
        Self.testResolverProvider = nil
        HeroCoverNegativeCache.resetForTests()
    }
    #endif

    private var currentMovie: Movie? {
        guard !movies.isEmpty else { return nil }
        return movies[min(max(currentIndex, 0), movies.count - 1)]
    }

    /// Current ±1, no wrap. Large sharp bitmaps are kept only for this window.
    private func adjacentMovies() -> [Movie] {
        guard !movies.isEmpty else { return [] }
        let current = min(max(currentIndex, 0), movies.count - 1)
        var result: [Movie] = []
        for delta in [-1, 0, 1] {
            let i = current + delta
            if movies.indices.contains(i) { result.append(movies[i]) }
        }
        return result
    }

    /// Unblurred floor rasters are small and stay in memory for the cap-10 list
    /// so eviction never leaves a smear. Sharp (2048) stays only for current ±1.
    private var floorCache: [String: UIImage] = [:]

    private func evictNonAdjacentBitmaps() {
        let keep = Set(adjacentMovies().map(\.id))
        for (id, var presentation) in presentations where !keep.contains(id) {
            if presentation.sharpImage != nil {
                presentation.sharpImage = nil
                presentations[id] = presentation
            }
            // Keep blurImage / enrichImage; if already evicted, the floor cache can restore it.
            if presentation.blurImage == nil, let floor = floorCache[id] {
                presentation.blurImage = floor
                if presentation.phase == .empty { presentation.phase = .blur }
                presentations[id] = presentation
            }
        }
    }

    private func restoreBitmaps(for movie: Movie) {
        var current = presentations[movie.id] ?? HeroCoverPresentation()
        if current.blurImage == nil, let floor = floorCache[movie.id] {
            current.blurImage = floor
            if current.phase == .empty { current.phase = .blur }
            presentations[movie.id] = current
        }
        if current.sharpImage == nil {
            if let number = movie.number, let disk = HeroCoverDisk.image(for: number) {
                applyResolverImage(disk, source: "hero-disk", movie: movie)
                return
            }
            if let image = cachedResolverPortrait(for: movie) {
                applyResolverImage(image, source: "resolver-cache", movie: movie)
            }
        }
    }

    private func cachedResolverPortrait(for movie: Movie) -> UIImage? {
        let account = APIClient.shared.token
        if let art = DetailPosterResolver.initialLayout(movie: movie, account: account).artwork {
            return HeroResolverSharp.primaryImage(from: art)
        }
        return nil
    }

    /// Immediate DTO floor + HeroCoverDisk / resolver-cache sharp. Never waits on enrich.
    private func enqueueFloorAndCachedSharp() {
        for movie in movies {
            startSettleTimer(for: movie)
            restoreBitmaps(for: movie)
            startFloorLoad(movie)
        }
    }

    private func startFloorLoad(_ movie: Movie) {
        if presentations[movie.id]?.blurImage != nil || floorCache[movie.id] != nil { return }
        let id = movie.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            for source in HeroCoverSources.blur(movie: movie).prefix(3) {
                if Task.isCancelled { return }
                if source.hasPrefix("fixture://hang") || source.hasPrefix("fixture://delay") { continue }
                if let image = await ImageLoader.shared.load(source, maxPixelSize: 640, timeout: 4) {
                    self.applyBlur(image, movieID: id)
                    return
                }
            }
        }
    }

    private func applyBlur(_ image: UIImage, movieID: String) {
        var current = presentations[movieID] ?? HeroCoverPresentation()
        guard current.blurImage == nil else { return }
        floorCache[movieID] = image
        current.blurImage = image
        if current.phase == .empty { current.phase = .blur }
        if current.ambient == nil { current.ambient = HomeAmbientColor.base(from: image) }
        presentations[movieID] = current
    }

    private func startSettleTimer(for movie: Movie) {
        guard settleStarted.insert(movie.id).inserted else { return }
        let gen = generation
        let id = movie.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(HeroCoverPolicy.effectiveOverallBudget * 1_000_000_000))
            guard let self, self.generation == gen else { return }
            // 6s is a provisional floor-display rhythm point, not a cancel of
            // in-flight resolver winners. Late winners may still upgrade.
            // Provisional settle, not a cancel of in-flight work.
            self.markSettled(id: id, finalized: (self.presentations[id]?.tier ?? .none) >= .c)
        }
    }

    private func enrichThenResolve() async {
        await enrichHeroCIDs()
        // First official resolve must run even if the 6s rhythm point already
        // marked 已定案（可升级） during enrich.
        enqueueResolver(force: true)
    }

    /// Scheduler covers the cap-10 hero list in order: current → +1 → −1 → +2 → −2.
    /// Concurrency cap 2. Starts only after enrich has merged fields.
    private func enqueueResolver(force: Bool = false) {
        guard enrichFinished, !movies.isEmpty else { return }
        let gen = generation
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let current = min(max(currentIndex, 0), movies.count - 1)
        // Priority: current → +1 → −1 → +2 → −2, then the rest. No wrap.
        var order: [Int] = [current]
        for delta in [1, -1, 2, -2] {
            let i = current + delta
            if movies.indices.contains(i), !order.contains(i) { order.append(i) }
        }
        if !lowPower {
            for i in 0..<movies.count where !order.contains(i) { order.append(i) }
        }
        let adjacentIds = Set(adjacentMovies().map(\.id))
        for index in order {
            let movie = movies[index]
            if tasks[movie.id] != nil { continue }
            let state = presentations[movie.id]
            if !force, state?.phase == .finalized, state?.tier.isAB == true { continue }
            if !force, !shouldRetry(movie, state: state) { continue }
            let isCurrent = index == current
            let isAdjacent = adjacentIds.contains(movie.id)
            tasks[movie.id] = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.gate.acquire(lowPower: lowPower)
                defer { self.tasks[movie.id] = nil }
                guard !Task.isCancelled, self.generation == gen else {
                    await self.gate.release()
                    return
                }
                await self.resolveOfficial(movie, isCurrent: isCurrent, isAdjacent: isAdjacent, generation: gen)
                await self.gate.release()
            }
        }
    }

    private func shouldRetry(_ movie: Movie, state: HeroCoverPresentation?) -> Bool {
        if state == nil { return true }
        if state?.phase == .finalized, state?.tier.isAB == true { return false }
        // A settled (已定案（可升级）) item is not restarted automatically once a
        // resolver attempt has been made — in-flight work continues, and
        // foreground / network / pull retry with force: true. An item that has
        // not been attempted yet must still run after the 6s rhythm point.
        if state?.settled == true, lastAttempt[movie.id] != nil { return false }
        if HeroCoverNegativeCache.isNegative(number: movie.number) { return false }
        return true
    }

    private func resolveOfficial(_ movie: Movie, isCurrent: Bool, isAdjacent: Bool, generation: UUID) async {
        lastAttempt[movie.id] = ProcessInfo.processInfo.systemUptime
        let keepBitmaps = isCurrent || isAdjacent
        #if DEBUG
        if let url = movie.coverURL, url.hasPrefix("fixture://") {
            if url.hasPrefix("fixture://hang") { return }
            if url.hasPrefix("fixture://delay/") {
                let rest = String(url.dropFirst("fixture://delay/".count))
                let parts = rest.split(separator: "/", maxSplits: 1)
                let seconds = TimeInterval(parts.first.flatMap { Double($0) } ?? 15)
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                guard generation == self.generation, !Task.isCancelled else { return }
                let remainder = parts.count > 1 ? "fixture://" + String(parts[1]) : url
                let image = ImageLoader.fixturePoster(remainder)
                applyResolverImage(image, source: url, movie: movie, keepBitmaps: keepBitmaps)
                return
            }
            let image = HeroCoverFixture.portrait(url)
            if let candidate = HeroCoverClassifier.classify(image: image, source: url, kind: .javdb, verifiedFrontCrop: true) {
                applySharp(candidate, movie: movie, provisional: false, keepBitmaps: keepBitmaps)
                return
            }
            applyResolverImage(image, source: url, movie: movie, keepBitmaps: keepBitmaps)
            return
        }
        if let provider = Self.testResolverProvider {
            if let art = await provider(movie) {
                guard generation == self.generation, !Task.isCancelled else { return }
                applyArtwork(art, movie: movie, keepBitmaps: keepBitmaps)
            }
            return
        }
        #endif
        if let disk = HeroCoverDisk.image(for: movie.number) {
            applyResolverImage(disk, source: "hero-disk", movie: movie, keepBitmaps: keepBitmaps)
            if presentations[movie.id]?.tier.isAB == true { return }
        }
        if let cached = cachedResolverPortrait(for: movie) {
            applyResolverImage(cached, source: "resolver-cache", movie: movie, keepBitmaps: keepBitmaps)
            if presentations[movie.id]?.tier.isAB == true { return }
        }
        let art = await DetailPosterResolver.resolveShared(movie: movie, account: APIClient.shared.token)
        guard generation == self.generation, !Task.isCancelled else { return }
        if let art {
            applyArtwork(art, movie: movie, keepBitmaps: keepBitmaps)
        }
        evictNonAdjacentBitmaps()
    }

    private func applyArtwork(_ art: DetailPosterArtwork, movie: Movie, keepBitmaps: Bool) {
        // Official resolver winner (raw artwork). Do not run AICover on the home hero.
        // Do not use art.backdrop (hdBackdrop / pl jacket is not the 单人大图).
        let image = HeroResolverSharp.primaryImage(from: art)
        applyResolverImage(image, source: art.sourceURL, movie: movie, keepBitmaps: keepBitmaps)
        HeroCoverDisk.storeAccepted(image, number: movie.number, source: art.sourceURL)
    }

    private func applyResolverImage(_ image: UIImage, source: String, movie: Movie, keepBitmaps: Bool = true) {
        if let candidate = HeroCoverClassifier.classify(image: image, source: source.isEmpty ? "resolver" : source,
                                                        kind: .disk, verifiedFrontCrop: true) {
            applySharp(candidate, movie: movie, provisional: !candidate.tier.isAB, keepBitmaps: keepBitmaps)
            HeroCoverDisk.storeAccepted(candidate.image, number: movie.number, source: candidate.source)
            return
        }
        // The official portrait is still the sharp layer even if it is slightly
        // outside the historical 1.30...1.55 hero-aspect window.
        let width = HeroCoverPolicy.pixelWidth(image)
        let height = HeroCoverPolicy.pixelHeight(image)
        let tier: HeroCoverTier = width >= HeroCoverPolicy.tierAWidth ? .a
            : width >= HeroCoverPolicy.tierBWidth ? .b : .c
        let candidate = HeroCoverCandidate(image: image, pixelWidth: width, pixelHeight: height,
                                           source: source, kind: .disk, tier: tier,
                                           isNativePortraitPS: source.lowercased().contains("ps.jpg"),
                                           verifiedFrontCrop: true)
        applySharp(candidate, movie: movie, provisional: !tier.isAB, keepBitmaps: keepBitmaps)
        HeroCoverDisk.storeAccepted(image, number: movie.number, source: source)
    }

    private func apply(_ event: HeroCoverRace.Event, movie: Movie, keepBitmaps: Bool) {
        var current = presentations[movie.id] ?? HeroCoverPresentation()
        switch event {
        case .blur(let image):
            guard current.phase == .empty || current.blurImage == nil else { return }
            floorCache[movie.id] = image
            if keepBitmaps { current.blurImage = image }
            if current.phase == .empty { current.phase = .blur }
            if current.ambient == nil { current.ambient = HomeAmbientColor.base(from: image) }
            presentations[movie.id] = current
        case .provisional(let candidate):
            applySharp(candidate, movie: movie, provisional: true, keepBitmaps: keepBitmaps)
        case .settled:
            markSettled(id: movie.id, finalized: current.tier >= .c)
        }
    }

    private func applySharp(_ candidate: HeroCoverCandidate, movie: Movie, provisional: Bool, keepBitmaps: Bool = true) {
        var current = presentations[movie.id] ?? HeroCoverPresentation()
        if let existing = current.sharpImage,
           current.tier > candidate.tier { return }
        if current.tier == candidate.tier, current.pixelWidth >= candidate.pixelWidth, current.phase == .finalized {
            return
        }
        if keepBitmaps { current.sharpImage = candidate.image }
        current.tier = candidate.tier
        current.pixelWidth = candidate.pixelWidth
        current.phase = provisional ? .provisional : .finalized
        if !provisional, candidate.tier.isAB { current.settled = true }
        current.ambient = HomeAmbientColor.base(from: candidate.image) ?? current.ambient
        presentations[movie.id] = current
    }

    private func markSettled(_ movie: Movie, finalized: Bool) {
        markSettled(id: movie.id, finalized: finalized)
    }

    private func markSettled(id: String, finalized: Bool) {
        var current = presentations[id] ?? HeroCoverPresentation()
        current.settled = true
        if finalized, current.tier >= .c, current.phase != .finalized {
            current.phase = .finalized
        }
        presentations[id] = current
    }

    /// Merge cover / actors / CID into the hero movie *before* the resolver starts.
    /// Never blocks the first floor paint. CID-only is not enough.
    private func enrichHeroCIDs() async {
        let snapshot = movies
        for movie in snapshot {
            if Task.isCancelled { return }
            #if DEBUG
            if let provider = Self.testDetailProvider {
                if let detail = await provider(movie) {
                    applyMergedDetail(movie, detail)
                } else {
                    enrichedIDs.insert(movie.id)
                }
                continue
            }
            if movie.coverURL?.hasPrefix("fixture://") == true || movie.thumbURL?.hasPrefix("fixture://") == true {
                enrichedIDs.insert(movie.id)
                continue
            }
            #endif
            guard let detail = try? await JavDBSDK.shared.movieDetail(movie.id) else {
                enrichedIDs.insert(movie.id)
                continue
            }
            applyMergedDetail(movie, detail)
        }
        enrichFinished = true
    }

    private func applyMergedDetail(_ movie: Movie, _ detail: Movie) {
        HeroCIDMap.learn(from: detail)
        let merged = movie.mergingHeroDetail(detail)
        if let idx = movies.firstIndex(where: { $0.id == movie.id }) {
            movies[idx] = merged
        }
        enrichedIDs.insert(movie.id)
        if let cover = merged.coverURL, !cover.contains("/small_covers/") {
            let dtoCover = movie.coverURL ?? ""
            let dtoThumb = movie.thumbURL ?? ""
            let isNewCover = cover != dtoThumb && (cover != dtoCover || dtoCover.contains("/small_covers/") || dtoCover.isEmpty)
            if isNewCover || (cover != dtoThumb) {
                loadEnrichCover(cover, movieID: movie.id)
            }
        }
        if var state = presentations[movie.id], state.isAB != true {
            state.settled = false
            presentations[movie.id] = state
        }
    }

    private func loadEnrichCover(_ url: String, movieID: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if url.hasPrefix("fixture://hang") { return }
            if let image = await ImageLoader.shared.load(url, maxPixelSize: 1024, timeout: HeroCoverPolicy.upgradeTimeout) {
                var current = self.presentations[movieID] ?? HeroCoverPresentation()
                current.enrichImage = image
                if current.phase == .empty { current.phase = .blur }
                if current.ambient == nil { current.ambient = HomeAmbientColor.base(from: image) }
                self.presentations[movieID] = current
            }
        }
    }

    private func startNetworkWatchIfNeeded() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                if ok, !self.lastPathSatisfied {
                    NotificationCenter.default.post(name: .heroCoverNetworkRecovered, object: nil)
                    self.noteNetworkRecovered()
                }
                self.lastPathSatisfied = ok
            }
        }
        monitor.start(queue: DispatchQueue(label: "avdb.hero.cover.network"))
        pathMonitor = monitor
    }
}

actor HeroCoverPrefetchGate {
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire(lowPower: Bool) async {
        let limit = HeroCoverPolicy.prefetchLimit(lowPower: lowPower)
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    func release() {
        active = max(0, active - 1)
        guard !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        active += 1
        next.resume()
    }
}

enum HeroCoverClassifier {
    static func classify(image: UIImage, source: String, kind: HeroCoverSourceKind,
                         verifiedFrontCrop: Bool? = nil) -> HeroCoverCandidate? {
        let width = HeroCoverPolicy.pixelWidth(image)
        let height = HeroCoverPolicy.pixelHeight(image)
        if HeroCoverPolicy.isBannedAsSharpURL(source) { return nil }
        if HeroCoverPolicy.isPicsDMMThumb(source: source, width: width, height: height) { return nil }
        let verified = verifiedFrontCrop ?? (kind != .javdb || height >= width)
        let tier = HeroCoverPolicy.tier(width: width, height: height, verifiedFrontCrop: verified)
        guard tier >= .c else { return nil }
        return HeroCoverCandidate(image: image, pixelWidth: width, pixelHeight: height,
                                  source: source, kind: kind, tier: tier,
                                  isNativePortraitPS: kind == .dmmPS || kind == .disk && source.contains("ps.jpg"),
                                  verifiedFrontCrop: verified)
    }
}

enum HeroCoverRace {
    enum Event {
        case blur(UIImage)
        case provisional(HeroCoverCandidate)
        case settled
    }

    enum Outcome {
        case finalized(HeroCoverCandidate)
        case provisionalFinal(HeroCoverCandidate)
        case blurOnly
    }

    static func run(movie: Movie, keepBitmaps: Bool = true,
                    onEvent: @escaping @MainActor (Event) -> Void) async -> Outcome {
        _ = keepBitmaps
        let sources = HeroCoverSources.sharp(movie: movie)
        let blurSources = HeroCoverSources.blur(movie: movie)
        return await withTaskGroup(of: RaceMessage.self) { group in
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(HeroCoverPolicy.effectiveOverallBudget * 1_000_000_000))
                return Task.isCancelled ? .miss : .budget
            }
            // Quick floor in parallel with the HQ race; thumbs paint unblurred.
            group.addTask {
                if let image = await loadBlur(blurSources) { return .blur(image) }
                return .miss
            }
            for source in sources {
                group.addTask {
                    // Do not cap the load by the 6s settle; late A/B may still land.
                    guard !Task.isCancelled else { return .miss }
                    if let candidate = await loadSharp(source, timeout: HeroCoverPolicy.upgradeTimeout) {
                        return .sharp(candidate)
                    }
                    return .miss
                }
            }

            var best: HeroCoverCandidate?
            var graceStarted = false
            var graceExpired = false
            var didSettle = false

            func maybeEvent(_ event: Event) {
                Task { @MainActor in onEvent(event) }
            }

            func settleIfNeeded() {
                guard !didSettle else { return }
                didSettle = true
                maybeEvent(.settled)
            }

            while let message = await group.next() {
                if Task.isCancelled { break }
                switch message {
                case .budget:
                    // Provisional settle, not a cancel of in-flight work.
                    settleIfNeeded()
                case .grace:
                    graceExpired = true
                case .blur(let image):
                    maybeEvent(.blur(image))
                case .sharp(let candidate):
                    if best == nil || HeroCoverPolicy.prefers(candidate, to: best!) {
                        best = candidate
                        maybeEvent(.provisional(candidate))
                    }
                    if candidate.tier == .a, graceStarted {
                        group.cancelAll()
                        return .finalized(best ?? candidate)
                    }
                    if !graceStarted, (best?.tier ?? .none) >= .c {
                        // First ≥ C-tier starts a 400ms grace window; other requests stay in flight.
                        graceStarted = true
                        group.addTask {
                            try? await Task.sleep(nanoseconds: UInt64(HeroCoverPolicy.graceWindow * 1_000_000_000))
                            return Task.isCancelled ? .miss : .grace
                        }
                    }
                case .miss:
                    break
                }

                if let best, best.tier == .a, graceExpired {
                    group.cancelAll()
                    return .finalized(best)
                }
                // Grace expiry with only C/B settles provisionally but must NOT
                // cancel a still-in-flight A (e.g. a CDN that answers at 15s).
                if graceExpired { settleIfNeeded() }
            }
            group.cancelAll()
            if let best, best.tier.isAB { return .finalized(best) }
            if let best, best.tier >= .c { return .provisionalFinal(best) }
            return .blurOnly
        }
    }

    private enum RaceMessage: @unchecked Sendable {
        case sharp(HeroCoverCandidate)
        case blur(UIImage)
        case budget
        case grace
        case miss
    }

    private static func loadBlur(_ sources: [String]) async -> UIImage? {
        for source in sources.prefix(3) {
            if Task.isCancelled { return nil }
            if source.hasPrefix("fixture://hang") || source.hasPrefix("fixture://delay") { continue }
            if let image = await ImageLoader.shared.load(source, maxPixelSize: 640, timeout: 4) {
                return image
            }
        }
        return nil
    }

    private static func loadSharp(_ source: HeroCoverSources.Source, timeout: TimeInterval) async -> HeroCoverCandidate? {
        guard timeout > 0, !Task.isCancelled else { return nil }
        let loaded = await ImageLoader.shared.load(source.url, maxPixelSize: HeroCoverPolicy.decodeCap, timeout: timeout)
        guard let loaded, !Task.isCancelled, let cg = loaded.cgImage else { return nil }
        if let host = URL(string: source.url)?.host, ["pics.dmm.co.jp", "awsimgsrc.dmm.co.jp"].contains(host) {
            let kind = DMMImageValidation.classify(width: cg.width, height: cg.height, bytes: 0, source: source.url)
            if kind == .placeholder || kind == .tooSmall { return nil }
        }
        var image = loaded
        var verified = source.kind != .javdb
        let shouldCrop = source.kind == .dmmPL
            || source.kind == .javdb
            || source.kind == .tenhowAvbase
            || FrontPosterPolicy.isKnownWrap(source.url)
            || DMMCoverURLs.isJacket(source.url)
        if shouldCrop,
           let rect = FrontPosterPolicy.cropRect(width: cg.width, height: cg.height, source: source.url,
                                                 validatedJacket: source.kind == .javdb && cg.width > cg.height),
           let front = cg.cropping(to: rect) {
            image = UIImage(cgImage: front)
            verified = true
        } else if cg.width > cg.height {
            // Landscape that we could not crop is never a sharp hero.
            return nil
        } else {
            verified = verified || source.kind == .dmmPS || source.kind == .amazon || source.kind == .tenhowAvbase
        }
        return HeroCoverClassifier.classify(image: image, source: source.url, kind: source.kind, verifiedFrontCrop: verified)
    }
}


/// DMM content-id lookup for the hero race. Reads the playback DTO and the
/// persistent number→CID mapping cache; a miss is filled by a detail fetch.
enum HeroCIDMap {
    static func cid(from movie: Movie) -> String? {
        if let number = movie.number, let cached = DMMLabelPrefixes.shared.cid(for: number) {
            return cached
        }
        var urls: [String] = []
        if let cover = movie.coverURL { urls.append(cover) }
        if let thumb = movie.thumbURL { urls.append(thumb) }
        urls.append(contentsOf: movie.catalogueMetadata?.images ?? [])
        for url in urls {
            if let cid = DMMCoverURLs.cid(url) { return cid }
        }
        return nil
    }

    @discardableResult
    static func learn(from movie: Movie) -> Bool {
        guard let number = movie.number, !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard let cid = cid(from: movie) else { return false }
        return DMMLabelPrefixes.shared.learn(cid: cid, number: number)
    }
}

#if DEBUG
enum HeroCoverFixture {
    /// Neutral 700×1000 (scale 1) B-tier portrait, no network.
    static func portrait(_ url: String) -> UIImage {
        let size = CGSize(width: 700, height: 1000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let digit = Double(Int(String(url.last ?? "1")) ?? 1)
        let top = UIColor(hue: CGFloat((0.04 + digit * 0.09).truncatingRemainder(dividingBy: 1)),
                          saturation: 0.55, brightness: 0.62, alpha: 1)
        let bottom = UIColor(red: 0.10, green: 0.08, blue: 0.07, alpha: 1)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            UIColor(white: 1, alpha: 0.16).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 170, y: 150, width: 360, height: 360))
            ("NEUTRAL " + (url.components(separatedBy: "/").last ?? "")).draw(
                at: CGPoint(x: 60, y: 560),
                withAttributes: [.font: UIFont.systemFont(ofSize: 48, weight: .bold), .foregroundColor: UIColor.white])
        }
    }
}
#endif
