import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Build 290: AI-enhanced covers live in the cloud (Cloudflare R2 behind the `avdb-covers` Worker), not long-term on the
/// phone. Foundation-only so the Linux/macOS unit tests (mock transport + mock HTTP server) and the CI e2e against the
/// real Worker compile exactly this file.
///
/// Contract (see r2cover README): `GET|HEAD|PUT /v1/cover/{prefix}/{NAME}.{jpg|webp|heic}`, header `X-AVDB-Key`.
/// PUT ≤ 3 MiB, `image/jpeg|webp|heic`; 404 missing; 401 bad key; 413 too large; 507 bucket near quota.
/// Keys are immutable (edge-cached 1 year) → the prefix carries the model version; bump it when the model changes.
enum AICoverCloudConfig {
    static let primary = URL(string: "https://covers.xy0305.kdns.fr")!
    static let fallback = URL(string: "https://avdb-covers.yxu83821.workers.dev")!
    /// One prefix per (model, params). 4xNomosWebPhoto esrgan x4, tile 128, fp16, v1 → `nomos1`.
    static let prefix = "nomos1"
    static let maxUploadBytes = 3 * 1024 * 1024
    static let fetchTimeout: TimeInterval = 2.5          // HEAD (hit/miss decision) budget
    static let downloadTimeout: TimeInterval = 15        // GET body budget after a confirmed hit
    static let infoPlistKey = "AVDBCoversKey"
    /// The app key is injected at build time (GitHub Actions secret → Info.plist `$(AVDB_COVERS_KEY)`); never in git.
    static func appKey(bundle: Bundle = .main) -> String? {
        if let env = ProcessInfo.processInfo.environment["AVDB_COVERS_KEY_OVERRIDE"], !env.isEmpty { return env }
        guard let k = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String else { return nil }
        let t = k.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.hasPrefix("$(") ? nil : t
    }
    /// Base URLs in order; a launch argument / env override exists for the simulator host and tests.
    static func bases() -> [URL] {
        if let o = ProcessInfo.processInfo.environment["AVDB_COVERS_BASE"], let u = URL(string: o) { return [u] }
        return [primary, fallback]
    }
}

/// Object names: `{番号}_{W}x{H}` of the native low-res input (different sources of the same title differ in size and
/// therefore in result), or `h{sha-prefix}` when there is no 番号. Segment rule: `^[A-Za-z0-9._-]{1,80}$`.
enum AICoverCloudName {
    static func sanitize(_ s: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        var out = String(s.uppercased().map { allowed.contains($0) ? $0 : "-" })
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return String(out.prefix(60))
    }
    static func make(number: String?, width: Int, height: Int, fallbackHash: String) -> String {
        let n = sanitize(number ?? "")
        let size = "\(max(0, width))x\(max(0, height))"
        if !n.isEmpty { return "\(n)_\(size)" }
        return "h" + String(fallbackHash.lowercased().filter { $0.isHexDigit }.prefix(40)) + "_" + size
    }
    static func path(_ name: String, ext: String, prefix: String = AICoverCloudConfig.prefix) -> String {
        "/v1/cover/\(prefix)/\(name).\(ext)"
    }
    static func valid(_ segment: String) -> Bool {
        guard (1...80).contains(segment.count), segment != ".", segment != ".." else { return false }
        return segment.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }
}

/// HTTP seam: production uses URLSession; unit tests inject a scripted transport.
protocol AICoverCloudTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct AICoverURLSessionTransport: AICoverCloudTransport {
    let session: URLSession
    /// One long-lived ephemeral session (no URLCache → nothing persisted on disk by the HTTP layer).
    static let sharedSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 30
        #if !canImport(FoundationNetworking)
        c.waitsForConnectivity = false
        #endif
        c.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: c)
    }()
    init(session: URLSession? = nil) { self.session = session ?? Self.sharedSession }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        #if canImport(FoundationNetworking)
        return try await withCheckedThrowingContinuation { cont in
            session.dataTask(with: request) { d, r, e in
                if let e { cont.resume(throwing: e); return }
                guard let h = r as? HTTPURLResponse else { cont.resume(throwing: URLError(.badServerResponse)); return }
                cont.resume(returning: (d ?? Data(), h))
            }.resume()
        }
        #else
        let (d, r) = try await session.data(for: request)
        guard let h = r as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (d, h)
        #endif
    }
}

enum AICoverFetchResult: Equatable, Sendable {
    case hit(Data, contentType: String)
    case miss                                  // 404 on the cloud → enhance locally
    case unavailable(String)                   // offline / timeout / 401 / 5xx / no key → enhance locally, silently
}

