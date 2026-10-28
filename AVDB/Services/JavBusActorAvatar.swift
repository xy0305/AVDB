import Foundation

/// Independent public-markup implementation; no ActorArchives code or DLL is loaded.
enum JavBusActorParser {
    struct Entry: Sendable, Equatable { let name: String; let actorURL: String; let imageURL: String }
    static func allowedImage(_ url: URL) -> Bool {
        JavBusPoster.clean(url) && url.path.range(of: #"^/pics/actress/[A-Za-z0-9]{1,40}_a\.(jpg|png)$"#, options: .regularExpression) != nil
    }
    static func entries(html: String, number: String, finalURL: URL) throws -> [Entry] {
        try Task.checkCancellation()
        guard html.utf8.count <= 768 * 1024, let wanted = JavBusPoster.number(number),
              JavBusPoster.allowedPage(finalURL, number: wanted) else { return [] }
        let lower = html.lowercased()
        guard !["cf-chl-", "challenge-platform", "captcha", "just a moment", "age verification", "driver-verify"].contains(where: lower.contains) else { return [] }
        let tree = try JRHTML.tree(html)
        // Real pages also label the magnet-submit form and magnet table as `movie`.
        // Ignore only these evidenced, identity-free auxiliary containers; an unknown
        // extra movie or any auxiliary carrying info/actor identity remains ambiguous.
        let movies = tree.all { $0.tag == "div" && $0.cls("movie") }.filter { node in
            let auxiliary = node.attrs["id"] == "mag-submit" || node.children.contains { $0.tag == "table" && $0.attrs["id"] == "magnet-table" }
            let identity = node.all { ($0.tag == "div" && $0.cls("info")) || ($0.tag == "a" && $0.cls("avatar-box")) || ($0.tag == "span" && $0.cls("header")) }
            return !auxiliary || !identity.isEmpty
        }
        guard movies.count == 1 else { return [] }
        let infos = movies[0].all { $0.tag == "div" && $0.cls("info") }
        guard infos.count == 1 else { return [] }
        var numbers: [String] = []
        for p in infos[0].all({ $0.tag == "p" }) {
            let spans = p.children.filter { $0.tag == "span" }
            guard let header = spans.first, header.cls("header"),
                  ["識別碼:", "识别码:"].contains(header.text) else { continue }
            guard spans.count == 2, let n = JavBusPoster.number(spans[1].text) else { return [] }
            numbers.append(n)
        }
        guard numbers == [wanted] else { return [] }
        var entries: [Entry] = []
        for node in tree.all({ $0.tag == "a" && $0.cls("avatar-box") }) {
            try Task.checkCancellation()
            guard let href = node.attrs["href"], let actor = URL(string: href, relativeTo: finalURL)?.absoluteURL,
                  JavBusPoster.clean(actor), actor.path.range(of: #"^/star/[A-Za-z0-9]{1,40}$"#, options: .regularExpression) != nil else { continue }
            let images = node.all { $0.tag == "img" }
            let labels = node.all { $0.tag == "span" }.map(\.text).filter { !$0.isEmpty }
            guard images.count == 1, labels.count == 1, let src = images[0].attrs["src"],
                  let url = URL(string: src, relativeTo: finalURL)?.absoluteURL, allowedImage(url),
                  !["nowprinting", "noimage", "no_image", "unknown", "placeholder"].contains(where: url.path.lowercased().contains) else { continue }
            let name = labels[0]
            if let title = images[0].attrs["title"], ActorNameNormalizer.key(title) != ActorNameNormalizer.key(name) { continue }
            let entry = Entry(name: name, actorURL: actor.absoluteString, imageURL: url.absoluteString)
            if !entries.contains(entry) { entries.append(entry) }
        }
        return entries
    }
    static func select(_ entries: [Entry], names: [String]) -> String? {
        let wanted = Set(names.map(ActorNameNormalizer.key).filter { !$0.isEmpty })
        let hits = entries.filter { wanted.contains(ActorNameNormalizer.key($0.name)) }
        // Even identical names belonging to two star IDs are ambiguous, never first-image wins.
        guard Set(hits.map(\.actorURL)).count == 1, Set(hits.map(\.imageURL)).count == 1 else { return nil }
        return hits.first?.imageURL
    }
}

enum ActorAvatarRedirectPolicy {
    static func permits(from: URL, to: URL, hops: Int) -> Bool {
        guard hops < 3, JavBusPoster.clean(from), JavBusPoster.clean(to), from.path == to.path else { return false }
        return JavBusActorParser.allowedImage(to) || JavBusPoster.number(String(to.path.dropFirst())).map { JavBusPoster.allowedPage(to, number: $0) } == true
    }
}
/// One public, credential-free header policy for both stages and redirect reconstruction.
enum JavBusActorRequests {
    static let version = "public-headers253"
    static let userAgent = "Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    static let language = "zh-CN,zh;q=0.9,en;q=0.7"
    static let pageAccept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    static let imageAccept = "image/avif,image/webp,image/*,*/*;q=0.8"
    static func validSource(_ url: URL) -> Bool {
        guard let n = JavBusPoster.number(String(url.path.dropFirst())) else { return false }
        return JavBusPoster.allowedPage(url, number: n)
    }
    static func request(_ url: URL, sourceURL: URL? = nil) -> URLRequest? {
        let image = JavBusActorParser.allowedImage(url)
        guard image ? sourceURL.map(validSource) == true : validSource(url) && sourceURL == nil else { return nil }
        var result = URLRequest(url: url)
        result.httpShouldHandleCookies = false
        result.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        result.setValue(language, forHTTPHeaderField: "Accept-Language")
        result.setValue(image ? imageAccept : pageAccept, forHTTPHeaderField: "Accept")
        if image { result.setValue(sourceURL!.absoluteString, forHTTPHeaderField: "Referer") }
        return result
    }
    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 10
        return config
    }
    static func redirected(from: URL, to: URL, hops: Int, sourceURL: URL?) -> URLRequest? {
        guard from.host?.lowercased() == to.host?.lowercased(), ActorAvatarRedirectPolicy.permits(from: from, to: to, hops: hops) else { return nil }
        return request(to, sourceURL: sourceURL)
    }
}
private final class JavBusActorRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var hops = 0
    private let sourceURL: URL?
    init(sourceURL: URL? = nil) { self.sourceURL = sourceURL }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let from = response.url, let to = request.url,
              let clean = JavBusActorRequests.redirected(from: from, to: to, hops: hops, sourceURL: sourceURL) else { completionHandler(nil); return }
        hops += 1
        completionHandler(clean)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}

