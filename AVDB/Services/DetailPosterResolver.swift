import Foundation
import UIKit
import ImageIO
import CoreImage
import CryptoKit

struct DetailPosterArtwork: @unchecked Sendable {
    let image: UIImage
    let backdrop: UIImage
    let tint: UIColor
    var provenance: CoverProvenance? = nil
    var diagnostic: String = ""
}

/// A separate cookie-free session is essential: this resolver never sees a 115
/// cookie, bearer header, account settings, JavaScript, or public-page scripts.
private final class PosterRedirectGuard: NSObject, URLSessionTaskDelegate {
    let host: String
    let path: String
    init(url: URL) { self.host = url.host!.lowercased(); self.path = url.path }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let target = request.url, target.scheme == "https", target.host?.lowercased() == host,
              target.path == path, target.user == nil, target.password == nil, target.port == nil,
              target.query == nil, target.fragment == nil,
              (host != "www.tenhow.net" || TenhowPoster.permitsRedirect(from: URL(string: "https://" + host + path)!, to: target)) else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}

private final class AmazonPosterRedirectGuard: NSObject, URLSessionTaskDelegate {
    let asin: String
    private var redirects = 0
    init(asin: String) { self.asin = asin }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 2, let url = request.url, AmazonPoster.allowedPage(url, asin: asin) else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}

enum DetailPosterResolver {
    private static let cache = DetailPosterCache<DetailPosterArtwork>()
    private static let westernCache = DetailPosterCache<DetailPosterArtwork>()
    private static let westernWinners = DetailPosterCache<DetailPosterArtwork>()
    private static let amazonPages = DetailPosterCache<String>(positiveTTL: 6 * 3600, negativeTTL: 300)
    private static let tenhowPages = DetailPosterCache<String>(positiveTTL: 6 * 3600, negativeTTL: 300)
    private static let fallbackReasons = DetailPosterCache<String>(positiveTTL: 30)

    static func fallbackReason(movie: Movie, account: String?) -> String {
        if FrontPosterPolicy.usesOriginal(type: movie.type, number: movie.number) {
            return "保留原图：无码、FC2或未确认有码类别，不裁切"
        }
        if validatedSources(movie).isEmpty && tenhowPaths(movie).isEmpty { return "正封回退：不支持的来源" }
        return fallbackReasons.snapshot(key: identity(movie: movie, account: account)).artwork
            ?? "正封回退：未取得合格候选（网络或尺寸限制）"
    }

    static func clearWesternCaches() { westernCache.invalidate(); westernWinners.invalidate() }
    static func cachedWinner(movie: Movie, account: String?) -> DetailPosterArtwork? {
        westernWinners.snapshot(key: reuseKey(movie: movie, account: account)).artwork
    }

    private static func reuseKey(movie: Movie, account: String?) -> String {
        let scope = SHA256.hash(data: Data((account ?? "guest").utf8)).map { String(format: "%02x", $0) }.joined()
        return scope + "#" + movie.id + "#" + (movie.coverURL ?? "") + "#" + (movie.thumbURL ?? "") + "#" + WesternCoverSettings.shared.namespace.uuidString
    }
    static func navigationSeed(_ movie: Movie, movieID: String) -> Movie? {
        guard movie.id == movieID, movie.type == "0",
              TenhowPoster.number(movie.number ?? "") != nil,
              !actorIdentities(movie).flatMap({ $0 }).filter({ !$0.isEmpty }).isEmpty,
              !validatedSources(movie).isEmpty else { return nil }
        return movie
    }

    // Navigation metadata is only a head start. A sparse seed must not suppress
    // exact-actor discovery supplied by the subsequently loaded detail record.
    static func posterMovie(seed: Movie?, detail: Movie?) -> Movie? {
        guard let seed else { return detail }
        guard let detail, detail.id == seed.id else { return seed }
        if let type = detail.type, !type.isEmpty,
           FrontPosterPolicy.usesOriginal(type: type, number: detail.number)
            != FrontPosterPolicy.usesOriginal(type: seed.type, number: seed.number) { return detail }
        if tenhowPaths(seed).isEmpty && !tenhowPaths(detail).isEmpty { return detail }
        return seed
    }

    static func actorIdentities(_ movie: Movie) -> [[String]] {
        let structured = (movie.actors ?? []).map { actor in
            ([actor.name, actor.otherName, actor.keyword].compactMap { $0 }).flatMap {
                $0.components(separatedBy: CharacterSet(charactersIn: ",，、;/；|\n"))
            }
        }
        // actor_names is the API's original identity fallback, never UI displayName.
        return structured.isEmpty ? (movie.actorNames ?? []).map { [$0] } : structured
    }

