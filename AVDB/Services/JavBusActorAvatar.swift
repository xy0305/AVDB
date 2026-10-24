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
        let movies = tree.all { $0.tag == "div" && $0.cls("movie") }
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

private final class JavBusActorNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Shared, bounded, cancellable page cache. No account token/cookie is sent to JavBus.
@MainActor enum JavBusActorService {
    struct Page: Sendable { let entries: [JavBusActorParser.Entry]; let status: Int }
    typealias Fetch = @MainActor (String) async throws -> Page
    private struct Cached { let page: Page; let expiry: Date }
    private static var cache: [String: Cached] = [:]
    private static var busy = Set<String>()
    private static var active = 0
    private static var epoch = 0
    private static var scope = ""
    private static var works: [String: [String]] = [:]
    static var currentScope: String { JavDBConstants.baseURL + "|" + (APIClient.shared.token ?? "anonymous") }
    static func reset() { epoch += 1; cache.removeAll(); works.removeAll(); imageCache.removeAll() }
    static func synchronize() {
        if scope != currentScope { reset(); scope = currentScope }
    }
    static func remember(actorID: String, numbers: [String]) {
        synchronize()
        let values = ActorNameNormalizer.orderedUnique(numbers.compactMap(JavBusPoster.number))
        if !values.isEmpty { works[actorID] = Array(values.prefix(2)) }
        if works.count > 240 { works.removeAll(); works[actorID] = Array(values.prefix(2)) }
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
    static func lookup(actor: Actor, numbers: [String], fetch: Fetch? = nil) async throws -> String? {
        guard ActorAvatarFallback.existing(actor) == nil else { return nil }
        synchronize(); let generation = epoch, startingScope = currentScope
        let candidates = Array(ActorNameNormalizer.orderedUnique(numbers.compactMap(JavBusPoster.number)).prefix(2))
        for number in candidates {
            try Task.checkCancellation()
            let key = scope + "|" + number
            // Awaiting callers share the completed page, not uncancellable detached tasks.
            while busy.contains(key) || active >= 2 {
                try await Task.sleep(nanoseconds: 50_000_000)
                try Task.checkCancellation()
                guard generation == epoch, startingScope == currentScope else { throw CancellationError() }
                if !busy.contains(key), let cached = cache[key], cached.expiry > Date() { break }
            }
            guard generation == epoch, startingScope == currentScope else { throw CancellationError() }
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
                    throw error
                }
                try Task.checkCancellation()
                guard generation == epoch, startingScope == currentScope else { throw CancellationError() }
                if cache.count >= 120 { cache.removeAll() }
                cache[key] = Cached(page: page, expiry: Date().addingTimeInterval(page.status == 200 && !page.entries.isEmpty ? 86400 : 600))
            }
            guard page.status == 200 else { continue } // Includes 403: never a successful match.
            if let result = JavBusActorParser.select(page.entries, names: names(actor)) { return result }
        }
        return nil
    }
    private static var imageCache: [String: (Data?, Date)] = [:]
    static func imageData(_ url: URL) async throws -> Data? {
        guard JavBusActorParser.allowedImage(url) else { return nil }
        synchronize(); let startingScope = currentScope, generation = epoch
        let key = scope + "|image|" + url.absoluteString
        while busy.contains(key) || active >= 2 { try await Task.sleep(nanoseconds: 50_000_000); try Task.checkCancellation() }
        guard generation == epoch, startingScope == currentScope else { throw CancellationError() }
        if let hit = imageCache[key], hit.1 > Date() { return hit.0 }
        active += 1; busy.insert(key)
        defer { active -= 1; busy.remove(key) }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config, delegate: JavBusActorNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.httpShouldHandleCookies = false
        let (bytes, response) = try await session.bytes(for: request)
        var result: Data?
        if let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == url,
           http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("image/") == true {
            var data = Data()
            for try await byte in bytes {
                if data.count % 4096 == 0 { try Task.checkCancellation() }
                guard data.count < 2 * 1024 * 1024 else { return nil }
                data.append(byte)
            }
            result = data
        }
        try Task.checkCancellation()
        guard generation == epoch, startingScope == currentScope else { throw CancellationError() }
        if imageCache.count >= 60 { imageCache.removeAll() }
        imageCache[key] = (result, Date().addingTimeInterval(result == nil ? 600 : 86400))
        return result
    }
    static func request(_ number: String) async throws -> Page {
        guard let url = JavBusPoster.page(number: number) else { return Page(entries: [], status: 0) }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config, delegate: JavBusActorNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.httpShouldHandleCookies = false
        request.setValue("text/html", forHTTPHeaderField: "Accept")
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
        return Page(entries: try JavBusActorParser.entries(html: html, number: number, finalURL: url), status: 200)
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
    @State private var javbusImage: UIImage?
    @State private var revision = 0
    private var identity: String {
        actor.id + "|" + (ActorAvatarFallback.existing(actor) ?? "") + "|" + numbers.joined(separator: ",") + "|" + String(revision)
    }
    var body: some View {
        Group {
            if ActorAvatarFallback.existing(actor) == nil, let javbusImage {
                Image(uiImage: javbusImage).resizable().aspectRatio(contentMode: contentMode)
            } else { JavDBImage(url: ActorAvatarFallback.existing(actor) ?? fallback, contentMode: contentMode) }
        }
            .task(id: identity) {
                fallback = nil; javbusImage = nil
                guard ActorAvatarFallback.existing(actor) == nil else { return }
                let account = JavBusActorService.currentScope
                let known = numbers.isEmpty ? JavBusActorService.knownNumbers(actorID: actor.id) : numbers
                let hit = try? await JavBusActorService.lookup(actor: actor, numbers: known)
                guard !Task.isCancelled, account == JavBusActorService.currentScope else { return }
                if let hit, let url = URL(string: hit), let data = try? await JavBusActorService.imageData(url), let image = UIImage(data: data) {
                    guard !Task.isCancelled, account == JavBusActorService.currentScope else { return }
                    javbusImage = image; return
                }
                guard !Task.isCancelled, account == JavBusActorService.currentScope else { return }
                let tmdb = await ActorAvatarFallback.resolveMissing(actor: actor, names: JavBusActorService.names(actor))
                guard !Task.isCancelled, account == JavBusActorService.currentScope else { return }
                fallback = tmdb.url
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("avdb.catalog.accountChanged"))) { _ in
                JavBusActorService.reset(); ActorAvatarFallback.resetCache(); fallback = nil; javbusImage = nil; revision += 1
            }
    }
}