/// Shared, bounded, cancellable page cache. Policy-versioned scope isolates old failures.
/// No account token/cookie is sent to JavBus.
@MainActor enum JavBusActorService {
    struct Page: Sendable {
        let entries: [JavBusActorParser.Entry]; let status: Int
        var sourceURL: URL? = nil
    }
    struct Artwork: Sendable { let imageURL: URL; let sourceURL: URL }
    private static var sources: [String: URL] = [:]
    static func lookupArtwork(actor: Actor, numbers: [String], existingFailed: Bool = false) async throws -> Artwork? {
        guard let hit = try await lookup(actor: actor, numbers: numbers, existingFailed: existingFailed),
              let image = URL(string: hit), let source = sources[hit] else { return nil }
        return Artwork(imageURL: image, sourceURL: source)
    }
    typealias Fetch = @MainActor (String) async throws -> Page
    private struct Cached { let page: Page; let expiry: Date }
    private static var cache: [String: Cached] = [:]
    private static var busy = Set<String>()
    private static var active = 0
    private static var epoch = 0
    private static var scope = ""
    private static var works: [String: [String]] = [:]
    static var currentScope: String { JavBusActorRequests.version + "|" + JavDBConstants.baseURL + "|" + (APIClient.shared.token ?? "anonymous") }
    static func reset() { epoch += 1; cache.removeAll(); works.removeAll(); imageCache.removeAll(); sources.removeAll() }
    static func synchronize() {
        if scope != currentScope { reset(); scope = currentScope }
    }
    static let maxWorks = 6
    static func remember(actorID: String, numbers: [String]) {
        synchronize()
        let values = ActorNameNormalizer.orderedUnique(numbers.compactMap(JavBusPoster.number))
        if !values.isEmpty, works[actorID] != Array(values.prefix(maxWorks)) {
            works[actorID] = Array(values.prefix(maxWorks))
            NotificationCenter.default.post(name: Notification.Name("avdb.actor.worksChanged"), object: actorID)
        }
        if works.count > 240 { works.removeAll(); works[actorID] = Array(values.prefix(maxWorks)) }
    }
    static func knownNumbers(actorID: String) -> [String] { synchronize(); return works[actorID] ?? [] }
    static func names(_ actor: Actor) -> [String] {
        let source = [actor.name, actor.otherName, actor.keyword, actor.nameZht].compactMap { $0 }
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",，、;；|/／\n")) }
        let catalog = ActorAliasCatalog.bundled()
        let mapped = catalog.lookup(source)
        let aliases = (mapped.map { [$0.canonical] + $0.aliases } ?? []).filter { !catalog.isConflict($0) }
        return ActorNameNormalizer.orderedUnique(source + aliases)
    }
    static func lookup(actor: Actor, numbers: [String], existingFailed: Bool = false, budget: TimeInterval = 25, fetch: Fetch? = nil) async throws -> String? {
        guard existingFailed || ActorAvatarFallback.existing(actor) == nil else { return nil }
        synchronize(); let generation = epoch, startingScope = currentScope
        let candidates = Array(ActorNameNormalizer.orderedUnique(numbers.compactMap(JavBusPoster.number)).prefix(maxWorks))
        let deadline = Date().addingTimeInterval(min(25, max(0, budget)))
        for number in candidates {
            guard Date() < deadline else { break }
            try Task.checkCancellation()
            let key = scope + "|" + number
            // Awaiting callers share the completed page, not uncancellable detached tasks.
            while busy.contains(key) || active >= 2 {
                guard Date() < deadline else { return nil }
                try await Task.sleep(nanoseconds: 50_000_000)
                try Task.checkCancellation()
                guard generation == epoch, startingScope == currentScope else { throw CancellationError() }
                if !busy.contains(key), let cached = cache[key], cached.expiry > Date() { break }
            }
            guard generation == epoch, startingScope == currentScope else { throw CancellationError() }
            guard Date() < deadline else { return nil }
            let page: Page
            if let cached = cache[key], cached.expiry > Date() { page = cached.page }
            else {
                active += 1; busy.insert(key)
                defer { active -= 1; busy.remove(key) }
                do { page = try await (fetch ?? request)(number) }
                catch is CancellationError { throw CancellationError() }
                catch {
                    try Task.checkCancellation()
                    if generation == epoch, startingScope == currentScope { cache[key] = Cached(page: Page(entries: [], status: 0), expiry: Date().addingTimeInterval(600)) }
                    continue
                }
                try Task.checkCancellation()
                guard generation == epoch, startingScope == currentScope else { throw CancellationError() }
                if cache.count >= 120 { cache.removeAll() }
                cache[key] = Cached(page: page, expiry: Date().addingTimeInterval(page.status == 200 && !page.entries.isEmpty ? 86400 : 600))
            }
            if [302, 401, 403, 429].contains(page.status) { return nil }
            guard page.status == 200 else { continue } // Includes 403: never a successful match.
            if let result = JavBusActorParser.select(page.entries, names: names(actor)) {
                if let source = page.sourceURL, JavBusPoster.allowedPage(source, number: number) {
                    if sources.count >= 720 { sources.removeAll() }
                    sources[result] = source
                }
                return result
            }
        }
        return nil
    }
    private static var imageCache: [String: (Data?, Date)] = [:]
    static func imageData(_ url: URL, sourceURL: URL) async throws -> Data? {
        guard JavBusActorParser.allowedImage(url), sources[url.absoluteString] == sourceURL,
              let request = JavBusActorRequests.request(url, sourceURL: sourceURL) else { return nil }
        synchronize(); let startingScope = currentScope, generation = epoch
        let key = scope + "|image|" + sourceURL.absoluteString + "|" + url.absoluteString
        while busy.contains(key) || active >= 2 { try await Task.sleep(nanoseconds: 50_000_000); try Task.checkCancellation() }
        guard generation == epoch, startingScope == currentScope else { throw CancellationError() }
        if let hit = imageCache[key], hit.1 > Date() { return hit.0 }
        active += 1; busy.insert(key)
        defer { active -= 1; busy.remove(key) }
        let session = URLSession(configuration: JavBusActorRequests.configuration(), delegate: JavBusActorRedirects(sourceURL: sourceURL), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        var result: Data?
        if let http = response as? HTTPURLResponse, http.statusCode == 200, let finalURL = http.url, JavBusActorParser.allowedImage(finalURL), finalURL.path == url.path,
           ["image/jpeg", "image/png"].contains(http.mimeType?.lowercased() ?? "") {
            var data = Data()
            for try await byte in bytes {
                if data.count % 4096 == 0 { try Task.checkCancellation() }
                guard data.count < 2 * 1024 * 1024 else { return nil }
                data.append(byte)
            }
            if ActorPortraitBytes.valid(data) { result = data }
        }
        try Task.checkCancellation()
        guard generation == epoch, startingScope == currentScope else { throw CancellationError() }
        if imageCache.count >= 60 { imageCache.removeAll() }
        imageCache[key] = (result, Date().addingTimeInterval(result == nil ? 600 : 86400))
        return result
    }
    static func request(_ number: String) async throws -> Page {
        guard let url = JavBusPoster.page(number: number) else { return Page(entries: [], status: 0) }
        let session = URLSession(configuration: JavBusActorRequests.configuration(), delegate: JavBusActorRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        guard let request = JavBusActorRequests.request(url) else { return Page(entries: [], status: 0) }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = http.url, JavBusPoster.allowedPage(finalURL, number: number),
              http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/html") == true else {
            return Page(entries: [], status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        var data = Data()
        for try await byte in bytes {
            if data.count % 4096 == 0 { try Task.checkCancellation() }
            guard data.count < 768 * 1024 else { return Page(entries: [], status: 0) }
            data.append(byte)
        }
        guard let html = String(data: data, encoding: .utf8) else { return Page(entries: [], status: 0) }
        // Parsing never runs on the UI actor. Cancellation is explicitly forwarded;
        // this short-lived CPU task cannot become detached background network work.
        let parser = Task.detached(priority: .utility) {
            try JavBusActorParser.entries(html: html, number: number, finalURL: finalURL)
        }
        let entries = try await withTaskCancellationHandler(operation: { try await parser.value }, onCancel: { parser.cancel() })
        try Task.checkCancellation()
        return Page(entries: entries, status: 200, sourceURL: finalURL)
    }
}

enum ActorPortraitBytes {
    static func valid(_ data: Data) -> Bool {
        data.starts(with: [0xff, 0xd8, 0xff]) || data.starts(with: [137,80,78,71,13,10,26,10])
    }
}

/// Deliberately narrow public agency-portrait source. Only one whitelisted agency
/// collection, exact alias filenames from its real index, never guessed actor URLs.
/// Delegate receives bounded chunks off the UI actor. AsyncBytes per-byte iteration
/// for a multi-megabyte public index is intentionally avoided.
private final class AgencyPortraitDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let url: URL
    let image: Bool
    let limit: Int
    var continuation: CheckedContinuation<Data, Error>?
    private var data = Data()
    private var accepted = false
    private(set) var response: HTTPURLResponse?
    init(url: URL, image: Bool) { self.url = url; self.image = image; self.limit = image ? 2 * 1024 * 1024 : 8 * 1024 * 1024 }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse; self.response = http
        accepted = http?.statusCode == 200 && http?.url == url && (image ? ["image/jpeg","image/png"] : ["application/json","text/plain"]).contains(http?.mimeType?.lowercased() ?? "") && response.expectedContentLength <= Int64(limit)
        completionHandler(accepted ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard accepted, chunk.count <= limit - data.count else { accepted = false; dataTask.cancel(); return }
        data.append(chunk)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let completion = continuation; continuation = nil
        if let error { completion?.resume(throwing:error) }
        else if !accepted { completion?.resume(throwing:URLError(.badServerResponse)) }
        else { completion?.resume(returning:data) }
    }
}

@MainActor enum GfriendsPortraits {
    struct Result { let url: String; let data: Data; let group: String }
    nonisolated static let root = "https://raw.githubusercontent.com/gfriends/gfriends/master/"
    /// Curated public agency / card portrait collections only. Wiki scrapes and
    /// retail jacket dumps stay out of scope: lower fidelity and multi-person
    /// wraps are not treated as single-person HQ portraits.
    nonisolated static let groups: [String] = [
        "6-Tpowers", "1-FALENO", "0-Hand-Storage", "2-Juicy-Honey", "3-MUTEKI",
        "1-Diaz", "2-Dahlia", "3-Allpro", "3-Arrows", "3-Lovepop", "6-Capsule", "6-Mines",
        "4-Kawaii", "5-Premium", "5-Ebody", "5-痴女天堂",
        "7-S1", "7-Madonna", "7-Moodyz", "7-未満",
        "8-Ideapocket", "8-GRAPHIS", "8-Honnaka", "8-KiraKira", "8-Bambi", "8-Cmore", "8-Digigra",
        "v-Prestige", "v-Attackers", "v-Fitch", "v-桃太郎",
        "w-OPPAI", "w-えむっ娘ラボ",
        "x-BeFree", "x-DAS", "x-WANZ", "x-KMP", "x-溜池ゴロー",
        "2-Nanairo", "y-Attractive",
    ]
    /// Compatibility alias for older probes that named only the first agency.
    nonisolated static let group = "6-Tpowers"
    private(set) static var diagnostics: [String:String] = [:]
    private static var index: [String: [String: String]]?
    private static var expiry = Date.distantPast
    private static var busy = false
    private static var epoch = 0
    private static var cache: [String:(Result?,Date)] = [:]
    static func reset() { epoch += 1; index = nil; expiry = .distantPast; cache.removeAll(); diagnostics.removeAll() }
    nonisolated static func allowedGroup(_ name: String) -> Bool { groups.contains(name) }
    static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == "raw.githubusercontent.com", url.port == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
        let path = url.path
        if path == "/gfriends/gfriends/master/Filetree.json" { return true }
        let rootPrefix = "/gfriends/gfriends/master/Content/"
        guard path.hasPrefix(rootPrefix) else { return false }
        let rest = String(path.dropFirst(rootPrefix.count))
        guard let slash = rest.firstIndex(of: "/") else { return false }
        let groupName = String(rest[..<slash])
        guard allowedGroup(groupName) else { return false }
        let file = String(rest[rest.index(after: slash)...])
        return file.count < 180 && !file.contains("/") && !file.contains("\\") && !file.contains("..") && !file.contains("%") && !file.contains("?") && !file.contains("#") && !file.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) && file.lowercased().hasSuffix(".jpg")
    }
    nonisolated static func parse(_ data: Data) throws -> [String: [String: String]] {
        try Task.checkCancellation()
        guard data.count <= 8 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String:Any],
              let content = object["Content"] as? [String:Any] else { return [:] }
        var result: [String: [String: String]] = [:]
        for group in groups {
            try Task.checkCancellation()
            guard let rows = content[group] as? [String:String], !rows.isEmpty, rows.count <= 25000 else { continue }
            result[group] = rows
        }
        return result
    }
    /// Single-collection exact match. Conflicting alias targets inside one group stay rejected.
    static func select(_ rows: [String:String], names: [String], group: String = "6-Tpowers") -> URL? {
        guard allowedGroup(group) else { return nil }
        let wanted = Set(names.map(ActorNameNormalizer.key).filter { !$0.isEmpty })
        var hits = Set<URL>()
        for (name, value) in rows {
            guard name.lowercased().hasSuffix(".jpg"), wanted.contains(ActorNameNormalizer.key(String(name.dropLast(4)))) else { continue }
            let pieces = value.components(separatedBy: "?t=")
            guard pieces.count == 2, !pieces[1].isEmpty, pieces[1].allSatisfy(\.isNumber) else { continue }
            let file = pieces[0]
            let url = URL(string: root)!.appendingPathComponent("Content").appendingPathComponent(group).appendingPathComponent(file)
            if allowed(url) { hits.insert(url) }
        }
        return hits.count == 1 ? hits.first : nil
    }
    /// Walk curated agencies in priority order; first group with a unique exact hit wins.
    /// Cross-group duplicates never auto-merge; later agencies are not consulted after a hit.
    static func select(index: [String: [String: String]], names: [String]) -> (url: URL, group: String)? {
        for group in groups {
            guard let rows = index[group], let url = select(rows, names: names, group: group) else { continue }
            return (url, group)
        }
        return nil
    }
    private static func download(_ url: URL, image: Bool) async throws -> Data? {
        guard allowed(url) else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 30
        let delegate = AgencyPortraitDownload(url:url,image:image)
        let session = URLSession(configuration:config,delegate:delegate,delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        let kind = image ? "image" : "index"
        do {
            try Task.checkCancellation()
            let data: Data = try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    delegate.continuation = continuation
                    var request = URLRequest(url:url); request.httpShouldHandleCookies = false
                    session.dataTask(with:request).resume()
                }
            }, onCancel: { session.invalidateAndCancel() })
            try Task.checkCancellation()
            diagnostics[kind] = "HTTP \(delegate.response?.statusCode ?? 0) \(delegate.response?.mimeType ?? "") bytes=\(data.count)"
            return !image || ActorPortraitBytes.valid(data) ? data : nil
        } catch {
            diagnostics[kind] = "HTTP \(delegate.response?.statusCode ?? 0) \(delegate.response?.mimeType ?? "") error=\(error.localizedDescription)"
            throw error
        }
    }
    static func lookup(names: [String]) async throws -> Result? {
        let starting = epoch, scope = JavBusActorService.currentScope
        while busy { try await Task.sleep(nanoseconds:50_000_000); try Task.checkCancellation() }
        guard starting == epoch, scope == JavBusActorService.currentScope else { throw CancellationError() }
        busy = true; defer { busy = false }
        let key = names.map(ActorNameNormalizer.key).sorted().joined(separator:"|")
        if let hit = cache[key], hit.1 > Date() { return hit.0 }
        if expiry < Date() {
            let rows: [String: [String: String]]
            if let data = try? await download(URL(string:root+"Filetree.json")!,image:false) {
                let parser = Task.detached(priority: .utility) { try parse(data) }
                rows = try await withTaskCancellationHandler(operation: { try await parser.value }, onCancel: { parser.cancel() })
            } else { rows = [:] }
            try Task.checkCancellation()
            guard starting == epoch, scope == JavBusActorService.currentScope else { throw CancellationError() }
            diagnostics["indexedGroups"] = String(rows.count)
            diagnostics["indexedRows"] = String(rows.values.reduce(0) { $0 + $1.count })
            index = rows
            expiry = Date().addingTimeInterval(rows.isEmpty ? 600 : 86400)
        }
        try Task.checkCancellation()
        guard starting == epoch, scope == JavBusActorService.currentScope else { throw CancellationError() }
        var result: Result?
        if let index, let hit = select(index: index, names: names), let data = try? await download(hit.url, image: true) {
            diagnostics["selectedGroup"] = hit.group
            result = Result(url: hit.url.absoluteString, data: data, group: hit.group)
        }
        try Task.checkCancellation()
        guard starting == epoch, scope == JavBusActorService.currentScope else { throw CancellationError() }
        if cache.count >= 60 { cache.removeAll() }
        cache[key] = (result, Date().addingTimeInterval(result == nil ? 600 : 86400))
        return result
    }
}