enum AICoverUploadResult: Equatable, Sendable {
    case ok
    case quotaFull                             // 507 → stop uploading for this session (note in settings)
    case rejected(Int)                         // 400 / 401 / 413 / 415 → not retryable
    case retryable(String)                     // offline / timeout / 5xx / 429
}

struct AICoverCloudClient: Sendable {
    let bases: [URL]
    let key: String?
    let transport: AICoverCloudTransport
    var fetchTimeout: TimeInterval = AICoverCloudConfig.fetchTimeout
    var prefix: String = AICoverCloudConfig.prefix
    var downloadTimeout: TimeInterval = AICoverCloudConfig.downloadTimeout

    init(bases: [URL] = AICoverCloudConfig.bases(), key: String? = AICoverCloudConfig.appKey(),
         transport: AICoverCloudTransport = AICoverURLSessionTransport(), fetchTimeout: TimeInterval = AICoverCloudConfig.fetchTimeout,
         prefix: String = AICoverCloudConfig.prefix) {
        self.bases = bases; self.key = key; self.transport = transport; self.fetchTimeout = fetchTimeout; self.prefix = prefix
    }

    var configured: Bool { key != nil && !bases.isEmpty }

    private func request(_ base: URL, _ path: String, method: String, timeout: TimeInterval) -> URLRequest? {
        guard let key, let url = URL(string: path, relativeTo: base)?.absoluteURL else { return nil }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        r.httpMethod = method
        r.setValue(key, forHTTPHeaderField: "X-AVDB-Key")
        r.setValue("AVDB-iOS/290", forHTTPHeaderField: "User-Agent")
        return r
    }

    /// Lookup: `HEAD` with the short budget (2.5 s total across primary → fallback; fallback only on transport / 5xx errors,
    /// never on a 404) decides hit/miss; only a confirmed hit is then downloaded with `GET`, under a longer body budget
    /// (`downloadTimeout`), so a slow link doesn't throw away an existing cloud copy halfway through a ~0.5–1 MB body.
    /// One object per name, always under `.jpg`; the body may be JPEG or HEIC (the Worker returns the uploaded type).
    func fetch(name: String) async -> AICoverFetchResult {
        guard configured else { return .unavailable("未配置云端密钥") }
        let deadline = Date().addingTimeInterval(fetchTimeout)
        var lastError = "offline"
        for base in bases {
            let left = deadline.timeIntervalSinceNow
            guard left > 0.05 else { return .unavailable("timeout") }
            let path = AICoverCloudName.path(name, ext: "jpg", prefix: prefix)
            guard let head = request(base, path, method: "HEAD", timeout: left) else { return .unavailable("bad url") }
            do {
                let (_, resp) = try await withTimeout(left) { try await transport.send(head) }
                switch resp.statusCode {
                case 200:
                    guard let get = request(base, path, method: "GET", timeout: downloadTimeout) else { return .unavailable("bad url") }
                    do {
                        let (data, r2) = try await withTimeout(downloadTimeout) { try await transport.send(get) }
                        guard r2.statusCode == 200, !data.isEmpty else { return .unavailable("GET HTTP \(r2.statusCode)") }
                        return .hit(data, contentType: r2.value(forHTTPHeaderField: "Content-Type") ?? "image/jpeg")
                    } catch { return .unavailable("GET " + Self.describe(error)) }
                case 404: return .miss
                case 401, 403: return .unavailable("HTTP \(resp.statusCode)")
                default: lastError = "HTTP \(resp.statusCode)"          // 5xx → try the fallback base
                }
            } catch { lastError = Self.describe(error) }
        }
        return .unavailable(lastError)
    }

    func upload(name: String, data: Data, contentType: String) async -> AICoverUploadResult {
        guard configured else { return .rejected(401) }
        guard !data.isEmpty, data.count <= AICoverCloudConfig.maxUploadBytes else { return .rejected(413) }
        var last: AICoverUploadResult = .retryable("offline")
        for base in bases {
            guard var req = request(base, AICoverCloudName.path(name, ext: "jpg", prefix: prefix), method: "PUT", timeout: 60) else { return .rejected(400) }
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            req.httpBody = data
            do {
                let (_, resp) = try await transport.send(req)
                switch resp.statusCode {
                case 200, 201, 204: return .ok
                case 507: return .quotaFull
                case 400, 401, 403, 413, 415: return .rejected(resp.statusCode)
                default: return .retryable("HTTP \(resp.statusCode)")      // server reached; retry later with backoff
                }
            } catch { last = .retryable(Self.describe(error)) }       // transport error → try the fallback base
        }
        return last
    }

