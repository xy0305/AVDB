import Foundation
import UIKit
import ImageIO
import CoreImage
import CryptoKit

struct DetailPosterArtwork: @unchecked Sendable {
    let image: UIImage
    let backdrop: UIImage
    let tint: UIColor
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
    private static let amazonPages = DetailPosterCache<String>(positiveTTL: 6 * 3600, negativeTTL: 300)
    private static let tenhowPages = DetailPosterCache<String>(positiveTTL: 6 * 3600, negativeTTL: 300)

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
        return scope + "#" + movie.id + "#" + (movie.type ?? "") + "#" + (movie.number ?? "") + "#" + (movie.coverURL ?? "") + "#" + (movie.thumbURL ?? "") + "#" + actors
    }

    static func initialLayout(movie: Movie, account: String?) -> DetailPosterLayout<DetailPosterArtwork> {
        let saved = cache.snapshot(key: identity(movie: movie, account: account))
        if case .resolving = saved {
            let original = FrontPosterPolicy.usesOriginal(type: movie.type, number: movie.number)
            let sources = FrontPosterPolicy.sources(thumb: movie.thumbURL, cover: movie.coverURL, original: original)
            let rules = original ? [] : DetailPosterPolicy.candidates(number: movie.number)
            // Definite unsupported/no eligible candidates: retain legacy immediately.
            if !(sources + rules).contains(where: { source in
                guard let url = URL(string: source) else { return false }
                return allowed(url) && !url.path.contains("/small_covers/")
                    && (!DetailPosterPolicy.allowedPublicImage(url) || rules.contains(source))
            }) && tenhowPaths(movie).isEmpty { return .landscape }
        }
        return saved
    }

    static func resolve(movie: Movie, account: String?) async -> DetailPosterArtwork? {
        let key = identity(movie: movie, account: account)
        return await cache.value(key: key) {
            let original = FrontPosterPolicy.usesOriginal(type: movie.type, number: movie.number)
            let sources = FrontPosterPolicy.sources(thumb: movie.thumbURL, cover: movie.coverURL, original: original)
            let rules = original ? [] : DetailPosterPolicy.candidates(number: movie.number)
            let validated = (sources + rules).filter { source in
                guard let url = URL(string: source), allowed(url), !url.path.contains("/small_covers/") else { return false }
                // Official public paths must be exact code-derived candidates;
                // metadata cannot smuggle an unrelated provider image into selection.
                return !DetailPosterPolicy.allowedPublicImage(url) || rules.contains(source)
            }
            let paths = tenhowPaths(movie)
            let discover: (@Sendable (TimeInterval) async -> [String])? = paths.isEmpty ? nil : { timeout in
                await discoverTenhow(paths: paths, number: movie.number ?? "", namespace: key, timeout: timeout)
            }
            let decoded: [DecodedPoster] = await DetailPosterSelection.collect(sources: validated, discover: discover) { source, timeout in
                guard let url = URL(string: source) else { return nil }
                return await download(url: url, timeout: timeout, derive: !original)
            }
            guard !Task.isCancelled,
                  let winner = DetailPosterQuality.winner(decoded.map(\.quality)),
                  let selected = decoded.first(where: { $0.quality.source == winner.source }) else { return nil }
            // No intermediate publication. The winner cache, not ImageLoader's
            // independently downsampled source cache, is the only warm fast path.
            return await artwork(image: selected.image, source: winner.source, derive: false)
        }
    }

    private static func discoverTenhow(paths: [String], number: String, namespace: String, timeout: TimeInterval) async -> [String] {
        let deadline = ProcessInfo.processInfo.systemUptime + min(timeout, 4)
        var matches = Set<String>()
        for path in paths.prefix(2) {
            guard !Task.isCancelled, TenhowPoster.allowedPage(path) else { return [] }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { break }
            let html = await tenhowPages.value(key: namespace + path) {
                await tenhowHTML(path: path, timeout: min(2, remaining))
            }
            if let html, let images = try? TenhowPoster.images(html: html, number: number) { matches.formUnion(images) }
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
        if DetailPosterPolicy.allowedPublicImage(url) { return true }
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return false }
        let host = url.host?.lowercased()
        return (host == JavDBConstants.imageCDNHost || host == JavDBConstants.webCDNHost)
            && (url.path.contains("/covers/") || url.path.contains("/small_covers/"))
    }

    struct DecodedPoster: @unchecked Sendable {
        let image: UIImage
        let quality: DetailPosterQuality
    }

    static func decode(data: Data, sourceURL: String, derive: Bool) -> DecodedPoster? {
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
        guard DetailPosterPolicy.eligible(width: cg.width, height: cg.height) else { return nil }
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
        return DecodedPoster(image: UIImage(cgImage: cg), quality: quality)
    }

    private static func download(url: URL, timeout: TimeInterval, derive: Bool) async -> DecodedPoster? {
        guard timeout > 0, !Task.isCancelled else { return nil }
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
                decode(data: data, sourceURL: url.absoluteString, derive: derive)
            }.value
        } catch { return nil }
    }

    private static func artwork(image: UIImage, source: String, derive: Bool) async -> DetailPosterArtwork? {
        guard !Task.isCancelled else { return nil }
        return await Task.detached(priority: .utility) { () -> DetailPosterArtwork? in
            guard var cg = image.cgImage else { return nil }
            if derive, let rect = FrontPosterPolicy.cropRect(width: cg.width, height: cg.height, source: source),
               let front = cg.cropping(to: rect) { cg = front }
            guard DetailPosterPolicy.eligible(width: cg.width, height: cg.height) else { return nil }
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