    static func tenhowPaths(_ movie: Movie) -> [String] {
        guard !FrontPosterPolicy.usesOriginal(type: movie.type, number: movie.number),
              TenhowPoster.number(movie.number ?? "") != nil else { return [] }
        return TenhowPoster.pages(identities: actorIdentities(movie))
    }

    #if DEBUG
    private static let fixtureCache = DetailPosterCache<DetailPosterArtwork>()
    static func fixtureLayout(movie: Movie, account: String?) -> DetailPosterLayout<DetailPosterArtwork> {
        fixtureCache.snapshot(key: identity(movie: movie, account: account))
    }
    static func fixtureResolve(movie: Movie, account: String?,
        operation: @escaping @Sendable () async -> DetailPosterArtwork?) async -> DetailPosterArtwork? {
        await fixtureCache.value(key: identity(movie: movie, account: account), operation: operation)
    }
    #endif

    static func identity(movie: Movie, account: String?) -> String {
        // Opaque memory-only account namespace; never log credentials.
        let scope = SHA256.hash(data: Data((account ?? "guest").utf8)).map { String(format: "%02x", $0) }.joined()
        let actors = actorIdentities(movie).map { $0.joined(separator: "|") }.joined(separator: ";")
        var components: [String] = [scope, movie.id, movie.type ?? "", movie.number ?? "", movie.coverURL ?? "", movie.thumbURL ?? "", actors]
        if movie.type == "2" {
            components.append(WesternCoverSettings.shared.namespace.uuidString)
            components.append(movie.originTitle ?? movie.title ?? "")
            components.append(movie.releaseDate ?? "")
            components.append(String(movie.duration ?? 0))
            components.append(movie.originalURL ?? "")
        }
        return components.joined(separator: "#")
    }

    static func validatedSources(_ movie: Movie) -> [String] {
        let original = FrontPosterPolicy.usesOriginal(type: movie.type, number: movie.number)
        let sources = FrontPosterPolicy.sources(thumb: movie.thumbURL, cover: movie.coverURL, original: original)
        let rules = original ? [] : DetailPosterPolicy.candidates(number: movie.number)
        // Exact official metadata is checked against the movie BEFORE any URL
        // transform. Only one two-CDN pair, never a Cartesian candidate expansion.
        let exact: [String] = original ? [] : ([movie.thumbURL, movie.coverURL].compactMap { $0 }.compactMap { source -> [String]? in
            let values = DMMPoster.candidates(metadata: source, number: movie.number ?? "")
            return values.isEmpty ? nil : values
        }.first ?? [])
        let validated = (exact + sources + rules).filter { source in
            guard let url = URL(string: source), allowed(url), (movie.type == "2" || !url.path.contains("/small_covers/")) else { return false }
            return !DetailPosterPolicy.allowedPublicImage(url) || exact.contains(source) || rules.contains(source)
        }
        // Start a JavDB and MGS opportunity where available, not two new DMM
        // variants that could consume every non-Tenhow/Amazon family slot.
        let anchors = [validated.first { source in
            guard let url = URL(string: source) else { return false }
            return !DetailPosterPolicy.allowedPublicImage(url)
        }, validated.first { URL(string: $0)?.host == "image.mgstage.com" }].compactMap { $0 }
        return anchors + validated.filter { !anchors.contains($0) }
    }

    static func initialLayout(movie: Movie, account: String?) -> DetailPosterLayout<DetailPosterArtwork> {
        let selectedCache = movie.type == "2" ? westernCache : cache
        let saved = selectedCache.snapshot(key: identity(movie: movie, account: account))
        if case .resolving = saved {
            // Definite unsupported/no eligible candidates: retain legacy immediately.
            if movie.type != "2" && validatedSources(movie).isEmpty && tenhowPaths(movie).isEmpty { return .landscape }
        }
        return saved
    }

