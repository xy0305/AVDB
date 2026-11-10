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
    static let overallBudget: TimeInterval = 6
    static let graceWindow: TimeInterval = 0.4
    static let crossfadeDuration: TimeInterval = 0.45
    static let prefetchConcurrency = 3
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
        lowPower ? lowPowerPrefetchConcurrency : prefetchConcurrency
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

/// Quick-blur and sharp source lists for one title. Reuses DMM / DetailPoster
/// URL rules with hero-tier parameters; does not call VisibleHQPosterPolicy.
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

    /// Thumbs are allowed here: they are only ever painted as a full-bleed blur.
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
    var sharpImage: UIImage?
    var tier: HeroCoverTier = .none
    var pixelWidth: Int = 0
    var ambient: HomeHSB?
    var retryable: Bool = false
    var finished: Bool = false

    var isAB: Bool { phase == .finalized && tier.isAB }
    var hasQuick: Bool { blurImage != nil || sharpImage != nil }

    var token: String {
        "\(phase.rawValue)#\(tier.rawValue)#\(pixelWidth)#\(blurImage != nil)#\(sharpImage != nil)#\(retryable)#\(finished)"
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

    func presentation(for id: String) -> HeroCoverPresentation {
        presentations[id] ?? HeroCoverPresentation()
    }

    func start(movies: [Movie], currentIndex: Int) {
        self.movies = movies
        self.currentIndex = min(max(currentIndex, 0), max(movies.count - 1, 0))
        generation = UUID()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        startNetworkWatchIfNeeded()
        enqueuePrefetch()
    }

    func setCurrentIndex(_ index: Int, movies: [Movie]? = nil) {
        if let movies { self.movies = movies }
        currentIndex = min(max(index, 0), max(self.movies.count - 1, 0))
        evictNonAdjacentBitmaps()
        // Current page is always highest priority; fault in from disk if evicted.
        if let movie = currentMovie, presentations[movie.id]?.sharpImage == nil,
           let number = movie.number, let disk = HeroCoverDisk.image(for: number),
           let candidate = HeroCoverClassifier.classify(image: disk, source: "hero-disk", kind: .disk) {
            applySharp(candidate, movie: movie, provisional: false)
        }
        enqueuePrefetch()
    }

    func clearNegatives() {
        HeroCoverNegativeCache.clearAll()
    }

    func clearNegativesAndRetry() {
        HeroCoverNegativeCache.clearAll()
        generation = UUID()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        enqueuePrefetch(force: true)
    }

    func retryOnForeground() {
        let now = ProcessInfo.processInfo.systemUptime
        var needed = false
        for movie in movies {
            let state = presentations[movie.id]
            guard state?.retryable == true || state?.isAB == false else { continue }
            let last = lastAttempt[movie.id] ?? 0
            if now - last > HeroCoverPolicy.foregroundRetryInterval { needed = true }
        }
        if needed { enqueuePrefetch(force: true) }
    }

    func noteNetworkRecovered() {
        let hasRetryable = movies.contains { presentations[$0.id]?.retryable == true }
        if hasRetryable { enqueuePrefetch(force: true) }
    }

    #if DEBUG
    func resetForTests() {
        generation = UUID()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        presentations.removeAll()
        lastAttempt.removeAll()
        movies = []
        currentIndex = 0
        HeroCoverNegativeCache.resetForTests()
    }
    #endif

    private var currentMovie: Movie? {
        guard !movies.isEmpty else { return nil }
        return movies[min(max(currentIndex, 0), movies.count - 1)]
    }

    private var nextMovie: Movie? {
        guard movies.count > 1 else { return nil }
        return movies[(min(max(currentIndex, 0), movies.count - 1) + 1) % movies.count]
    }

    private func evictNonAdjacentBitmaps() {
        let keep = Set([currentMovie?.id, nextMovie?.id].compactMap { $0 })
        for (id, var presentation) in presentations where !keep.contains(id) {
            if presentation.blurImage != nil || presentation.sharpImage != nil {
                presentation.blurImage = nil
                presentation.sharpImage = nil
                presentations[id] = presentation
            }
        }
    }

    private func enqueuePrefetch(force: Bool = false) {
        guard !movies.isEmpty else { return }
        let gen = generation
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let current = min(max(currentIndex, 0), movies.count - 1)
        // Priority: current > next 2 pages > rest. Low Power defers non-adjacent pages.
        var order: [Int] = [current]
        if movies.count > 1 { order.append((current + 1) % movies.count) }
        if movies.count > 2 { order.append((current + 2) % movies.count) }
        if !lowPower {
            for i in 0..<movies.count where !order.contains(i) { order.append(i) }
        }
        let adjacent = Set(order.prefix(min(3, movies.count)))
        for index in order {
            let movie = movies[index]
            if tasks[movie.id] != nil { continue }
            let state = presentations[movie.id]
            if !force, state?.phase == .finalized, state?.tier.isAB == true { continue }
            if !force, !shouldRetry(movie, state: state) { continue }
            let isCurrent = index == current
            let isAdjacent = adjacent.contains(index)
            tasks[movie.id] = Task { @MainActor [weak self] in
                guard let self else { return }
                if !isCurrent {
                    await self.gate.acquire(lowPower: lowPower)
                }
                defer { self.tasks[movie.id] = nil }
                guard !Task.isCancelled, self.generation == gen else {
                    if !isCurrent { await self.gate.release() }
                    return
                }
                await self.resolve(movie, isCurrent: isCurrent, isAdjacent: isAdjacent, generation: gen)
                if !isCurrent { await self.gate.release() }
            }
        }
    }

    private func shouldRetry(_ movie: Movie, state: HeroCoverPresentation?) -> Bool {
        if state == nil { return true }
        if state?.phase == .finalized, state?.tier.isAB == true { return false }
        if HeroCoverNegativeCache.isNegative(number: movie.number), state?.retryable == true { return false }
        if state?.retryable == true { return true }
        if state?.phase == .finalized, state?.tier == .c { return true } // may still upgrade later if forced
        if state?.finished != true { return true }
        return state?.hasQuick != true
    }

    private func resolve(_ movie: Movie, isCurrent: Bool, isAdjacent: Bool, generation: UUID) async {
        lastAttempt[movie.id] = ProcessInfo.processInfo.systemUptime
        #if DEBUG
        if let url = movie.coverURL, url.hasPrefix("fixture://") {
            let image = HeroCoverFixture.portrait(url)
            if let candidate = HeroCoverClassifier.classify(image: image, source: url, kind: .javdb, verifiedFrontCrop: true) {
                applySharp(candidate, movie: movie, provisional: false)
                return
            }
        }
        #endif
        // Priority 1: previously accepted HQ for this title (detail write-back included).
        if let disk = HeroCoverDisk.image(for: movie.number),
           let candidate = HeroCoverClassifier.classify(image: disk, source: "hero-disk", kind: .disk, verifiedFrontCrop: true) {
            if candidate.tier.isAB {
                applySharp(candidate, movie: movie, provisional: false)
                return
            }
            if candidate.tier == .c {
                applySharp(candidate, movie: movie, provisional: true)
            }
        }

        let keepBitmaps = isCurrent || isAdjacent
        let result = await HeroCoverRace.run(movie: movie, keepBitmaps: keepBitmaps) { [weak self] event in
            guard let self, self.generation == generation else { return }
            self.apply(event, movie: movie, keepBitmaps: keepBitmaps)
        }
        guard generation == self.generation, !Task.isCancelled else { return }
        switch result {
        case .finalized(let candidate), .provisionalFinal(let candidate):
            applySharp(candidate, movie: movie, provisional: false, keepBitmaps: keepBitmaps)
            HeroCoverDisk.storeAccepted(candidate.image, number: movie.number, source: candidate.source)
            HeroCoverSRHook.scheduleIdleUpscaleIfNeeded(movie: movie, image: candidate.image, tier: candidate.tier)
        case .blurOnly:
            // A disk C-tier (or other provisional sharp) must not be discarded if the
            // remaining sources miss — finalize whatever ≥ C is already on screen.
            if let existing = presentations[movie.id], existing.tier >= .c {
                var kept = existing
                kept.phase = .finalized
                kept.finished = true
                kept.retryable = false
                presentations[movie.id] = kept
            } else {
                markRetryable(movie, keepExistingSharp: false)
            }
        }
        evictNonAdjacentBitmaps()
    }

    private func apply(_ event: HeroCoverRace.Event, movie: Movie, keepBitmaps: Bool) {
        var current = presentations[movie.id] ?? HeroCoverPresentation()
        switch event {
        case .blur(let image):
            guard current.phase == .empty || current.blurImage == nil else { return }
            if keepBitmaps { current.blurImage = image }
            if current.phase == .empty { current.phase = .blur }
            if current.ambient == nil { current.ambient = HomeAmbientColor.base(from: image) }
            presentations[movie.id] = current
        case .provisional(let candidate):
            applySharp(candidate, movie: movie, provisional: true, keepBitmaps: keepBitmaps)
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
        current.retryable = false
        current.finished = !provisional
        current.ambient = HomeAmbientColor.base(from: candidate.image) ?? current.ambient
        presentations[movie.id] = current
    }

    private func markRetryable(_ movie: Movie, keepExistingSharp: Bool) {
        var current = presentations[movie.id] ?? HeroCoverPresentation()
        if !keepExistingSharp, current.tier < .c {
            current.phase = current.blurImage == nil ? .empty : .blur
            current.sharpImage = nil
            current.tier = .none
            current.pixelWidth = 0
        }
        current.retryable = true
        current.finished = true
        presentations[movie.id] = current
        HeroCoverNegativeCache.store(number: movie.number)
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
        let deadline = ProcessInfo.processInfo.systemUptime + HeroCoverPolicy.overallBudget
        return await withTaskGroup(of: RaceMessage.self) { group in
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(HeroCoverPolicy.overallBudget * 1_000_000_000))
                return Task.isCancelled ? .miss : .budget
            }
            // Quick blur in parallel with the HQ race; thumbs are OK because they stay blurred.
            group.addTask {
                if let image = await loadBlur(blurSources) { return .blur(image) }
                return .miss
            }
            for source in sources {
                group.addTask {
                    let remaining = deadline - ProcessInfo.processInfo.systemUptime
                    guard remaining > 0, !Task.isCancelled else { return .miss }
                    let timeout = min(HeroCoverPolicy.sourceTimeout, remaining)
                    if let candidate = await loadSharp(source, timeout: timeout) { return .sharp(candidate) }
                    return .miss
                }
            }

            var best: HeroCoverCandidate?
            var graceStarted = false
            var graceExpired = false
            var budgetExpired = false

            func maybeEvent(_ event: Event) {
                Task { @MainActor in onEvent(event) }
            }

            while let message = await group.next() {
                if Task.isCancelled { break }
                switch message {
                case .budget:
                    budgetExpired = true
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
                if graceExpired, let best, best.tier >= .c {
                    group.cancelAll()
                    return .provisionalFinal(best)
                }
                if budgetExpired {
                    group.cancelAll()
                    if let best, best.tier >= .c { return .provisionalFinal(best) }
                    return .blurOnly
                }
            }
            group.cancelAll()
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