// MARK: - Native shared presentation
import SwiftUI

/// No extra AVDB actorMovies request is made by cards. Detail supplies its already-loaded works.
@MainActor struct ActorAvatarArtwork: View {
    let actor: Actor
    var numbers: [String] = []
    var contentMode: ContentMode = .fill
    @State private var fallback: String?
    @State private var portrait: UIImage?
    @State private var revision = 0
    private var identity: String {
        actor.id + "|" + ([actor.avatarURL, actor.coverURL].compactMap { $0 }.joined(separator: ",")) + "|" + JavBusActorService.names(actor).joined(separator: ",") + "|" + numbers.joined(separator: ",") + "|" + String(revision)
    }
    var body: some View {
        Group {
            if let portrait { Image(uiImage: portrait).resizable().aspectRatio(contentMode: contentMode) }
            else { JavDBImage(url: fallback, contentMode: contentMode) }
        }
        .task(id: identity) {
            fallback = nil; portrait = nil
            let account = JavBusActorService.currentScope
            // A non-empty URL is not proof of a decoded image. Preserve valid AVDB artwork;
            // only a completed failed load enables public fallbacks (not cancellation).
            for source in ActorNameNormalizer.orderedUnique([actor.avatarURL, actor.coverURL].compactMap { $0 }) {
                let image = await ImageLoader.shared.load(source, maxPixelSize: 512)
                guard !Task.isCancelled, account == JavBusActorService.currentScope else { return }
                if let image { portrait = image; return }
            }
            let known = numbers.isEmpty ? JavBusActorService.knownNumbers(actorID: actor.id) : numbers
            let hit = try? await JavBusActorService.lookupArtwork(actor: actor, numbers: known, existingFailed: true)
            guard !Task.isCancelled, account == JavBusActorService.currentScope else { return }
            if let hit, let data = try? await JavBusActorService.imageData(hit.imageURL, sourceURL: hit.sourceURL), let image = UIImage(data: data) {
                guard !Task.isCancelled, account == JavBusActorService.currentScope else { return }
                portrait = image; return
            }
            // Public agency portrait index; no JavBus verification/challenge is followed.
            if let result = try? await GfriendsPortraits.lookup(names: JavBusActorService.names(actor)), let image = UIImage(data: result.data) {
                guard !Task.isCancelled, account == JavBusActorService.currentScope else { return }
                portrait = image; return
            }
            // avbase talent page → declared FANZA actjpgs headshot (after curated HQ Gfriends).
            if let url = await AvbasePortraitService.shared.lookup(names: JavBusActorService.names(actor)),
               let image = await ImageLoader.shared.load(url, maxPixelSize: 512) {
                guard !Task.isCancelled, account == JavBusActorService.currentScope else { return }
                portrait = image; return
            }
            guard !Task.isCancelled, account == JavBusActorService.currentScope else { return }
            let tmdb = await ActorAvatarFallback.resolveMissing(actor: actor, names: JavBusActorService.names(actor), existingFailed: true)
            guard !Task.isCancelled, account == JavBusActorService.currentScope else { return }
            fallback = tmdb.url
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("avdb.actor.worksChanged"))) { note in
            if note.object as? String == actor.id { revision += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("avdb.catalog.accountChanged"))) { _ in
            JavBusActorService.reset(); GfriendsPortraits.reset(); ActorAvatarFallback.resetCache(); fallback = nil; portrait = nil; revision += 1
        }
    }
}