    static func resolve(movie: Movie, account: String?) async -> DetailPosterArtwork? {
        let key = identity(movie: movie, account: account)
        let epoch = WesternCoverSettings.shared.namespace
        let selectedCache = movie.type == "2" ? westernCache : cache
        return await selectedCache.value(key: key) { () async -> DetailPosterArtwork? in
            let original = FrontPosterPolicy.usesOriginal(type: movie.type, number: movie.number)
            let validated = validatedSources(movie)
            let paths = tenhowPaths(movie)
            let discover: (@Sendable (TimeInterval) async -> [String])?
            if movie.type == "2" {
                discover = { @Sendable timeout in
                    await WesternCoverService.discover(movie: movie, namespace: key, timeout: timeout).images
                }
            } else if paths.isEmpty {
                discover = nil
            } else {
                discover = { @Sendable (timeout: TimeInterval) async -> [String] in
                    await discoverTenhow(paths: paths, number: movie.number ?? "", namespace: key, timeout: timeout)
                }
            }
            let started = ProcessInfo.processInfo.systemUptime
            let decoded: [DecodedPoster] = await DetailPosterSelection.collect(sources: validated, discover: discover) { source, timeout in
                guard let url = URL(string: source) else { return nil }
                return await download(url: url, timeout: timeout, derive: !original, western: movie.type == "2")
            }
            guard !Task.isCancelled,
                  let winner = (movie.type == "2" ? WesternCoverPolicy.winner(decoded.map(\.quality)) : DetailPosterQuality.winner(decoded.map(\.quality))),
                  let selected = decoded.first(where: { $0.quality.source == winner.source }) else {
                if !Task.isCancelled, movie.type != "2" {
                    let exhausted = ProcessInfo.processInfo.systemUptime - started >= DetailPosterSelection.totalBudget
                    fallbackReasons.store(key: key, value: exhausted
                        ? "正封回退：12 秒预算耗尽，未取得合格候选"
                        : "正封回退：未取得合格候选（网络或尺寸限制）")
                }
                return nil
            }
            // No intermediate publication. The winner cache, not ImageLoader's
            // independently downsampled source cache, is the only warm fast path.
            guard var art = await artwork(image: selected.image, source: winner.source, derive: false, western: movie.type == "2") else { return nil }
            art.provenance = CoverProvenance(url: CoverSourceDisplay.safeURL(winner.source), rawWidth: selected.rawWidth, rawHeight: selected.rawHeight, effectiveWidth: winner.width, effectiveHeight: winner.height)
            if movie.type == "2" {
                art.diagnostic = WesternCoverService.diagnostic(movie: movie, namespace: key)
                let winnerName = CoverSourceDisplay.name(host: URL(string: winner.source)?.host ?? "")
                for family in ["ThePornDB", "片商", "Data18"] {
                    let available = decoded.contains { CoverSourceDisplay.name(host: URL(string: $0.quality.source)?.host ?? "") == family }
                    if available && winnerName != family { art.diagnostic += "；" + family + "：已解码可用未胜出" }
                }
            }
            guard !Task.isCancelled, movie.type != "2" || epoch == WesternCoverSettings.shared.namespace else { return nil }
            if movie.type == "2" { westernWinners.store(key: reuseKey(movie: movie, account: account), value: art) }
            return art
        }
    }

    private static func discoverTenhow(paths: [String], number: String, namespace: String, timeout: TimeInterval) async -> [String] {
        let deadline = ProcessInfo.processInfo.systemUptime + min(timeout, 4)
        var matches = Set<String>()
        var official = Set<String>()
        for path in paths.prefix(2) {
            guard !Task.isCancelled, TenhowPoster.allowedPage(path) else { return [] }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { break }
            let html = await tenhowPages.value(key: namespace + path) {
                await tenhowHTML(path: path, timeout: min(2, remaining))
            }
            if let html, let match = try? TenhowPoster.match(html: html, number: number) {
                matches.formUnion(match.images); official.formUnion(match.official)
            }
        }
        guard !Task.isCancelled, matches.count == 1, let tenhow = matches.first else { return [] }
        var result = [tenhow]
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        if remaining > 0.1, let url = URL(string: tenhow), let asin = AmazonPoster.asin(url) {
            // Exactly one record-verified ASIN; no title/keyword search, no year
            // guess. Both sources receive reserved slots, including 2021–2024.
            let html = await amazonPages.value(key: namespace + "#amazon#" + asin) {
                await amazonHTML(asin: asin, timeout: min(1.5, remaining))
            }
            if !Task.isCancelled, let html, let images = try? AmazonPoster.images(html: html, asin: asin) { result += images.prefix(1) }
        }
        // Tenhow and Amazon always lead. Do not enumerate alternate CIDs, pl
        // jackets or classifications. Ambiguous cross-page products add nothing.
        if official.count <= 2 { result += official.sorted() }
        return Task.isCancelled ? [] : result
    }