    static func describe(_ error: Error) -> String {
        if error is AICoverTimeout { return "timeout" }
        if let u = error as? URLError { return "URLError \(u.code.rawValue)" }
        return String(describing: error).prefix(80).description
    }
}

struct AICoverTimeout: Error {}
func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { g in
        g.addTask { try await op() }
        g.addTask { try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1e9)); throw AICoverTimeout() }
        defer { g.cancelAll() }
        guard let first = try await g.next() else { throw AICoverTimeout() }
        return first
    }
}

/// User settings + counters (UserDefaults; injectable for tests).
final class AICoverCloudSettings: @unchecked Sendable {
    static let shared = AICoverCloudSettings()
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    static let enabledKey = "ai.cover.cloud.enabled"
    static let capKey = "ai.cover.cloud.cacheCapMB"
    static let wifiOnlyKey = "ai.cover.cloud.wifiOnly"
    static let capChoicesMB = [50, 100, 200, 500, 1000]
    static let defaultCapMB = 200

    var enabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }
    var capMB: Int {
        get { let v = defaults.integer(forKey: Self.capKey); return v > 0 ? v : Self.defaultCapMB }
        set { defaults.set(newValue, forKey: Self.capKey) }
    }
    var capBytes: Int { capMB * 1024 * 1024 }
    var wifiOnly: Bool {
        get { defaults.bool(forKey: Self.wifiOnlyKey) }
        set { defaults.set(newValue, forKey: Self.wifiOnlyKey) }
    }
    // Counters
    private func bump(_ k: String, _ n: Int = 1) { defaults.set(defaults.integer(forKey: k) + n, forKey: k) }
    func countHit() { bump("ai.cover.cloud.hits") }
    func countMiss() { bump("ai.cover.cloud.misses") }
    func countUpload(bytes: Int) { bump("ai.cover.cloud.uploads"); bump("ai.cover.cloud.uploadBytes", bytes) }
    func countFailure(_ why: String) { bump("ai.cover.cloud.failures"); defaults.set(why, forKey: "ai.cover.cloud.lastError") }
    var hits: Int { defaults.integer(forKey: "ai.cover.cloud.hits") }
    var misses: Int { defaults.integer(forKey: "ai.cover.cloud.misses") }
    var uploads: Int { defaults.integer(forKey: "ai.cover.cloud.uploads") }
    var uploadBytes: Int { defaults.integer(forKey: "ai.cover.cloud.uploadBytes") }
    var failures: Int { defaults.integer(forKey: "ai.cover.cloud.failures") }
    var lastError: String? { defaults.string(forKey: "ai.cover.cloud.lastError") }
    /// 507: uploads stop until this date (re-probed after a day; the bucket guard is recomputed hourly).
    var quotaFullUntil: Date? {
        get { defaults.object(forKey: "ai.cover.cloud.quotaFullUntil") as? Date }
        set { defaults.set(newValue, forKey: "ai.cover.cloud.quotaFullUntil") }
    }
    func quotaFull(now: Date = Date()) -> Bool { (quotaFullUntil ?? .distantPast) > now }
    func resetStats() {
        for k in ["hits", "misses", "uploads", "uploadBytes", "failures", "lastError", "quotaFullUntil"] { defaults.removeObject(forKey: "ai.cover.cloud." + k) }
    }
    /// Names this device has already confirmed in the cloud (uploaded or hit) — avoids re-uploading.
    func markInCloud(_ name: String) {
        var s = defaults.stringArray(forKey: "ai.cover.cloud.known") ?? []
        guard !s.contains(name) else { return }
        s.append(name); if s.count > 5000 { s.removeFirst(s.count - 5000) }
        defaults.set(s, forKey: "ai.cover.cloud.known")
    }
    func isInCloud(_ name: String) -> Bool { (defaults.stringArray(forKey: "ai.cover.cloud.known") ?? []).contains(name) }
}

