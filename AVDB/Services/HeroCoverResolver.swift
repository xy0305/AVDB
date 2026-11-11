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
    /// Build 331: per-item enrich deadline (detail + optional catalogue lookup).
    static let enrichTimeout: TimeInterval = 8
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

    /// Build 331: winner-URL key. A swipe back to an evicted item restores
    /// exactly the finalized winner from disk — no resolver rerun, no network.
    static func key(winnerURL: String, number: String?) -> String {
        let title = (number ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "hero-winner-331#\(title)#\(winnerURL.trimmingCharacters(in: .whitespacesAndNewlines))#\(HeroCoverPolicy.decodeCap)"
    }

    private static let pendingLock = NSLock()
    /// Writes still in flight on the utility queue. Part of the disk layer so a
    /// restore that races the JPEG write still reads the winner (never the network).
    private static var pending: [String: UIImage] = [:]

    static func image(for number: String?) -> UIImage? {
        guard let number, !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return HQPosterDiskCache.image(forKey: key(number: number))
    }

    static func image(winnerURL: String?, number: String?) -> UIImage? {
        guard let winnerURL, !winnerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let key = key(winnerURL: winnerURL, number: number)
        pendingLock.lock()
        let inFlight = pending[key]
        pendingLock.unlock()
        if let inFlight { return inFlight }
        return HQPosterDiskCache.image(forKey: key)
    }

    /// Write an already-accepted C+ portrait. Never stores thumbs or sub-C rasters.
    @discardableResult
    static func storeAccepted(_ image: UIImage, number: String?, source: String = "") -> Bool {
        guard let number, !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let width = HeroCoverPolicy.pixelWidth(image)
        let height = HeroCoverPolicy.pixelHeight(image)
        let tier = HeroCoverPolicy.tier(width: width, height: height, verifiedFrontCrop: true)
        guard tier >= .c else { return false }
        guard !HeroCoverPolicy.isBannedAsSharpURL(source) || source.isEmpty else { return false }
        HQPosterDiskCache.store(image, forKey: key(number: number))
        return true
    }

    private static func finishPending(key: String, image: UIImage) {
        pendingLock.lock()
        if pending[key] === image { pending[key] = nil }
        pendingLock.unlock()
    }

    /// Build 331: persist the official resolver winner under its URL. Encoding
    /// and the LRU trim run off the main actor; returns whether it is retrievable.
    @discardableResult
    static func storeWinner(_ image: UIImage, winnerURL: String, number: String?) -> Bool {
        let url = winnerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !HeroCoverPolicy.isBannedAsSharpURL(url), image.cgImage != nil else { return false }
        let key = key(winnerURL: url, number: number)
        pendingLock.lock()
        pending[key] = image
        pendingLock.unlock()
        Task.detached(priority: .utility) {
            HQPosterDiskCache.store(image, forKey: key)
            HeroCoverDisk.finishPending(key: key, image: image)
        }
        return true
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
    /// Build 331 two-level floor (field name kept from 326): the sharpest image
    /// available in the movie's current record, painted sharp — front-cropped
    /// cover_url preferred, DTO thumb fallback. Always produced by
    /// `ImageLoader.loadPoster` (FrontPosterPolicy crop-or-passthrough), so it
    /// is never an uncropped DVD jacket. Re-evaluated when enrich merges a better cover.
    var blurImage: UIImage?
    var floorSource: String?
    var floorPixelWidth: Int = 0
    /// Official DetailPosterResolver winner (the iPhone detail portraitHero).
    /// Overrides the floor on arrival. nil when evicted outside current ±1.
    var sharpImage: UIImage?
    /// Winner URL of the sharp layer; with `sharpOnDisk` it restores from
    /// HeroCoverDisk after eviction without a resolver rerun or any network.
    var winnerURL: String?
    var sharpOnDisk: Bool = false
    var tier: HeroCoverTier = .none
    var pixelWidth: Int = 0
    /// Ambient wash colour, always sampled from the currently displayed
    /// (cropped) bitmap — never from a separate full-jacket fetch.
    var ambient: HomeHSB?
    /// 已定案（可升级）：the 6s budget has provisionally settled. Late A/B may
    /// still replace the floor. Keyed with the rest of the presentation by movie id.
    var settled: Bool = false

    /// Sharp state requires the bitmap to be retrievable (memory or HeroCoverDisk).
    var hasSharpBitmap: Bool { sharpImage != nil || sharpOnDisk }
    var isAB: Bool { phase == .finalized && tier.isAB && hasSharpBitmap }
    var isSharp: Bool { phase == .finalized && winnerURL != nil && hasSharpBitmap }
    var hasQuick: Bool { blurImage != nil || sharpImage != nil }
    /// Top-most painted bitmap (sharp over floor).
    var displayedImage: UIImage? { sharpImage ?? blurImage }

    var token: String {
        "\(phase.rawValue)#\(tier.rawValue)#\(pixelWidth)#\(blurImage != nil)#\(floorPixelWidth)#\(sharpImage != nil)#\(winnerURL ?? "")#\(settled)"
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

/// Main-actor façade the hero carousel reads. Build 331: per-item pipeline
/// enrich → DetailPosterResolver (current → +1 → −1 → +2 → −2, cap 2), a
/// two-level floor (front-cropped cover_url / thumb, then the official winner),
/// keep/evict decided at result-arrival time, and disk-only restores.
@MainActor
final class HeroCoverStore: ObservableObject {
    static let shared = HeroCoverStore()

    @Published private(set) var presentations: [String: HeroCoverPresentation] = [:]

    private var movies: [Movie] = []
    private var currentIndex = 0
    private var generation = UUID()
    /// Resolver tasks by movie id (token-guarded so a stale task never clears a newer one).
    private var tasks: [String: Task<Void, Never>] = [:]
    private var taskTokens: [String: UUID] = [:]
    /// Per-item enrich → resolver pipelines by movie id.
    private var pipelines: [String: Task<Void, Never>] = [:]
    private var lastAttempt: [String: TimeInterval] = [:]
    private var pathMonitor: NWPathMonitor?
    private var lastPathSatisfied = true
    private let gate = HeroCoverPrefetchGate()
    private let enrichGate = HeroCoverPrefetchGate()
    private enum EnrichState { case running, merged, failed, skipped }
    private var enrichState: [String: EnrichState] = [:]
    /// Items whose enrich timed out / failed get exactly one retry when they become current.
    private var enrichRetried: Set<String> = []
    /// Enrich-merged records by movie id. A raw ranking DTO never overwrites them.
    private var enriched: [String: Movie] = [:]
    private var settleStarted: Set<String> = []
    /// Floor rasters are small and stay in memory for the cap-10 list
    /// so eviction never leaves a smear. Sharp (2048) stays only for current ±1.
    private var floorCache: [String: UIImage] = [:]
    private var floorInFlight: Set<String> = []
    private var floorLoaded: Set<String> = []
    private var floorFailedAt: [String: TimeInterval] = [:]
    private var restoring: Set<String> = []
    private var diskProbed: Set<String> = []
    private var winnerObserver: NSObjectProtocol?
    #if DEBUG
    static var testDetailProvider: ((Movie) async -> Movie?)?
    static var testResolverProvider: ((Movie) async -> DetailPosterArtwork?)?
    /// Resolver runs (tests assert a disk restore is not a rerun).
    static var resolverRunCount = 0
    /// Hosted unit tests own the shared store: the host app's HomeView stops
    /// driving it (start / setCurrentIndex) once a test has reset it.
    static var suspendAppCallsForTests = false
    static var appCallsSuspended: Bool { suspendAppCallsForTests }
    #else
    static var appCallsSuspended: Bool { false }
    #endif

    init() {
        winnerObserver = NotificationCenter.default.addObserver(
            forName: .detailPosterWinnerResolved, object: nil, queue: .main
        ) { [weak self] note in
            let id = note.userInfo?["movieID"] as? String
            Task { @MainActor [weak self] in self?.noteDetailWinner(movieID: id) }
        }
    }

    func presentation(for id: String) -> HeroCoverPresentation {
        presentations[id] ?? HeroCoverPresentation()
    }

    func start(movies incoming: [Movie], currentIndex: Int) {
        movies = mergeRanking(incoming)
        self.currentIndex = min(max(currentIndex, 0), max(movies.count - 1, 0))
        generation = UUID()
        cancelWork()
        enrichState.removeAll()
        enrichRetried.removeAll()
        settleStarted.removeAll()
        diskProbed.removeAll()
        startNetworkWatchIfNeeded()
        // Floor + cached official winners paint immediately; never waits on enrich.
        enqueueFloorAndCachedSharp()
        schedulePipelines()
    }

    func setCurrentIndex(_ index: Int, movies incoming: [Movie]? = nil) {
        // Field-level merge by movie id: rank / title follow the latest ranking,
        // enriched cover / actors / type / CID are never overwritten by the DTO.
        if let incoming { movies = mergeRanking(incoming) }
        currentIndex = min(max(index, 0), max(movies.count - 1, 0))
        evictNonAdjacentBitmaps()
        enqueueFloorAndCachedSharp()
        if let current = currentMovie, enrichState[current.id] == .failed, !enrichRetried.contains(current.id) {
            enrichRetried.insert(current.id)
            enrichState[current.id] = nil
        }
        schedulePipelines()
        enqueueResolvers()
    }

    func clearNegatives() {
        HeroCoverNegativeCache.clearAll()
    }

    func clearNegativesAndRetry() {
        HeroCoverNegativeCache.clearAll()
        generation = UUID()
        cancelWork()
        settleStarted.removeAll()
        floorFailedAt.removeAll()
        for (id, state) in enrichState where state == .failed { enrichState[id] = nil }
        enqueueFloorAndCachedSharp()
        schedulePipelines()
        enqueueResolvers(force: true)
    }

    func retryOnForeground() {
        let now = ProcessInfo.processInfo.systemUptime
        var needed = false
        for movie in movies {
            guard presentations[movie.id]?.isAB != true else { continue }
            let last = lastAttempt[movie.id] ?? 0
            if now - last > HeroCoverPolicy.foregroundRetryInterval { needed = true }
        }
        if needed { enqueueResolvers(force: true) }
    }

    func noteNetworkRecovered() {
        floorFailedAt.removeAll()
        enqueueFloorAndCachedSharp()
        let needsUpgrade = movies.contains { presentations[$0.id]?.isAB != true }
        if needsUpgrade { enqueueResolvers(force: true) }
    }

    #if DEBUG
    func resetForTests() {
        generation = UUID()
        cancelWork()
        presentations.removeAll()
        lastAttempt.removeAll()
        floorCache.removeAll()
        floorInFlight.removeAll()
        floorLoaded.removeAll()
        floorFailedAt.removeAll()
        restoring.removeAll()
        diskProbed.removeAll()
        enriched.removeAll()
        movies = []
        currentIndex = 0
        enrichState.removeAll()
        enrichRetried.removeAll()
        settleStarted.removeAll()
        Self.testDetailProvider = nil
        Self.testResolverProvider = nil
        Self.resolverRunCount = 0
        Self.suspendAppCallsForTests = true
        HeroCoverNegativeCache.resetForTests()
        DetailPosterWinners.resetForTests()
    }
    #endif

    private func cancelWork() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        taskTokens.removeAll()
        for task in pipelines.values { task.cancel() }
        pipelines.removeAll()
        for (id, state) in enrichState where state == .running { enrichState[id] = nil }
    }

    private var currentMovie: Movie? {
        guard !movies.isEmpty else { return nil }
        return movies[min(max(currentIndex, 0), movies.count - 1)]
    }

    private func movie(id: String) -> Movie? {
        movies.first { $0.id == id }
    }

    private func mergeRanking(_ incoming: [Movie]) -> [Movie] {
        incoming.map { dto in
            if let merged = enriched[dto.id] { return dto.preservingHeroEnrichment(from: merged) }
            return dto
        }
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

    /// Evaluated when a result *arrives*, never frozen at enqueue time.
    private func isInWindow(_ id: String) -> Bool {
        adjacentMovies().contains { $0.id == id }
    }

    /// Priority: current → +1 → −1 → +2 → −2 → … covering the full cap-10 list. No wrap.
    /// The current page is always highest priority (gates re-rank waiters on every swipe).
    private func priorityOrder() -> [Int] {
        guard !movies.isEmpty else { return [] }
        let current = min(max(currentIndex, 0), movies.count - 1)
        var order: [Int] = [current]
        var step = 1
        while order.count < movies.count, step < movies.count {
            for i in [current + step, current - step] where movies.indices.contains(i) && !order.contains(i) {
                order.append(i)
            }
            step += 1
        }
        return order
    }

    private func updateGatePriority() {
        let ids = priorityOrder().map { movies[$0].id }
        let gate = self.gate
        let enrichGate = self.enrichGate
        Task {
            await gate.setPriority(ids)
            await enrichGate.setPriority(ids)
        }
    }

    private func evictNonAdjacentBitmaps() {
        let keep = Set(adjacentMovies().map(\.id))
        for (id, var presentation) in presentations where !keep.contains(id) {
            var changed = false
            if presentation.sharpImage != nil {
                presentation.sharpImage = nil
                changed = true
                if !presentation.sharpOnDisk {
                    // Nothing retrievable any more: never pose as a finalized sharp.
                    presentation.winnerURL = nil
                    presentation.tier = .none
                    presentation.pixelWidth = 0
                    presentation.phase = presentation.blurImage != nil ? .blur : .empty
                    lastAttempt[id] = nil
                }
            }
            // Keep the floor; if it was dropped, the floor cache restores it.
            if presentation.blurImage == nil, let floor = floorCache[id] {
                presentation.blurImage = floor
                if presentation.phase == .empty { presentation.phase = .blur }
                changed = true
            }
            if changed {
                presentation.ambient = presentation.displayedImage.flatMap(HomeAmbientColor.base(from:)) ?? presentation.ambient
                presentations[id] = presentation
            }
        }
    }

    /// Current ±1 only. Order: by-id winner in memory (detail page or hero,
    /// absolute priority) → evicted winner from HeroCoverDisk by winner URL →
    /// cold-start HeroCoverDisk by number. Disk reads run off the main actor.
    /// A restore never reruns the resolver and never touches the network.
    private func restoreBitmaps(for movie: Movie) {
        let id = movie.id
        var current = presentations[id] ?? HeroCoverPresentation()
        if current.blurImage == nil, let floor = floorCache[id] {
            current.blurImage = floor
            if current.phase == .empty { current.phase = .blur }
            if current.sharpImage == nil { current.ambient = HomeAmbientColor.base(from: floor) ?? current.ambient }
            presentations[id] = current
        }
        guard current.sharpImage == nil, isInWindow(id) else { return }
        if let art = DetailPosterWinners.winner(movieID: id, account: APIClient.shared.token) {
            applyArtwork(art, movie: movie, authoritative: true)
            if presentations[id]?.sharpImage != nil { return }
        }
        guard !restoring.contains(id) else { return }
        let winnerURL = current.sharpOnDisk ? current.winnerURL : nil
        if winnerURL == nil {
            guard !diskProbed.contains(id) else { return }
            diskProbed.insert(id)
        }
        restoring.insert(id)
        let number = movie.number
        Task { @MainActor [weak self] in
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                if let winnerURL, let exact = HeroCoverDisk.image(winnerURL: winnerURL, number: number) { return exact }
                return HeroCoverDisk.image(for: number)
            }.value
            self?.finishRestore(id: id, image: image, winnerURL: winnerURL)
        }
    }

    private func finishRestore(id: String, image: UIImage?, winnerURL: String?) {
        restoring.remove(id)
        guard let movie = movie(id: id) else { return }
        if let winnerURL {
            var current = presentations[id] ?? HeroCoverPresentation()
            guard current.winnerURL == winnerURL, current.sharpImage == nil else { return }
            if let image {
                guard isInWindow(id) else { return }
                current.sharpImage = image
                current.ambient = HomeAmbientColor.base(from: image) ?? current.ambient
                presentations[id] = current
            } else {
                // Disk purged under storage pressure: no longer sharp, so it may
                // not pose as final. Only now is a fresh resolve allowed.
                current.sharpOnDisk = false
                current.winnerURL = nil
                current.tier = .none
                current.pixelWidth = 0
                current.phase = current.blurImage != nil ? .blur : .empty
                presentations[id] = current
                lastAttempt[id] = nil
                enqueueResolver(for: movie, force: true)
            }
            return
        }
        if let image {
            applyResolverImage(image, source: Self.diskStandIn, movie: movie)
        }
    }

    private static let diskStandIn = "hero-disk"

    /// Immediate floor + cached winners for the window. Never waits on enrich.
    private func enqueueFloorAndCachedSharp() {
        for movie in movies {
            startSettleTimer(for: movie)
            startFloorLoad(movie)
        }
        for movie in adjacentMovies() {
            restoreBitmaps(for: movie)
        }
    }

    // MARK: Floor (level 1)

    /// Front-cropped cover_url first, the DTO thumb as fallback. Hanging /
    /// delayed CDN stand-ins never block the floor.
    private func floorSources(_ movie: Movie) -> [String] {
        var out: [String] = []
        func add(_ raw: String?) {
            guard let raw else { return }
            let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, !out.contains(url) else { return }
            if url.hasPrefix("fixture://hang") || url.hasPrefix("fixture://delay") { return }
            out.append(url)
        }
        if let cover = movie.coverURL, !cover.contains("/small_covers/") { add(cover) }
        add(movie.thumbURL)
        add(movie.coverURL)
        return out
    }

    private static func isCoverSource(_ source: String, movie: Movie) -> Bool {
        guard let cover = movie.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return source == cover && !cover.contains("/small_covers/")
    }

    private func startFloorLoad(_ movie: Movie) {
        let id = movie.id
        let now = ProcessInfo.processInfo.systemUptime
        let current = presentations[id]
        let floorIsCover = current?.floorSource.map { Self.isCoverSource($0, movie: movie) } ?? false
        let todo = floorSources(movie).filter { source in
            let key = id + "#" + source
            if floorLoaded.contains(key) || floorInFlight.contains(key) { return false }
            if let failed = floorFailedAt[key], now - failed < 30 { return false }
            // A cropped cover already on screen beats the 166 px thumb.
            if floorIsCover, !Self.isCoverSource(source, movie: movie) { return false }
            return true
        }
        guard !todo.isEmpty else { return }
        for source in todo { floorInFlight.insert(id + "#" + source) }
        // Parallel race only for current ±1: first arrival paints, a later
        // sharper one replaces it. Elsewhere: cover first, thumb on failure.
        let parallel = isInWindow(id)
        let sizes = todo.map { Self.isCoverSource($0, movie: movie) ? 1024 : 640 }
        Task { @MainActor [weak self] in
            if parallel {
                await withTaskGroup(of: (String, UIImage?).self) { group in
                    for (source, size) in zip(todo, sizes) {
                        group.addTask {
                            let image = await ImageLoader.shared.loadPoster(source, maxPixelSize: size, timeout: 6)
                            return (source, image)
                        }
                    }
                    for await (source, image) in group {
                        await self?.finishFloor(image, source: source, movieID: id)
                    }
                }
            } else {
                var done = false
                for (source, size) in zip(todo, sizes) {
                    if done {
                        self?.floorInFlight.remove(id + "#" + source)
                        continue
                    }
                    let image = await ImageLoader.shared.loadPoster(source, maxPixelSize: size, timeout: 6)
                    self?.finishFloor(image, source: source, movieID: id)
                    done = image != nil
                }
            }
        }
    }

    private func finishFloor(_ image: UIImage?, source: String, movieID: String) {
        let key = movieID + "#" + source
        floorInFlight.remove(key)
        guard let image else {
            floorFailedAt[key] = ProcessInfo.processInfo.systemUptime
            return
        }
        floorLoaded.insert(key)
        applyFloor(image, source: source, movieID: movieID)
    }

    /// Portrait (front) beats landscape; then the wider raster wins.
    nonisolated static func floorRank(_ image: UIImage) -> Int {
        let width = HeroCoverPolicy.pixelWidth(image)
        let height = HeroCoverPolicy.pixelHeight(image)
        return (height >= width ? 1_000_000 : 0) + width
    }

    private func applyFloor(_ image: UIImage, source: String, movieID: String) {
        var current = presentations[movieID] ?? HeroCoverPresentation()
        if let existing = current.blurImage, Self.floorRank(existing) >= Self.floorRank(image) { return }
        floorCache[movieID] = image
        current.blurImage = image
        current.floorSource = source
        current.floorPixelWidth = HeroCoverPolicy.pixelWidth(image)
        if current.phase == .empty { current.phase = .blur }
        if current.sharpImage == nil { current.ambient = HomeAmbientColor.base(from: image) ?? current.ambient }
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

    // MARK: Per-item pipeline enrich → resolver

    /// Merge cover / actors / CID per item and start that item's resolver as
    /// soon as its own enrich finishes (no batch waterfall). Order current →
    /// +1 → −1 → +2 → −2 over the full cap-10 list, concurrency cap 2, 8s per item.
    private func schedulePipelines() {
        updateGatePriority()
        let gen = generation
        for index in priorityOrder() {
            let movie = movies[index]
            let id = movie.id
            if enrichState[id] != nil || pipelines[id] != nil { continue }
            enrichState[id] = .running
            pipelines[id] = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.enrichGate.acquire(id: id, lowPower: false)
                guard !Task.isCancelled, self.generation == gen else {
                    await self.enrichGate.release()
                    return
                }
                let outcome = await self.fetchEnrich(self.movie(id: id) ?? movie)
                await self.enrichGate.release()
                guard !Task.isCancelled, self.generation == gen else { return }
                self.pipelines[id] = nil
                switch outcome {
                case .merged(let detail):
                    self.applyMergedDetail(id: id, detail)
                    self.enrichState[id] = .merged
                case .failed:
                    self.enrichState[id] = .failed
                case .skipped:
                    self.enrichState[id] = .skipped
                }
                if let latest = self.movie(id: id) {
                    self.enqueueResolver(for: latest, force: true)
                }
            }
        }
    }

    private enum EnrichOutcome: @unchecked Sendable {
        case merged(Movie)
        case failed
        case skipped
    }

    private struct Boxed<T>: @unchecked Sendable { let value: T? }

    /// Per-item deadline. The 6s rhythm point never cancels this; only the 8s
    /// per-item budget does.
    nonisolated private static func withTimeout<T>(_ seconds: TimeInterval,
                                                   _ operation: @escaping @Sendable () async -> T?) async -> Boxed<T> {
        await withTaskGroup(of: Boxed<T>.self) { group -> Boxed<T> in
            group.addTask { Boxed(value: await operation()) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                return Boxed(value: nil)
            }
            let first = await group.next() ?? Boxed(value: nil)
            group.cancelAll()
            return first
        }
    }

    private func fetchEnrich(_ movie: Movie) async -> EnrichOutcome {
        #if DEBUG
        if let provider = Self.testDetailProvider {
            let detail: Movie? = await Self.withTimeout(HeroCoverPolicy.enrichTimeout) { () async -> Movie? in
                await provider(movie)
            }.value
            return detail.map { EnrichOutcome.merged($0) } ?? EnrichOutcome.failed
        }
        if movie.coverURL?.hasPrefix("fixture://") == true || movie.thumbURL?.hasPrefix("fixture://") == true {
            return .skipped
        }
        #endif
        let detail: Movie? = await Self.withTimeout(HeroCoverPolicy.enrichTimeout) { () async -> Movie? in
            // Login token, exactly as the detail page requires.
            guard let native = try? await JavDBSDK.shared.movieDetail(movie.id, catalogue: false) else { return nil }
            // Verified for 331: the v4 detail response has no CID field (its
            // cover / thumb / preview images live on the JavDB CDN). Skip the
            // redundant avbase catalogue lookup whenever a DMM CID is already
            // known for the record; otherwise keep it inside the 8s budget.
            if HeroCIDMap.cid(from: native) != nil { return native }
            return (try? await JavDBSDK.shared.catalogueEnriched(native)) ?? native
        }.value
        return detail.map { EnrichOutcome.merged($0) } ?? EnrichOutcome.failed
    }

    private func applyMergedDetail(id: String, _ detail: Movie) {
        HeroCIDMap.learn(from: detail)
        guard let idx = movies.firstIndex(where: { $0.id == id }) else { return }
        let merged = movies[idx].mergingHeroDetail(detail)
        movies[idx] = merged
        enriched[id] = merged
        // The floor re-evaluates automatically when enrich merges a better cover.
        startFloorLoad(merged)
        if var state = presentations[id], state.isAB != true {
            state.settled = false
            presentations[id] = state
        }
    }

    // MARK: Resolver (level 2)

    private func enqueueResolvers(force: Bool = false) {
        for index in priorityOrder() {
            enqueueResolver(for: movies[index], force: force)
        }
    }

    private func enqueueResolver(for movie: Movie, force: Bool) {
        let id = movie.id
        guard tasks[id] == nil else { return }
        // Each item's resolver starts only after its own enrich is terminal.
        guard let enrich = enrichState[id], enrich != .running else { return }
        let state = presentations[id]
        if state?.isAB == true { return }
        if !force, !shouldRetry(movie, state: state) { return }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if lowPower {
            let window = Set(priorityOrder().prefix(5).map { movies[$0].id })
            guard window.contains(id) else { return }
        }
        updateGatePriority()
        let gen = generation
        let token = UUID()
        taskTokens[id] = token
        tasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.gate.acquire(id: id, lowPower: lowPower)
            defer {
                if self.taskTokens[id] == token {
                    self.tasks[id] = nil
                    self.taskTokens[id] = nil
                }
            }
            guard !Task.isCancelled, self.generation == gen else {
                await self.gate.release()
                return
            }
            // The resolver receives the merged record as of *now*.
            await self.resolveOfficial(self.movie(id: id) ?? movie, generation: gen)
            await self.gate.release()
        }
    }

    private func shouldRetry(_ movie: Movie, state: HeroCoverPresentation?) -> Bool {
        if state == nil { return true }
        if state?.isAB == true { return false }
        // A settled (已定案（可升级）) item is not restarted automatically once a
        // resolver attempt has been made — in-flight work continues, and
        // foreground / network / pull retry with force: true. An item that has
        // not been attempted yet must still run after the 6s rhythm point.
        if state?.settled == true, lastAttempt[movie.id] != nil { return false }
        if HeroCoverNegativeCache.isNegative(number: movie.number) { return false }
        return true
    }

    private func resolveOfficial(_ movie: Movie, generation: UUID) async {
        lastAttempt[movie.id] = ProcessInfo.processInfo.systemUptime
        #if DEBUG
        Self.resolverRunCount += 1
        if movie.coverURL?.hasPrefix("fixture://hang") == true || movie.thumbURL?.hasPrefix("fixture://hang") == true {
            return
        }
        // Injected test resolvers take precedence over instant fixture covers
        // (an enrich-merged fixture cover_url is a floor candidate, not a sharp stand-in).
        if let provider = Self.testResolverProvider {
            if let art = await provider(movie) {
                guard generation == self.generation, !Task.isCancelled else { return }
                applyArtwork(art, movie: movie, authoritative: true)
            }
            return
        }
        if let url = movie.coverURL, url.hasPrefix("fixture://") {
            if url.hasPrefix("fixture://delay/") {
                let rest = String(url.dropFirst("fixture://delay/".count))
                let parts = rest.split(separator: "/", maxSplits: 1)
                let seconds = TimeInterval(parts.first.flatMap { Double($0) } ?? 15)
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                guard generation == self.generation, !Task.isCancelled else { return }
                let remainder = parts.count > 1 ? "fixture://" + String(parts[1]) : url
                let image = ImageLoader.fixturePoster(remainder)
                applyResolverImage(image, source: url, movie: movie)
                return
            }
            let image = HeroCoverFixture.portrait(url)
            if let candidate = HeroCoverClassifier.classify(image: image, source: url, kind: .javdb, verifiedFrontCrop: true) {
                applySharp(candidate, movie: movie, provisional: false)
                return
            }
            applyResolverImage(image, source: url, movie: movie)
            return
        }
        #endif
        let account = APIClient.shared.token
        if let shared = DetailPosterWinners.winner(movieID: movie.id, account: account) {
            applyArtwork(shared, movie: movie, authoritative: true)
            return
        }
        let number = movie.number
        let disk = await Task.detached(priority: .userInitiated) { HeroCoverDisk.image(for: number) }.value
        guard generation == self.generation, !Task.isCancelled else { return }
        if let disk {
            applyResolverImage(disk, source: Self.diskStandIn, movie: movie)
            if presentations[movie.id]?.isAB == true { return }
        }
        if let cached = cachedResolverPortrait(for: movie, account: account) {
            applyArtwork(cached, movie: movie, authoritative: true)
            if presentations[movie.id]?.isAB == true { return }
        }
        let art = await DetailPosterResolver.resolveShared(movie: movie, account: account)
        guard generation == self.generation, !Task.isCancelled else { return }
        if let art {
            applyArtwork(art, movie: movie, authoritative: true)
        }
        evictNonAdjacentBitmaps()
    }

    /// DetailPosterResolver memory (identity cache, then the by-id winner share).
    private func cachedResolverPortrait(for movie: Movie, account: String?) -> DetailPosterArtwork? {
        DetailPosterResolver.initialLayout(movie: movie, account: account).artwork
    }

    /// Detail page (or another hero resolve) landed a winner for this movie id:
    /// upgrade immediately, even before the next swipe.
    private func noteDetailWinner(movieID: String?) {
        guard let movieID, let movie = movie(id: movieID),
              let art = DetailPosterWinners.winner(movieID: movieID, account: APIClient.shared.token) else { return }
        applyArtwork(art, movie: movie, authoritative: true)
    }

    private func applyArtwork(_ art: DetailPosterArtwork, movie: Movie, authoritative: Bool = false) {
        // Official resolver winner (raw artwork). Do not run AICover on the home hero.
        // Do not use art.backdrop (hdBackdrop / pl jacket is not the 单人大图).
        let image = HeroResolverSharp.primaryImage(from: art)
        let source = art.sourceURL.isEmpty ? "resolver#" + movie.id : art.sourceURL
        applyResolverImage(image, source: source, movie: movie, authoritative: authoritative)
    }

    private func applyResolverImage(_ image: UIImage, source: String, movie: Movie, authoritative: Bool = false) {
        if let candidate = HeroCoverClassifier.classify(image: image, source: source.isEmpty ? "resolver" : source,
                                                        kind: .disk, verifiedFrontCrop: true) {
            applySharp(candidate, movie: movie, provisional: !candidate.tier.isAB, authoritative: authoritative)
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
        applySharp(candidate, movie: movie, provisional: !tier.isAB, authoritative: authoritative)
    }

    /// Keep/evict is decided by distance from the current index when the
    /// result arrives. A sharp state is recorded only when the bitmap is
    /// retrievable (kept in memory, or written to HeroCoverDisk by winner URL);
    /// the metadata guards never assume a bitmap that is missing.
    private func applySharp(_ candidate: HeroCoverCandidate, movie: Movie, provisional: Bool, authoritative: Bool = false) {
        let id = movie.id
        var current = presentations[id] ?? HeroCoverPresentation()
        let keep = isInWindow(id)
        let bitmapPresent = current.sharpImage != nil
        let retrievable = bitmapPresent || (!keep && current.sharpOnDisk)
        if retrievable, current.winnerURL == candidate.source { return }
        if retrievable, !authoritative {
            if current.tier > candidate.tier { return }
            if current.tier == candidate.tier, current.pixelWidth >= candidate.pixelWidth, current.phase == .finalized {
                return
            }
        }
        let onDisk: Bool
        if candidate.source == Self.diskStandIn {
            onDisk = true  // already in HeroCoverDisk under the title key
        } else if current.winnerURL == candidate.source, current.sharpOnDisk {
            onDisk = true
        } else {
            onDisk = HeroCoverDisk.storeWinner(candidate.image, winnerURL: candidate.source, number: movie.number)
        }
        guard keep || onDisk else { return }
        current.sharpImage = keep ? candidate.image : nil
        current.winnerURL = candidate.source
        current.sharpOnDisk = onDisk
        current.tier = candidate.tier
        current.pixelWidth = candidate.pixelWidth
        current.phase = provisional ? .provisional : .finalized
        if !provisional, candidate.tier.isAB { current.settled = true }
        current.ambient = HomeAmbientColor.base(from: candidate.image) ?? current.ambient
        presentations[id] = current
    }

    private func markSettled(id: String, finalized: Bool) {
        var current = presentations[id] ?? HeroCoverPresentation()
        current.settled = true
        if finalized, current.tier >= .c, current.hasSharpBitmap, current.phase != .finalized {
            current.phase = .finalized
        }
        presentations[id] = current
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

/// Priority gate (cap 2): a released slot goes to the waiter closest to the
/// current page (current → +1 → −1 → +2 → −2), FIFO among equals.
actor HeroCoverPrefetchGate {
    private var active = 0
    private var waiters: [(id: String, continuation: CheckedContinuation<Void, Never>)] = []
    private var priority: [String: Int] = [:]

    func setPriority(_ order: [String]) {
        priority = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func acquire(id: String = "", lowPower: Bool) async {
        let limit = HeroCoverPolicy.prefetchLimit(lowPower: lowPower)
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append((id, continuation))
        }
    }

    func release() {
        active = max(0, active - 1)
        guard !waiters.isEmpty else { return }
        let index = waiters.indices.min { lhs, rhs in
            (priority[waiters[lhs].id] ?? Int.max) < (priority[waiters[rhs].id] ?? Int.max)
        } ?? 0
        let next = waiters.remove(at: index)
        active += 1
        next.continuation.resume()
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