    private static func amazonHTML(asin: String, timeout: TimeInterval) async -> String? {
        guard let url = URL(string: "https://www.amazon.co.jp/dp/" + asin), AmazonPoster.allowedPage(url, asin: asin) else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = timeout; config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config, delegate: AmazonPosterRedirectGuard(asin: asin), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: url); request.timeoutInterval = timeout
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let final = response.url, AmazonPoster.allowedPage(final, asin: asin),
                  response.expectedContentLength <= 2 * 1024 * 1024 else { return nil }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 2 * 1024 * 1024 else { return nil }
                data.append(byte)
            }
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }

    private static func tenhowHTML(path: String, timeout: TimeInterval) async -> String? {
        guard TenhowPoster.allowedPage(path), timeout > 0,
              let url = URL(string: "https://www.tenhow.net" + path) else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = timeout; config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config, delegate: PosterRedirectGuard(url: url), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: url); request.timeoutInterval = timeout
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.expectedContentLength <= 768 * 1024 else { return nil }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 768 * 1024 else { return nil }
                data.append(byte)
            }
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }

    private static func allowed(_ url: URL) -> Bool {
        if DetailPosterPolicy.allowedPublicImage(url) || WesternCoverPolicy.imageAllowed(url) { return true }
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return false }
        let host = url.host?.lowercased()
        return (host == JavDBConstants.imageCDNHost || host == JavDBConstants.webCDNHost)
            && (url.path.contains("/covers/") || url.path.contains("/small_covers/"))
    }

    struct DecodedPoster: @unchecked Sendable {
        let image: UIImage
        let quality: DetailPosterQuality
        let rawWidth: Int
        let rawHeight: Int
    }

    static func decode(data: Data, sourceURL: String, derive: Bool, western: Bool = false) -> DecodedPoster? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let rawHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              rawWidth > 0, rawHeight > 0, rawWidth <= 10000, rawHeight <= 10000,
              rawWidth * rawHeight <= 40_000_000,
              // Full native decode, applying EXIF orientation; never enlarge.
              var cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(rawWidth, rawHeight)
              ] as CFDictionary) else { return nil }
        var cropped = false
        if derive, let rect = FrontPosterPolicy.cropRect(width: cg.width, height: cg.height, source: sourceURL) {
            guard let front = cg.cropping(to: rect) else { return nil }
            cg = front; cropped = true
        }
        guard (western ? WesternCoverPolicy.eligible(width: cg.width, height: cg.height) : DetailPosterPolicy.eligible(width: cg.width, height: cg.height)) else { return nil }
        let quality = DetailPosterQuality(source: sourceURL, width: cg.width, height: cg.height, originalPortrait: !cropped)
        // Keep only a bounded rendered raster per successful candidate. Score
        // above came from its real native front dimensions, not this downsample.
        if cg.height > 1800 {
            let scale = 1800 / Double(cg.height)
            guard let context = CGContext(data: nil, width: max(1, Int(Double(cg.width) * scale)), height: 1800,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
            guard let resized = context.makeImage() else { return nil }
            cg = resized
        }
        return DecodedPoster(image: UIImage(cgImage: cg), quality: quality, rawWidth: rawWidth, rawHeight: rawHeight)
    }

    private static func download(url: URL, timeout: TimeInterval, derive: Bool, western: Bool = false) async -> DecodedPoster? {
        guard timeout > 0, !Task.isCancelled, allowed(url) else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: PosterRedirectGuard(url: url), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            if ["bdn.dt18.com", "cdn.dt18.com"].contains(url.host ?? "") { request.setValue("https://www.data18.com/", forHTTPHeaderField: "Referer") }
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.expectedContentLength <= 12 * 1024 * 1024 else { return nil }
            var data = Data()
            for try await byte in bytes {
                if data.count >= 12 * 1024 * 1024 { return nil }
                data.append(byte)
            }
            try Task.checkCancellation()
            if url.host?.lowercased() == JavDBConstants.imageCDNHost {
                data = JavDBSignature.decryptImage(data)
            }
            return await Task.detached(priority: .utility) {
                decode(data: data, sourceURL: url.absoluteString, derive: derive, western: western)
            }.value
        } catch { return nil }
    }

    private static func artwork(image: UIImage, source: String, derive: Bool, western: Bool = false) async -> DetailPosterArtwork? {
        guard !Task.isCancelled else { return nil }
        return await Task.detached(priority: .utility) { () -> DetailPosterArtwork? in
            guard var cg = image.cgImage else { return nil }
            if derive, let rect = FrontPosterPolicy.cropRect(width: cg.width, height: cg.height, source: source),
               let front = cg.cropping(to: rect) { cg = front }
            guard (western ? WesternCoverPolicy.eligible(width: cg.width, height: cg.height) : DetailPosterPolicy.eligible(width: cg.width, height: cg.height)) else { return nil }
            let space = CGColorSpaceCreateDeviceRGB()
            var pixel = [UInt8](repeating: 0, count: 4)
            pixel.withUnsafeMutableBytes { bytes in
                if let ctx = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                       bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                }
            }
            // Muted sampled palette, not a hardcoded skin/scene or screenshot color.
            let tint = UIColor(red: CGFloat(pixel[0]) / 255 * 0.65 + 0.16,
                               green: CGFloat(pixel[1]) / 255 * 0.65 + 0.14,
                               blue: CGFloat(pixel[2]) / 255 * 0.65 + 0.13, alpha: 1)
            let input = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: 0.08, y: 0.08))
            let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 12]).cropped(to: input.extent)
            let backdrop = CIContext(options: [.cacheIntermediates: false]).createCGImage(blurred, from: input.extent).map { UIImage(cgImage: $0) } ?? UIImage(cgImage: cg)
            return DetailPosterArtwork(image: UIImage(cgImage: cg), backdrop: backdrop, tint: tint)
        }.value
    }
}
