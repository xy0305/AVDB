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
    init(host: String) { self.host = host }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https", request.url?.host?.lowercased() == host else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}

enum DetailPosterResolver {
    private static let cache = DetailPosterCache<DetailPosterArtwork>()

    static func resolve(movie: Movie, account: String?) async -> DetailPosterArtwork? {
        // Opaque, memory-only namespace. Never log/store the account credential.
        let scope = SHA256.hash(data: Data((account ?? "guest").utf8)).map { String(format: "%02x", $0) }.joined()
        let key = scope + "#" + movie.id + "#" + (movie.number ?? "") + "#" + (movie.coverURL ?? "") + "#" + (movie.thumbURL ?? "")
        return await cache.value(key: key) {
            let original = FrontPosterPolicy.usesOriginal(type: movie.type, number: movie.number)
            let sources = FrontPosterPolicy.sources(thumb: movie.thumbURL, cover: movie.coverURL, original: original)
            // Prefer already-decoded high resolution fronts, avoiding additional requests.
            for source in sources {
                if let image = await ImageLoader.shared.cachedDetailPoster(source: source),
                   let art = await artwork(image: image, source: source, derive: !original) { return art }
            }
            let deadline = Date().addingTimeInterval(12)
            let rules = original ? [] : DetailPosterPolicy.candidates(number: movie.number)
            var attempted = Set<String>()
            for source in sources + rules {
                guard !Task.isCancelled, Date() < deadline else { return nil }
                guard let url = URL(string: source), allowed(url),
                      !url.path.contains("/small_covers/"), !attempted.contains(source) else { continue }
                guard attempted.count < 4 else { break }
                attempted.insert(source)
                // attempted.count <= 4: actual downloads only, not skipped thumbnails.
                if let image = await download(url: url, timeout: min(5, deadline.timeIntervalSinceNow)),
                   let art = await artwork(image: image, source: source, derive: !original) { return art }
            }
            return nil
        }
    }

    private static func allowed(_ url: URL) -> Bool {
        if DetailPosterPolicy.allowedPublicImage(url) { return true }
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil else { return false }
        let host = url.host?.lowercased()
        return (host == JavDBConstants.imageCDNHost || host == JavDBConstants.webCDNHost)
            && (url.path.contains("/covers/") || url.path.contains("/small_covers/"))
    }

    private static func download(url: URL, timeout: TimeInterval) async -> UIImage? {
        guard timeout > 0, !Task.isCancelled else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: PosterRedirectGuard(host: url.host!.lowercased()), delegateQueue: nil)
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
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1800
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
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