/// Background uploader: serial, utility priority, exponential backoff, Wi‑Fi-only option, stops on 507.
/// Payload source is a closure so a job whose local LRU file was evicted is just dropped.
actor AICoverUploadQueue {
    struct Job: Sendable, Equatable { let name: String; let contentType: String; let fileURL: URL? ; let data: Data? }
    static let shared = AICoverUploadQueue()

    private var client: AICoverCloudClient
    private let settings: AICoverCloudSettings
    private let isExpensiveNetwork: @Sendable () -> Bool
    private let sleep: @Sendable (Double) async -> Void
    private var jobs: [Job] = []
    private var running = false
    private(set) var log: [String] = []
    let maxAttempts = 5

    init(client: AICoverCloudClient = AICoverCloudClient(), settings: AICoverCloudSettings = .shared,
         isExpensiveNetwork: @escaping @Sendable () -> Bool = { AICoverNetworkState.isExpensive },
         sleep: @escaping @Sendable (Double) async -> Void = { s in try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }) {
        self.client = client; self.settings = settings; self.isExpensiveNetwork = isExpensiveNetwork; self.sleep = sleep
    }

    var pending: Int { jobs.count }
    func setClient(_ c: AICoverCloudClient) { client = c }

    func enqueue(_ job: Job) {
        guard settings.enabled, client.configured, !settings.isInCloud(job.name), !jobs.contains(where: { $0.name == job.name }) else { return }
        jobs.append(job)
        guard !running else { return }
        running = true
        Task.detached(priority: .utility) { [weak self] in await self?.run() }
    }

    /// Waits until the queue is idle (processing inline if no worker is running). Used by tests and the diagnostics.
    func drain() async {
        if !running { running = true; await run() }
        while running { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    private func run() async {
        defer { running = false }
        while let job = jobs.first {
            if settings.quotaFull() { note("507 配额已满，暂停上传"); jobs.removeAll(); return }
            if !settings.enabled { jobs.removeAll(); return }
            if settings.wifiOnly && isExpensiveNetwork() { note("仅 Wi‑Fi 上传：蜂窝网络下跳过 \(job.name)"); jobs.removeAll(); return }
            guard let data = job.data ?? job.fileURL.flatMap({ try? Data(contentsOf: $0) }) else { jobs.removeFirst(); note("本地文件已淘汰，放弃 \(job.name)"); continue }
            var attempt = 0
            var done = false
            while !done {
                attempt += 1
                switch await client.upload(name: job.name, data: data, contentType: job.contentType) {
                case .ok:
                    settings.countUpload(bytes: data.count); settings.markInCloud(job.name); note("上传 \(job.name) \(data.count) B"); done = true
                case .quotaFull:
                    settings.quotaFullUntil = Date().addingTimeInterval(24 * 3600); settings.countFailure("507 云端空间将满")
                    note("507 → 停止上传"); jobs.removeAll(); return
                case .rejected(let code):
                    settings.countFailure("HTTP \(code)"); note("拒绝 \(code) \(job.name)"); done = true
                case .retryable(let why):
                    if attempt >= maxAttempts { settings.countFailure(why); note("放弃 \(job.name)：\(why)"); done = true }
                    else { await sleep(Self.backoff(attempt)) }
                }
            }
            if !jobs.isEmpty { jobs.removeFirst() }
        }
    }

    static func backoff(_ attempt: Int) -> Double { min(300, 2 * pow(4, Double(attempt - 1))) }   // 2, 8, 32, 128, 300 s

    private func note(_ s: String) { log.append(s); if log.count > 50 { log.removeFirst() } }
}

/// Network cost flag (set by NWPathMonitor in the app; Foundation-only default here).
enum AICoverNetworkState {
    nonisolated(unsafe) static var isExpensive = false
}

/// Pure LRU trimming over (size, lastUse) records — shared by the disk cache and the tests.
/// Migration (290): files last used before `protectBefore` (the pre-290 cache) are neither counted nor evicted while the
/// grace window is open, so they can be uploaded opportunistically first; after the window they trim like any other file.
enum AICoverLRU {
    static func evictions(_ files: [(id: String, bytes: Int, lastUse: Date)], cap: Int, protectBefore: Date? = nil) -> [String] {
        let pool = files.filter { f in protectBefore.map { f.lastUse >= $0 } ?? true }
        var total = pool.reduce(0) { $0 + $1.bytes }
        guard total > cap else { return [] }
        var out: [String] = []
        for f in pool.sorted(by: { $0.lastUse < $1.lastUse }) where total > cap { out.append(f.id); total -= f.bytes }
        return out
    }
}

/// Migration bookkeeping for the pre-290 on-disk cache.
enum AICoverMigration {
    static let cutoffKey = "ai.cover.cloud.legacyCutoff290"
    static let grace: TimeInterval = 30 * 24 * 3600
    static func begin(_ d: UserDefaults = .standard, now: Date = Date()) {
        if d.object(forKey: cutoffKey) == nil { d.set(now, forKey: cutoffKey) }
    }
    static func protectBefore(_ d: UserDefaults = .standard, now: Date = Date()) -> Date? {
        guard let cutoff = d.object(forKey: cutoffKey) as? Date, now < cutoff.addingTimeInterval(grace) else { return nil }
        return cutoff
    }
}
