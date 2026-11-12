//
//  ImageLoader.swift
//  AVDB
//
//  图片加载器：下载 CDN 加密流并解密后显示。
//  支持缓存，避免重复请求。
//

import Foundation
import ImageIO
import CoreImage
import CryptoKit
import SwiftUI

/// 图片加载错误
public enum ImageLoaderError: Error {
    case downloadFailed
    case decryptFailed
    case invalidData
}

/// 高清封面 URL 构建器（移植自 jable.js 的 HQ cover 规则）。
/// 根据番号拼出 DMM / MGS 官方无水印高清封面直链，作为 JAVDB 加密封面的首选/回退源。
public enum CoverURLBuilder {

    /// 番号 → contentId 的厂牌前缀映射（对齐 jable.js numMap）。
    private static let numMap: [String: String] = [
        "WSA": "2",
        "FSDSS": "1", "FCDSS": "1", "FNS": "1", "FTHTD": "1",
        "FALENO": "1", "FGAN": "1", "FSNF": "1", "FLAV": "1",
        "ABP": "118", "CHN": "118",
        "STARS": "1", "STAR": "1", "START": "1",
        "SODS": "1",
        "REBD": "h_346", "REBDB": "h_346", "GSHRB": "h_346",
    ]

    /// MGS（prestige 系）厂牌映射。
    private static let mgstageRules: [String: String] = [
        "ABF": "prestige", "ABW": "prestige", "ABP": "prestige",
        "CHN": "prestige", "JUFE": "prestige", "MAAN": "prestige",
        "PPT": "prestige", "390JAC": "jackson",
    ]

    /// 生成高清封面候选 URL（poster + backdrop）。
    public static func coverURLs(for number: String?) -> (poster: String?, backdrop: String?) {
        guard let number, !number.isEmpty else { return (nil, nil) }
        let raw = number.uppercased()
        // Digit-bearing prefixes and amateur namespaces have no safe guessed CID.
        // Use linked-record metadata instead of truncating R18 or 723GGH.
        if let parsed = CatalogueIdentity.parts(raw), parsed.prefix.contains(where: { $0.isNumber }) { return (nil, nil) }
        guard let match = raw.range(of: #"([A-Z0-9]+)-?(\d{2,5})"#, options: .regularExpression) else {
            return (nil, nil)
        }
        let seg = String(raw[match])
        // 分离字母前缀与数字
        let prefix = String(seg.prefix { !$0.isNumber })
            .trimmingCharacters(in: CharacterSet(charactersIn: "- \t"))
        let numStr = String(seg.drop { !$0.isNumber })
            .trimmingCharacters(in: CharacterSet(charactersIn: "- \t"))
        guard !prefix.isEmpty, let idx = Int(numStr), idx > 0 else {
            return (nil, nil)
        }
        // FC2/FC2PPV 没有 DMM 标准封面，必须回退到 JAVDB cover_url。
        if prefix == "FC2" || prefix == "FC2PPV" { return (nil, nil) }
        let prefixLower = prefix.lowercased()
        let number5 = String(idx).paddingLeft(toLength: 5, withPad: "0")
        let mapPrefix = numMap[prefix] ?? ""
        let code = "\(mapPrefix)\(prefixLower)\(number5)"

        // MGS 厂牌
        if let maker = mgstageRules[prefix] {
            let base = "https://image.mgstage.com/images/\(maker)/\(prefixLower)/\(idx)"
            let poster = "\(base)/pf_e_\(prefixLower)-\(idx).jpg"
            let backdrop = "\(base)/pb_e_\(prefixLower)-\(idx).jpg"
            return (poster, backdrop)
        }

        // DMM 默认（Build 282）：解析器给出的 CID（学习/种子厂牌前缀，如 MILK → h_1240），
        // awsimgsrc ps 为全尺寸竖版正面，pl 为 1600 宽完整封套。
        let cid = DMMCID.candidates(number: "\(prefix)-\(idx)").first ?? code
        let urls = DMMCoverURLs.digital(cid)
        return (urls[0], urls[1])
    }
}

/// Tenhow（日亚商品图）竖版封面解析器。
/// Tenhow 条目同时包含 DMM cid 与 ASIN 图片名，可用番号对应 cid 后取得原尺寸 poster。
public actor TenhowCoverResolver {
    public static let shared = TenhowCoverResolver()

    private let baseURL = URL(string: "https://www.tenhow.net/")!
    private var actorPages: [String: String]?
    private var resultCache: [String: String?] = [:]

    public func coverURL(number: String, releaseDate: String?, actorNames: [String]) async -> String? {
        guard let year = releaseDate.flatMap({ Int($0.prefix(4)) }), (2021...2026).contains(year),
              !number.isEmpty, !actorNames.isEmpty else { return nil }
        let key = number.uppercased()
        if let cached = resultCache[key] { return cached }

        do {
            let pages = try await loadActorPages()
            for name in actorNames {
                let candidates = actorNameCandidates(name)
                guard let path = candidates.compactMap({ pages[$0] }).first,
                      let pageURL = URL(string: path, relativeTo: baseURL) else { continue }
                let html = try await downloadText(pageURL)
                if let asin = asin(in: html, matching: number) {
                    let result = "https://www.tenhow.net/images/\(asin).jpg"
                    resultCache[key] = result
                    return result
                }
            }
        } catch { }
        resultCache[key] = nil
        return nil
    }

    private func actorNameCandidates(_ name: String) -> [String] {
        name.components(separatedBy: CharacterSet(charactersIn: " /／・,，()（）[]【】"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func loadActorPages() async throws -> [String: String] {
        if let actorPages { return actorPages }
        // mokuji.html 的演员目录更新不完整；首页/分类页会包含新演员（如神木麗）。
        let indexPaths = ["mokuji.html", "index.html", "body.html", "kyonyu.html", "gokujo.html"]
        let regex = try NSRegularExpression(pattern: #"href=[\"']([^\"']+\.html)[\"'][^>]*>([^<]+)</a>"#, options: .caseInsensitive)
        var result: [String: String] = [:]
        for indexPath in indexPaths {
            guard let url = URL(string: indexPath, relativeTo: baseURL),
                  let html = try? await downloadText(url) else { continue }
            let ns = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                let path = ns.substring(with: match.range(at: 1))
                let rawName = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                for name in actorNameCandidates(rawName) where !name.isEmpty {
                    result[name] = path
                }
            }
        }
        actorPages = result
        return result
    }

    private func asin(in html: String, matching number: String) -> String? {
        let regex = try? NSRegularExpression(
            pattern: #"href=[\"'](?:images/)?(B[0-9A-Z]{9})\.jpg[\"'][\s\S]{0,1800}?cid%3D([^%&\"']+)"#,
            options: .caseInsensitive
        )
        guard let regex else { return nil }
        let ns = html as NSString
        let target = normalize(number)
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let cid = ns.substring(with: match.range(at: 2)).removingPercentEncoding ?? ""
            if normalize(cid) == target { return ns.substring(with: match.range(at: 1)).uppercased() }
        }
        return nil
    }

    private func normalize(_ value: String) -> String {
        var value = value.uppercased().replacingOccurrences(of: #"[^A-Z0-9]"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"^H\d+"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"^\d+(?=[A-Z])"#, with: "", options: .regularExpression)
        guard let range = value.range(of: #"\d+$"#, options: .regularExpression) else { return value }
        let prefix = String(value[..<range.lowerBound])
        let digits = Int(value[range]) ?? 0
        return prefix + String(digits)
    }

    private func downloadText(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { throw ImageLoaderError.downloadFailed }
        return text
    }
}

extension String {
    func paddingLeft(toLength: Int, withPad: String) -> String {
        guard toLength > count else { return self }
        return String(repeating: withPad, count: toLength - count) + self
    }
}

/// Fast Core Image clarity for soft / early **JavDB-native** movie covers only.
/// Off by default. Never touches DMM, Amazon, JavBus, Tenhow, TPDB, Avbase, MGS,
/// actor portraits, or any non-JavDB host. Uses system CISharpenLuminance (no ML).
public enum JavDBCoverEnhance {
    public static let defaultsKey = "javdb.cover.enhance.enabled"
    /// Mild luminance sharpen; same filter family as player NativeLUT, kept light for ≤~200ms.
    public static let sharpness: Double = 0.35
    /// Skip when the longer edge already looks high-res (HQ replacements need no help).
    public static let highResSkipPixels = 1200

    public static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Cache-key tag so toggling on/off never serves the wrong raster.
    public static var cacheTag: String { isEnabled ? "e1" : "e0" }

    public static func isJavDBNativeCover(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        guard host == JavDBConstants.imageCDNHost || host == JavDBConstants.webCDNHost else { return false }
        // Movie jackets only — never actress/avatar or unrelated CDN paths.
        return path.contains("/covers/") || path.contains("/small_covers/")
    }

    public static func shouldEnhance(source: String, width: Int, height: Int) -> Bool {
        guard isEnabled, isJavDBNativeCover(source), width > 0, height > 0 else { return false }
        return max(width, height) < highResSkipPixels
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

    public static func apply(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let ci = CIImage(cgImage: cg)
        let sharpened = ci.clampedToExtent()
            .applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: sharpness])
            .cropped(to: ci.extent)
        guard let out = context.createCGImage(sharpened, from: sharpened.extent) else { return image }
        return UIImage(cgImage: out, scale: image.scale, orientation: image.imageOrientation)
    }

    public static func maybeApply(_ image: UIImage, source: String) -> UIImage {
        guard let cg = image.cgImage,
              shouldEnhance(source: source, width: cg.width, height: cg.height) else { return image }
        return apply(image)
    }
}

/// List-only artwork policy, independently implemented after researching Amane.
/// Metadata is not rewritten: detail screens still request the untouched original.
public enum FrontPosterPolicy {
    public static func isKnownWrap(_ value: String) -> Bool {
        guard let url = URL(string: value), let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        return (host == JavDBConstants.imageCDNHost && path.contains("/covers/"))
            || (host == JavDBConstants.webCDNHost && path.contains("/covers/"))
            || (host == "image.mgstage.com" && path.contains("/pb_e_"))
            || isHQStoreJacket(value)
    }

    /// Build 285: DUGA 1000 px jacket / MGS Prestige 1125 px package (front = right 0.703·h).
    public static func isHQStoreJacket(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return AvbaseHQExtras.isDugaJacket(url) || AvbaseHQExtras.isMGSPrestigePackage(url)
    }

    /// API catalog values: 0 censored, 1 Japanese uncensored, 2 Western, 3 FC2.
    /// Never infer Western from a horizontal image or an unfamiliar code (e.g. HEYZO).
    public static func usesOriginal(type: String?, number: String?) -> Bool {
        let type = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if ["1", "2", "3", "uncensored", "western", "fc2"].contains(type) { return true }
        let number = number?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        if number.range(of: #"^HEYZO[- _]?\d"#, options: .regularExpression) != nil { return true }
        if number.range(of: #"^FC2(?:[- _]?PPV)?[- _]?\d"#, options: .regularExpression) != nil { return true }
        // JavDB Western catalog uses Studio.YYYY.MM.DD; HEYZO-1234 is not Western.
        if number.range(of: #"^[A-Z][A-Z0-9 _-]*\.\d{4}\.\d{2}\.\d{2}$"#, options: .regularExpression) != nil { return true }
        // Missing catalog is common in mixed lists. Only positively known censored labels
        // can opt in to DVD-front derivation; unknown/uncensored (including HEYZO) stay original.
        let censoredLabels: Set<String> = ["IPX", "IPZZ", "SSIS", "SSNI", "SSIW", "SONE", "MIDV", "MIDE", "MIAA", "MIAB", "JUQ", "JUFE", "JUL", "JUR", "STARS", "START", "STAR", "SODS", "ABP", "ABW", "ABF", "FSDSS", "FCDSS", "FNS", "FTHTD", "FALENO", "FGAN", "FSNF", "FLAV", "PPPD", "PRED", "DASS", "CAWD", "EBOD", "WANZ", "WAAA", "WAVR", "MEYD", "ROE", "HMN", "HND", "RBD", "SHKD"]
        if type == "0" || type == "censored" { return false }
        let prefix = String(number.prefix { $0.isLetter })
        return !censoredLabels.contains(prefix)
    }

    public static func sources(thumb: String?, cover: String?, original: Bool = false) -> [String] {
        // JAVDB small_covers are genuine portraits, but observed at 147x200;
        // covers are 800x538 DVD wraps. Prefer the high-resolution front in that pair.
        let values = !original && cover.map(isKnownWrap) == true ? [cover, thumb] : [thumb, cover]
        var result: [String] = []
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !result.contains(value) { result.append(value) }
        }
        return result
    }

    public static func cropRect(width: Int, height: Int, source: String, validatedJacket: Bool = false) -> CGRect? {
        let dmmJacket = DMMCoverURLs.isJacket(source)
        guard width > 0, height > 0, isKnownWrap(source) || validatedJacket || dmmJacket else { return nil }
        let ratio = Double(width) / Double(height)
        // Standard DVD jacket only; never blindly slice arbitrary landscape photos.
        guard (1.35...1.65).contains(ratio) else { return nil }
        // Build 285: DMM / DUGA / MGS-Prestige jackets: the front is the right-aligned 0.703·h
        // (ps↔pl alignment, 15/17 titles); MILK (h_1240) keeps its measured 0.69 (745 of 1081).
        let measured = dmmJacket || isHQStoreJacket(source)
        let frontWidth = Int((Double(height) * (measured ? DMMImageValidation.frontRatio(source: source) : 0.7)).rounded())
        guard frontWidth > 0, frontWidth < width else { return nil }
        return CGRect(x: width - frontWidth, y: 0, width: frontWidth, height: height)
    }
}

/// Build 332: color-preserving crop for `loadPoster` and resolver pixel-crop sites.
/// Translates the *uncropped* original into a tightly packed sRGB 32 bpp bitmap
/// sized to the crop rect (translate −origin). Never takes a `cg.cropping()`
/// subimage as input. Redraw only when a crop actually happens; native portrait
/// passthrough stays zero-copy. No filters, LUTs, or manual color correction.
public enum PosterColorCrop {
    public static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Tightly packed sRGB 32 bpp crop of `image` to `rect` (CGImage pixel space).
    /// Preserves `scale` and `imageOrientation`.
    public static func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let x = rect.origin.x.rounded(.towardZero)
        let y = rect.origin.y.rounded(.towardZero)
        let w = Int(rect.width.rounded())
        let h = Int(rect.height.rounded())
        guard w > 0, h > 0, x >= 0, y >= 0,
              x + CGFloat(w) <= CGFloat(cg.width) + 0.5,
              y + CGFloat(h) <= CGFloat(cg.height) + 0.5 else { return nil }
        let bytesPerRow = w * 4
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 1:1 translate, no resample.
        ctx.interpolationQuality = .none
        ctx.translateBy(x: -x, y: -y)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Crop only when `FrontPosterPolicy` produces a rect; otherwise return `image` unchanged.
    public static func cropIfNeeded(_ image: UIImage, source: String, validatedJacket: Bool = false) -> UIImage {
        guard let cg = image.cgImage,
              let rect = FrontPosterPolicy.cropRect(width: cg.width, height: cg.height,
                                                    source: source, validatedJacket: validatedJacket) else {
            return image
        }
        return crop(image, to: rect) ?? image
    }
}

/// Build 332: JPEG encode / restore that keeps the ICC profile so a cached
/// sRGB raster is not later displayed as DeviceRGB or Display P3.
enum PosterJPEGColor {
    static func data(_ image: UIImage, quality: CGFloat = 0.88) -> Data? {
        guard var cg = image.cgImage else { return image.jpegData(compressionQuality: quality) }
        if needsSRGBTag(cg), let tagged = retagSRGB(cg) { cg = tagged }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return image.jpegData(compressionQuality: quality)
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            return image.jpegData(compressionQuality: quality)
        }
        return data as Data
    }

    static func image(from data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        guard let cg = image.cgImage else { return image }
        if needsSRGBTag(cg), let tagged = retagSRGB(cg) {
            return UIImage(cgImage: tagged, scale: image.scale, orientation: image.imageOrientation)
        }
        return image
    }

    static func needsSRGBTag(_ cg: CGImage) -> Bool {
        guard let space = cg.colorSpace, let name = space.name else { return true }
        // Keep a real ICC / named space (sRGB, Display P3, …). Retag only DeviceRGB / generic.
        if name == CGColorSpace.sRGB || name == CGColorSpace.displayP3 { return false }
        let raw = name as String
        if raw.contains("sRGB") || raw.contains("DisplayP3") || raw.contains("P3") { return false }
        return true
    }

    static func retagSRGB(_ cg: CGImage) -> CGImage? {
        guard let provider = cg.dataProvider else { return nil }
        return CGImage(width: cg.width, height: cg.height,
                       bitsPerComponent: cg.bitsPerComponent, bitsPerPixel: cg.bitsPerPixel,
                       bytesPerRow: cg.bytesPerRow, space: PosterColorCrop.sRGB,
                       bitmapInfo: cg.bitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: cg.shouldInterpolate, intent: cg.renderingIntent)
    }
}

/// 图片加载器（单例）：后台解密/降采样、请求合并、按内存压力自动淘汰。
public actor ImageLoader {
    public static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let posterCache = NSCache<NSString, UIImage>()
    private var posterInFlight: [String: Task<UIImage?, Never>] = [:]
    private let userAgent = "Mozilla/5.0 (Linux; Android 13; javdb)"

    private init() {
        posterCache.countLimit = 180
        posterCache.totalCostLimit = 48 * 1024 * 1024
        cache.countLimit = 240
        cache.totalCostLimit = 192 * 1024 * 1024
    }

    /// 获取图片（自动判断是否需要解密）
    public func load(_ urlString: String?, maxPixelSize: Int = 2048, timeout: TimeInterval = 20) async -> UIImage? {
        guard let urlString = urlString, !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }
        #if DEBUG
        // Build 328: hanging CDN stand-in (MIDE-991). Sleeps for the caller timeout
        // or until cancelled so the hero race budget can force a terminal state.
        if urlString.hasPrefix("fixture://hang") {
            let nanos = UInt64(max(timeout, 0.05) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            return nil
        }
        // Build 329: delayed CDN stand-in, e.g. fixture://delay/15/poster/portrait-hero-a
        // The declared delay is honored even past the hero's 6s provisional settle.
        if urlString.hasPrefix("fixture://delay/") {
            let rest = String(urlString.dropFirst("fixture://delay/".count))
            let parts = rest.split(separator: "/", maxSplits: 1)
            let seconds = Double(parts.first.map(String.init) ?? "") ?? 0
            if seconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            if Task.isCancelled { return nil }
            let tail = parts.count > 1 ? String(parts[1]) : "poster/portrait"
            let poster: String
            if tail.hasPrefix("fixture://") {
                poster = tail
            } else if tail.hasPrefix("poster/") {
                poster = "fixture://" + tail
            } else {
                poster = "fixture://poster/" + tail
            }
            return Self.fixturePoster(poster)
        }
        if urlString.hasPrefix("fixture://poster/") {
            return Self.fixturePoster(urlString)
        }
        #endif
        let pixelSize = max(320, maxPixelSize)
        let tag = JavDBCoverEnhance.cacheTag
        let cacheKey = "\(urlString)#\(pixelSize)#\(tag)" as NSString
        if let img = cache.object(forKey: cacheKey) {
            return img
        }

        let flightKey = "\(urlString)#\(pixelSize)#\(tag)"
        if let task = inFlight[flightKey] {
            return await task.value
        }

        let task = Task.detached(priority: .utility) { [userAgent] () -> UIImage? in
            // Verified HQ covers are disk-cached: a hit paints instantly and
            // never touches the network, even on a cold launch.
            let cacheable = HQPosterDiskCache.isCacheable(urlString)
            if cacheable, let diskImage = HQPosterDiskCache.image(forKey: flightKey) {
                return diskImage
            }
            let raw = await Self.fetchImage(url: url, urlString: urlString, userAgent: userAgent, maxPixelSize: pixelSize, timeout: timeout)
            guard let raw else { return nil }
            let image = JavDBCoverEnhance.maybeApply(raw, source: urlString)
            if cacheable { HQPosterDiskCache.store(image, forKey: flightKey) }
            return image
        }
        inFlight[flightKey] = task
        let image = await task.value
        inFlight[flightKey] = nil
        if Task.isCancelled { return nil }

        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
            cache.setObject(image, forKey: cacheKey, cost: cost)
        }
        return image
    }

    #if DEBUG
    nonisolated static func fixturePoster(_ urlString: String) -> UIImage {
        let name = urlString.components(separatedBy: "/").last ?? "neutral"
        // portrait-hero-a is an A-tier hero raster (≥1000 px wide); a name
        // containing "thumb147" is the typical JavDB 147×200 small_cover.
        let size: CGSize
        if name.contains("thumb147") || name.contains("small147") {
            size = CGSize(width: 147, height: 200)
        } else if name.contains("hero-a") || name.contains("portrait-a") {
            size = CGSize(width: 1200, height: 1800)
        } else if name.contains("portrait") {
            size = CGSize(width: 700, height: 1000)
        } else if name.contains("square") {
            size = CGSize(width: 700, height: 700)
        } else if name.contains("wide") {
            size = CGSize(width: 1200, height: 500)
        } else {
            size = CGSize(width: 800, height: 538)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            ("NEUTRAL " + name).draw(at: CGPoint(x: 40, y: size.height * 0.45),
                withAttributes: [.font: UIFont.systemFont(ofSize: 36, weight: .bold),
                                 .foregroundColor: UIColor.white])
        }
    }
    #endif

    /// Decoded source cache stays separate from bounded list-only derivatives.
    public func loadPoster(_ source: String, maxPixelSize: Int, timeout: TimeInterval = 20) async -> UIImage? {
        let tag = JavDBCoverEnhance.cacheTag
        let key = "front-v2#\(tag)#\(source)#\(maxPixelSize)"
        if let cached = posterCache.object(forKey: key as NSString) { return cached }
        if let flight = posterInFlight[key] { return await flight.value }
        let flight = Task { () -> UIImage? in
            // load() already applies JavDB enhance when enabled; crop the enhanced raster
            // with a color-preserving translate-redraw (never cg.cropping).
            guard let original = await self.load(source, maxPixelSize: maxPixelSize, timeout: timeout) else { return nil }
            return await Task.detached(priority: .utility) {
                PosterColorCrop.cropIfNeeded(original, source: source)
            }.value
        }
        posterInFlight[key] = flight
        let result = await flight.value
        posterInFlight[key] = nil
        if let result {
            let cost = result.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
            posterCache.setObject(result, forKey: key as NSString, cost: cost)
        }
        return result
    }

    private static func isExternalCover(_ urlString: String) -> Bool {
        // Include AWS DMM CDN so NOW placeholders (147×200) fail fast on list HQ tries.
        urlString.contains("pics.dmm.co.jp")
            || urlString.contains("awsimgsrc.dmm.co.jp")
            || urlString.contains("image.mgstage.com")
    }

    /// 判断是否为 App 专用加密 CDN（tp.spfcas.com）
    private static func isEncryptedCDN(_ urlString: String) -> Bool {
        return urlString.contains(JavDBConstants.imageCDNHost)
    }

    #if DEBUG
    /// Neutral fixture transport. Production leaves this nil. Returning nil is a
    /// miss, never an enlarged copy of the small list image.
    static var testTransport: (@Sendable (String, Int) async -> UIImage?)?
    static var testTransportCalls = 0
    static let testTransportLock = NSLock()
    static func resetTestTransport() {
        testTransportLock.lock(); testTransport = nil; testTransportCalls = 0; testTransportLock.unlock()
    }
    /// Drop memory caches so a later test's testTransport is not skipped on a warm hit.
    func resetCachesForTests() {
        cache.removeAllObjects()
        posterCache.removeAllObjects()
        inFlight.removeAll()
        posterInFlight.removeAll()
    }
    #endif

    private static func fetchImage(url: URL, urlString: String, userAgent: String, maxPixelSize: Int, timeout: TimeInterval = 20) async -> UIImage? {
        #if DEBUG
        if let testTransport {
            testTransportLock.lock(); testTransportCalls += 1; testTransportLock.unlock()
            return await testTransport(urlString, maxPixelSize)
        }
        #endif
        do {
            let downloaded = try await download(url, userAgent: userAgent, timeout: timeout)
            let imageData = isEncryptedCDN(urlString)
                ? JavDBSignature.decryptImage(downloaded)
                : downloaded
            guard let image = downsample(imageData, maxPixelSize: maxPixelSize) else {
                throw ImageLoaderError.invalidData
            }

            // DMM/MGS 某些地址会返回通用 NOW 占位图：ps 为 147x200，
            // pl 为 590x800。pl 本应是横版剧照，因此竖向 pl 也必须判无效。
            if isExternalCover(urlString) {
                let tooSmall = max(image.size.width, image.size.height) < 500
                let portraitBackdrop = urlString.lowercased().hasSuffix("pl.jpg")
                    && image.size.height > image.size.width
                if tooSmall || portraitBackdrop { throw ImageLoaderError.invalidData }
            }
            return image
        } catch {
            return nil
        }
    }

    private static func download(_ url: URL, userAgent: String, timeout: TimeInterval = 20) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ImageLoaderError.downloadFailed
        }
        return data
    }

    /// Read-only detail reuse: no network, no catalog mutations, original decoding unchanged.
    func cachedDetailPoster(source: String) -> UIImage? {
        let tag = JavDBCoverEnhance.cacheTag
        for size in [2048, 1600, 1200, 1000, 720, 640] {
            if let image = posterCache.object(forKey: "front-v1#\(tag)#\(source)#\(size)" as NSString) { return image }
            if let image = cache.object(forKey: "\(source)#\(size)#\(tag)" as NSString) { return image }
            // Legacy untagged keys (pre-Build272) still warm when enhance is off.
            if tag == "e0" {
                if let image = posterCache.object(forKey: "front-v1#\(source)#\(size)" as NSString) { return image }
                if let image = cache.object(forKey: "\(source)#\(size)" as NSString) { return image }
            }
        }
        return nil
    }

    /// 提前解码并限制纹理尺寸，避免原始大图在滚动期间触发主线程解码和内存峰值。
    private static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// 清空缓存
    public func clearCache() {
        cache.removeAllObjects()
        posterCache.removeAllObjects()
        HQPosterDiskCache.removeAll()
    }
}

/// AsyncImage 封装：自动处理 JAVDB 加密 CDN；可选优先加载高清源并回退。
public struct JavDBImage: View {
    let url: String?
    var fallbackURL: String? = nil
    var secondFallbackURL: String? = nil
    let contentMode: ContentMode
    let maxPixelSize: Int
    let frontPoster: Bool
    let fitUncroppedLandscape: Bool
    let showsSourceLabel: Bool

    @State private var image: UIImage?
    @State private var imageProvenance: PosterProvenance?
    @State private var imageIdentity: String?
    @State private var loadFailed = false
    @State private var retryTick = 0

    private var requestIdentity: String {
        imageURLs.joined(separator: "|") + "#\(frontPoster)#\(maxPixelSize)"
    }

    private func publish(_ value: UIImage, identity: String, source: String) {
        guard !Task.isCancelled, identity == requestIdentity else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            image = value
            imageProvenance = PosterProvenance(source: source)
            imageIdentity = identity
        }
    }

    public init(
        url: String?,
        fallbackURL: String? = nil,
        secondFallbackURL: String? = nil,
        contentMode: ContentMode = .fill,
        maxPixelSize: Int = 2048,
        frontPoster: Bool = false,
        fitUncroppedLandscape: Bool = false,
        showsSourceLabel: Bool = false
    ) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.secondFallbackURL = secondFallbackURL
        self.contentMode = contentMode
        self.maxPixelSize = maxPixelSize
        self.frontPoster = frontPoster
        self.fitUncroppedLandscape = fitUncroppedLandscape
        self.showsSourceLabel = showsSourceLabel
    }

    /// Build 343: poster cells opt in so an image that stayed an uncropped
    /// landscape (no portrait source existed, so the candidate loop's
    /// landscape fallback is what got published) is shown whole instead of
    /// as a magnified centre slice of itself. Portrait and square images,
    /// and every caller that does not opt in, render exactly as before.
    private var displayedContentMode: ContentMode {
        if fitUncroppedLandscape, let image, image.size.width > image.size.height { return .fit }
        return contentMode
    }

    private var imageURLs: [String] {
        var result: [String] = []
        for candidate in [url, fallbackURL, secondFallbackURL] {
            if let candidate, !candidate.isEmpty, !result.contains(candidate) {
                result.append(candidate)
            }
        }
        return result
    }

    public var body: some View {
        // Color.clear 吃父视图提议的尺寸；图片只在 overlay 里绘制。
        // 直接把 resizable Image 放进网格会按原图像素报告 ideal size，
        // 把 LazyVGrid 格子撑爆（.clipped() 只裁绘制、不改布局）。
        Color.clear
            .overlay {
                if let image, imageIdentity == requestIdentity {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: displayedContentMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    placeholder
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if showsSourceLabel, image != nil, imageIdentity == requestIdentity, let imageProvenance {
                    Text(imageProvenance.text)
                        .font(.caption2).foregroundStyle(.white.opacity(0.85))
                        .padding(5).background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 5))
                        .padding(10)
                        .accessibilityIdentifier("detail-cover-source")
                }
            }
            // Identity replacement must also ignore a parent's animation. Merely
            // disabling animation in publish() leaves an old Image fading out
            // when the new source fails and no publication ever occurs.
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .contentShape(Rectangle())
            // Retry is the only interactive affordance; a painted image never steals the card tap.
            .allowsHitTesting(loadFailed && image == nil)
            .task(id: requestIdentity + "#" + String(retryTick)) {
            let identity = requestIdentity
            loadFailed = false
            #if DEBUG
            if let url, url.hasPrefix("fixture://poster/") {
                let name = url.components(separatedBy: "/").last ?? "neutral"
                let size: CGSize
                if name.contains("thumb147") || name.contains("small147") {
                    size = CGSize(width: 147, height: 200)
                } else if name.contains("hero-a") || name.contains("portrait-a") {
                    size = CGSize(width: 1200, height: 1800)
                } else if name.contains("portrait") {
                    size = CGSize(width: 700, height: 1000)
                } else if name.contains("square") {
                    size = CGSize(width: 700, height: 700)
                } else if name.contains("wide") {
                    size = CGSize(width: 1200, height: 500)
                } else {
                    size = CGSize(width: 800, height: 538)
                }
                let renderer = UIGraphicsImageRenderer(size: size)
                var fixtureImage = renderer.image { context in
                    UIColor.systemTeal.setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                    UIColor.systemOrange.setFill()
                    context.fill(CGRect(x: 424, y: 0, width: 376, height: 538))
                    ("NEUTRAL " + url.components(separatedBy: "/").last!) .draw(at: CGPoint(x: 300, y: 260), withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.white])
                }
                if frontPoster {
                    fixtureImage = PosterColorCrop.cropIfNeeded(fixtureImage, source: "https://tp.spfcas.com/covers/neutral.jpg")
                }
                publish(fixtureImage, identity: identity, source: url)
                return
            }
            #endif
            // 不先清空 image。LazyVGrid 滚动时 task 会被取消，先清空会让中间封面变空白。
            // Build 329: the floor paints the first available source immediately,
            // including typical JavDB 147×200 small_covers. 360 px is only a
            // preference among already-decoded candidates, never a discard gate.
            var best: UIImage?
            var bestSource: String?
            var landscapeFallback: (image: UIImage, source: String)?
            for candidate in imageURLs {
                guard !Task.isCancelled else { return }
                let loaded = frontPoster
                    ? await ImageLoader.shared.loadPoster(candidate, maxPixelSize: maxPixelSize)
                    : await ImageLoader.shared.load(candidate, maxPixelSize: maxPixelSize)
                if let img = loaded {
                    guard !Task.isCancelled else { return }
                    if frontPoster, img.size.width > img.size.height {
                        landscapeFallback = landscapeFallback ?? (img, candidate)
                        continue
                    }
                    if let current = best, let currentSource = bestSource,
                       !RailCoverFloor.prefers(img, source: candidate, to: current, currentSource: currentSource) {
                        continue
                    }
                    best = img
                    bestSource = candidate
                    publish(img, identity: identity, source: candidate)
                    // Keep looking only if a later candidate might be preferred (≥360 / wider).
                    if RailCoverFloor.pixelWidth(img) >= RailCoverFloor.minWidth { break }
                }
            }
            if best == nil, !Task.isCancelled, let landscapeFallback {
                best = landscapeFallback.image
                bestSource = landscapeFallback.source
                publish(landscapeFallback.image, identity: identity, source: landscapeFallback.source)
            }
            if best == nil, !Task.isCancelled, !imageURLs.isEmpty, identity == requestIdentity {
                loadFailed = true
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        let kind = RailPosterPlaceholder.kind(hasURL: !imageURLs.isEmpty, failed: loadFailed)
        ZStack {
            LinearGradient(
                colors: [Color(.systemGray6), Color(.systemGray5).opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            switch kind {
            case .filmIcon:
                // Only when there is no cover/thumb URL at all.
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.42))
                        .frame(width: 48, height: 48)
                    Image(systemName: "film.stack")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            case .retry:
                VStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                    Text("點按重試")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(8)
                .contentShape(Rectangle())
                .onTapGesture { retryTick += 1 }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("封面載入失敗，點按重試")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("rail-cover-retry")
            case .loading:
                // URL exists and is in flight: plain gray, never a film.stack flash.
                EmptyView()
            }
        }
        .accessibilityHidden(kind != .retry)
    }
}

/// Home / grid cards upgrade only while visible. Immediate thumb/cover stays on
/// screen; HQ fetches are bounded and cancel off-screen. This is not an upscale
/// of the small image and never starts AI enhancement.
/// Build 303: Wi‑Fi allows more parallel upgrades; cellular stays conservative.
/// Pixel sizes are quantized so disk cache keys match across cells / prefetch.
enum VisibleHQPosterPolicy {
    static let cellularConcurrency = 2
    static let wifiConcurrency = 5
    /// Effective cap used by the scheduler (Wi‑Fi vs cellular / expensive).
    static var concurrency: Int { currentConcurrency() }
    static func currentConcurrency() -> Int {
        AICoverNetworkState.isExpensive ? cellularConcurrency : wifiConcurrency
    }
    /// A phone card is ~120 pt; iPad can be wider. Cap the fetch so a 3× screen
    /// never pulls a multi-megapixel original into a list cell.
    static let maxPixelCap = 900
    static let minPixelFloor = 360
    /// Shared buckets so prefetch and visible cells hit the same disk keys.
    static let pixelBuckets = [360, 540, 720, 900]
    /// Prefetch / ahead warm size: typical 3× phone card after quantize (~513→540).
    static let listPrefetchPixels = 540
    static let negativeTTL: TimeInterval = 10 * 60
    static let requestTimeout: TimeInterval = 8

    static func quantizePixels(_ raw: Int) -> Int {
        let clamped = min(maxPixelCap, max(minPixelFloor, raw))
        return pixelBuckets.first(where: { $0 >= clamped }) ?? maxPixelCap
    }

    static func targetPixels(displayPoints: CGSize, scale: CGFloat) -> Int {
        let longest = max(displayPoints.width, displayPoints.height) * max(scale, 1)
        guard longest.isFinite, longest > 0 else { return minPixelFloor }
        return quantizePixels(Int(longest.rounded(.up)))
    }

    /// One already-admitted HQ URL, or nil. Never discovers Tenhow/Amazon pages
    /// and never adds a host. Cache hits win; otherwise the first safe public
    /// candidate ListCoverPolicy already built.
    static func upgradeURL(movie: Movie) -> String? {
        if FrontPosterPolicy.usesOriginal(type: movie.type, number: movie.number) {
            // Build 335: originals stay thumb-only UNLESS a catalogue poster
            // (a genuine portrait, never the landscape wrap) was resolved for
            // this movie. The detail rails enrich their items with catalogue
            // metadata, so their cards upgrade to that HD portrait instead of
            // sitting on the 147x200 thumb.
            guard let poster = movie.catalogueMetadata?.poster,
                  poster != movie.thumbURL,
                  let url = URL(string: poster), isSafeUpgradeHost(url) else { return nil }
            return poster
        }
        if let cached = ListHQCoverCache.url(for: movie.number),
           let url = URL(string: cached), isSafeUpgradeHost(url) { return cached }
        for source in boundedCandidates(movie: movie) {
            guard let url = URL(string: source), isSafeUpgradeHost(url) else { continue }
            if isImmediateListSource(source, movie: movie) { continue }
            return source
        }
        return nil
    }

    /// The same admitted hosts ListCoverPolicy used to splice in synchronously.
    /// Capped at one URL so a visible card never fans out into nine full-size fetches.
    static func boundedCandidates(movie: Movie) -> [String] {
        var result: [String] = []
        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { return }
            result.append(trimmed)
        }
        for image in movie.catalogueMetadata?.images ?? [] {
            guard let url = URL(string: image) else { continue }
            for hq in DMMCoverURLs.upgrade(image) { append(hq) }
            if DetailPosterPolicy.allowedPublicImage(url)
                || AvbaseMetadata.allowedDiscoveredImage(url)
                || AmazonPoster.allowedImage(url)
                || TenhowPoster.allowedImage(url) {
                append(image)
            }
            if result.count >= 1 { break }
        }
        // Build 300: every list (not only Home) upgrades visible cards. Most list rows
        // carry no catalogue images, so when none is admitted try exactly ONE rule
        // candidate (DMM awsimgsrc ps portrait / MGS pf_e), never a fan-out. DMM
        // NOW-PRINTING / 147x200 answers are rejected by ImageLoader and land in the
        // short negative cache; the small JavDB image stays underneath.
        if result.isEmpty, let guess = DetailPosterPolicy.candidates(number: movie.number).first {
            append(guess)
        }
        return Array(result.prefix(1))
    }

    static func isImmediateListSource(_ source: String, movie: Movie) -> Bool {
        source == movie.thumbURL || source == movie.coverURL
    }

    /// Same hosts DetailPosterResolver / ListHQCoverCache already admit. No new host.
    static func isSafeUpgradeHost(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil else { return false }
        if ListHQCoverCache.isHQHost(url) { return true }
        return DetailPosterPolicy.allowedPublicImage(url)
            || AmazonPoster.allowedImage(url)
            || TenhowPoster.allowedImage(url)
            || AvbaseMetadata.allowedDiscoveredImage(url)
    }
}

/// Bounded visible-card upgrades. Account/backend scope follows ListHQCoverCache.
/// A cancel never writes the negative cache. Low Power Mode skips the upgrade and
/// leaves the small image. Build 303: concurrency follows Wi‑Fi vs cellular.
actor VisibleHQPosterScheduler {
    static let shared = VisibleHQPosterScheduler()
    private var active = 0
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    func upgrade(movie: Movie, url: String, maxPixelSize: Int) async -> UIImage? {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return nil }
        guard VisibleHQPosterPolicy.isSafeUpgradeHost(URL(string: url) ?? URL(string: "about:blank")!) else { return nil }
        if ListHQCoverCache.isNegative(number: movie.number) { return nil }
        let pixels = VisibleHQPosterPolicy.quantizePixels(maxPixelSize)
        guard await acquire() else { return nil }
        defer { release() }
        guard !Task.isCancelled else { return nil }
        let loaded = await ImageLoader.shared.load(url, maxPixelSize: pixels, timeout: VisibleHQPosterPolicy.requestTimeout)
        if Task.isCancelled { return nil }
        if let loaded {
            // Build 300: a learned DMM pl / store jacket is a landscape envelope; show its
            // front (Plan A crop) off the main thread. Portrait sources pass through.
            let image = await Task.detached(priority: .utility) { () -> UIImage in
                PosterColorCrop.cropIfNeeded(loaded, source: url)
            }.value
            if RailCoverFloor.rejects(source: url, image: image) { return nil }
            ListHQCoverCache.store(number: movie.number, source: url)
            return image
        }
        ListHQCoverCache.storeNegative(number: movie.number)
        return nil
    }

    private func acquire() async -> Bool {
        if active < VisibleHQPosterPolicy.currentConcurrency() {
            active += 1
            #if DEBUG
            noteActive()
            #endif
            return true
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            waiters.append(continuation)
        }
    }

    private func release() {
        active -= 1
        guard !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        active += 1
        #if DEBUG
        noteActive()
        #endif
        next.resume(returning: true)
    }

    #if DEBUG
    static var testPeakActive = 0
    func resetForTests() {
        active = 0
        Self.testPeakActive = 0
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume(returning: false) }
    }
    var activeCount: Int { active }
    private func noteActive() { Self.testPeakActive = max(Self.testPeakActive, active) }
    #endif
}

/// Memory-only HQ URL tips learned from detail poster wins.
/// List reads synchronously; never triggers Tenhow/Amazon discovery itself.
enum ListHQCoverCache {
    private static let lock = NSLock()
    // Build 285: verified winners persist across launches (UserDefaults, bounded), so list
    // cards and history show the HQ cover immediately instead of re-learning it.
    static let defaultsKey = "list.hq.cover.urls.v1"
    private static var urls: [String: String] = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
    private static var order: [String] = Array(urls.keys)
    private static let capacity = 1024
    /// Failures are memory-only and short-lived. A cancelled upgrade must not call this.
    private static var negatives: [String: TimeInterval] = [:]

    static func key(_ number: String) -> String? {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }
        // Same account/backend boundary as detail artwork. The token is hashed so a
        // persisted URL map never stores the credential itself.
        let account = APIClient.shared.token ?? "guest"
        let scope = SHA256.hash(data: Data((JavBusActorRequests.version + "|" + JavDBConstants.baseURL + "|" + account).utf8)).map { String(format: "%02x", $0) }.joined()
        return String(scope.prefix(16)) + "#" + trimmed
    }

    static func url(for number: String?) -> String? {
        guard let number, let key = key(number) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return urls[key]
    }

    static func isNegative(number: String?) -> Bool {
        guard let number, let key = key(number) else { return false }
        lock.lock(); defer { lock.unlock() }
        guard let until = negatives[key] else { return false }
        if ProcessInfo.processInfo.systemUptime >= until {
            negatives[key] = nil
            return false
        }
        return true
    }

    /// Memory-only. Callers must not invoke this after cancellation.
    static func storeNegative(number: String?, ttl: TimeInterval = VisibleHQPosterPolicy.negativeTTL) {
        guard let number, let key = key(number), ttl > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        negatives[key] = ProcessInfo.processInfo.systemUptime + ttl
    }

    static func store(number: String?, source: String) {
        guard let number, let key = key(number),
              let parsed = URL(string: source), isHQHost(parsed) else { return }
        lock.lock()
        if urls[key] == source { lock.unlock(); return }
        if urls[key] == nil, urls.count >= capacity, let oldest = order.first {
            urls[oldest] = nil; order.removeFirst()
        }
        if urls[key] == nil { order.append(key) }
        urls[key] = source
        let snapshot = urls
        lock.unlock()
        UserDefaults.standard.set(snapshot, forKey: defaultsKey)
    }

    static func isHQHost(_ url: URL) -> Bool {
        switch url.host?.lowercased() {
        case "m.media-amazon.com", "images-na.ssl-images-amazon.com",
             "pics.dmm.co.jp", "awsimgsrc.dmm.co.jp",
             "image.mgstage.com", "www.tenhow.net", "pic.duga.jp":
            return true
        default:
            return false
        }
    }

    #if DEBUG
    static func resetForTests() {
        lock.lock(); defer { lock.unlock() }
        urls.removeAll(); order.removeAll(); negatives.removeAll()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
    #endif
}

/// Persistent on-disk cache for verified HQ poster images.
/// ListHQCoverCache persists WHICH URL won; this persists the *resized*
/// image bytes (URL + target pixel size key via ImageLoader flightKey), so a
/// learned HQ cover paints instantly on later launches without re-decoding
/// the full DMM/MGS original. Build 303: prefetch warms the same quantized
/// cell size visible upgrades request.
/// Scope is exactly the hosts ListHQCoverCache already admits as HQ —
/// no new host, no JavDB traffic. Bounded LRU in the system Caches
/// directory (iOS may purge it under storage pressure): the byte limit
/// is user-configurable in Settings (persisted, applied immediately,
/// least-recently-used evicted first), with a generous file-count
/// safety cap on top.
enum HQPosterDiskCache {
    /// UserDefaults key shared with the Settings picker (@AppStorage).
    static let limitKey = "hq.poster.disk.cache.limitMB"
    static let limitChoicesMB = [50, 100, 150, 300, 500, 1000]
    static let defaultLimitMB = 150
    private static let safetyMaxFiles = 10000
    private static let lock = NSLock()
    private static var cachedDirectory: URL?

    /// Effective cache size limit in MB. Writing applies the new limit
    /// immediately (trims to it), mirroring AICoverDiskCache's cap.
    static var limitMB: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: limitKey)
            return limitChoicesMB.contains(stored) ? stored : defaultLimitMB
        }
        set {
            UserDefaults.standard.set(newValue, forKey: limitKey)
            evictIfNeeded()
        }
    }

    static func trimNow() { evictIfNeeded() }

    /// Current on-disk usage for the Settings row.
    static func usage() -> (bytes: Int, files: Int) {
        guard let dir = directoryURL(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return (0, 0) }
        var total = 0
        for url in files {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
        return (total, files.count)
    }

    static func isCacheable(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return ListHQCoverCache.isHQHost(url)
    }

    private static func directoryURL() -> URL? {
        lock.lock(); defer { lock.unlock() }
        if let cachedDirectory { return cachedDirectory }
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("HQPosterImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cachedDirectory = dir
        return dir
    }

    private static func fileURL(forKey key: String) -> URL? {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directoryURL()?.appendingPathComponent(digest + ".jpg")
    }

    static func image(forKey key: String) -> UIImage? {
        guard let file = fileURL(forKey: key),
              let data = try? Data(contentsOf: file),
              let image = PosterJPEGColor.image(from: data) else { return nil }
        // Touch so eviction stays least-recently-used.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return image
    }

    static func store(_ image: UIImage, forKey key: String) {
        guard let file = fileURL(forKey: key),
              let data = PosterJPEGColor.data(image, quality: 0.88) else { return }
        try? data.write(to: file, options: .atomic)
        evictIfNeeded()
    }

    static func removeAll() {
        guard let dir = directoryURL() else { return }
        try? FileManager.default.removeItem(at: dir)
        lock.lock(); cachedDirectory = nil; lock.unlock()
    }

    private static func evictIfNeeded() {
        guard let dir = directoryURL(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        var entries: [(url: URL, size: Int, modified: Date)] = files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }
        let limitBytes = limitMB * 1024 * 1024
        var total = entries.reduce(0) { $0 + $1.size }
        guard entries.count > safetyMaxFiles || total > limitBytes else { return }
        entries.sort { $0.modified < $1.modified }
        while entries.count > safetyMaxFiles || total > limitBytes, let victim = entries.first {
            entries.removeFirst()
            if (try? FileManager.default.removeItem(at: victim.url)) != nil { total -= victim.size }
        }
    }
}

#if !HOME_HQ_SIMULATOR
/// Build 303: light HQ prefetch for home / lists — first ~2 screens when data
/// arrives, then a few cards ahead while scrolling. Uses the same bounded
/// VisibleHQ path (one candidate, Plan A crop, junk rejection) and warms the
/// *cell-sized* HQPosterDiskCache key so the next launch paints HQ from disk
/// without re-decoding the full DMM/MGS original. Does not call DetailPosterResolver
/// or touch Cloudflare R2. Low Power Mode skips the batch.
enum HomeHQPosterPrefetch {
    /// ~2 screens of a 3-column phone grid (8 rows × 3).
    static let firstScreens = 24
    /// Cards ahead of the last appeared index while scrolling.
    static let aheadCount = 9
    private static let lock = NSLock()
    private static var aheadTask: Task<Void, Never>?
    private static var aheadToken = 0

    /// Warm the first screens when a list / home payload arrives.
    /// `account` kept for call-site compatibility; unused (no detail discovery).
    @discardableResult
    static func prefetch(_ movies: [Movie], account: String? = nil) async -> Bool {
        await warm(Array(movies.prefix(firstScreens)))
    }

    /// Coalesced scroll-ahead: warm a few items after `index` in `movies`.
    static func scheduleAhead(movies: [Movie], around index: Int) {
        guard upgradesAllowed, index >= 0, !movies.isEmpty else { return }
        let start = min(movies.count, index + 1)
        let end = min(movies.count, start + aheadCount)
        guard start < end else { return }
        let slice = Array(movies[start..<end])
        lock.lock()
        aheadToken += 1
        let token = aheadToken
        aheadTask?.cancel()
        aheadTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            lock.lock(); let current = aheadToken; lock.unlock()
            guard current == token else { return }
            _ = await warm(slice)
        }
        lock.unlock()
    }

    private static var upgradesAllowed: Bool {
        !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private static func warm(_ movies: [Movie]) async -> Bool {
        guard upgradesAllowed else { return false }
        let pixels = VisibleHQPosterPolicy.listPrefetchPixels
        var seen = Set<String>()
        var pending: [(Movie, String)] = []
        for movie in movies {
            guard let number = movie.number, !number.isEmpty,
                  seen.insert(number).inserted,
                  !ListHQCoverCache.isNegative(number: number),
                  let url = VisibleHQPosterPolicy.upgradeURL(movie: movie) else { continue }
            pending.append((movie, url))
        }
        guard !pending.isEmpty else { return false }
        var learned = false
        // Run through the same scheduler so Wi‑Fi/cellular caps + cancel semantics apply.
        await withTaskGroup(of: Bool.self) { group in
            for (movie, url) in pending {
                group.addTask {
                    if Task.isCancelled { return false }
                    let image = await VisibleHQPosterScheduler.shared.upgrade(
                        movie: movie, url: url, maxPixelSize: pixels)
                    return image != nil
                }
            }
            for await hit in group {
                if hit { learned = true }
            }
        }
        return learned
    }
}
#endif

/// Build 329: start immediate list-thumb / JavDBImage loads when home data
/// returns, in section order. This is not VisibleHQ disk warm — it fetches the
/// DTO cover/thumb so a fast scroll to 我的關注 does not flash film icons on
/// cards that already have a URL. VisibleHQ stays on the 2/5 scheduler.
enum HomeRailThumbPreheat {
    static let cap = 9
    static let maxPixelSize = 900

    @discardableResult
    static func preheat(_ movies: [Movie]) async -> Int {
        var loaded = 0
        for movie in movies.prefix(cap) {
            if Task.isCancelled { break }
            guard let url = ListCoverPolicy.sources(movie: movie).first, !url.isEmpty else { continue }
            if let image = await ImageLoader.shared.load(url, maxPixelSize: maxPixelSize, timeout: 8) {
                loaded += 1
                _ = image
            }
        }
        return loaded
    }

    /// Preheat several home sections in the given order (往期推薦, 最新上架,
    /// 近期磁鏈更新, 我的關注). Starts each section without waiting for the
    /// previous section to fully finish, but enqueues earlier sections first.
    @discardableResult
    static func preheat(sections: [[Movie]]) async -> Int {
        var total = 0
        await withTaskGroup(of: Int.self) { group in
            for movies in sections where !movies.isEmpty {
                group.addTask { await preheat(movies) }
                // Yield so earlier sections start their first requests first.
                await Task.yield()
            }
            for await count in group { total += count }
        }
        return total
    }
}

/// Build 329 rail floor: 360 px is a preference among candidates, never a
/// discard gate. A 147×200 JavDB / pics.dmm thumb is a legal floor image.
enum RailCoverFloor {
    static let minWidth = 360

    static func pixelWidth(_ image: UIImage) -> Int {
        image.cgImage?.width ?? Int((image.size.width * image.scale).rounded())
    }

    static func pixelHeight(_ image: UIImage) -> Int {
        image.cgImage?.height ?? Int((image.size.height * image.scale).rounded())
    }

    /// VisibleHQ still uses this to refuse a sub-360 "upgrade". The rail *floor*
    /// path must not call this — use `prefers` instead.
    static func rejects(source: String, image: UIImage) -> Bool {
        let width = pixelWidth(image)
        let height = pixelHeight(image)
        if width < minWidth { return true }
        if width == 147 && height == 200 && source.contains("pics.dmm.co.jp") { return true }
        if let url = URL(string: source), url.host?.lowercased() == "pics.dmm.co.jp",
           url.path.lowercased().hasSuffix("ps.jpg") { return true }
        return false
    }

    /// Among already-decoded floor candidates, prefer ≥360 when one exists,
    /// otherwise the wider raster. Never discards the only available image.
    static func prefers(_ incoming: UIImage, source incomingSource: String,
                        to current: UIImage, currentSource: String) -> Bool {
        let inW = pixelWidth(incoming)
        let curW = pixelWidth(current)
        let inOK = inW >= minWidth
        let curOK = curW >= minWidth
        if inOK != curOK { return inOK }
        return inW > curW
    }
}

/// Rail / list placeholder policy. film.stack only when no cover or thumb URL
/// exists at all. A URL that failed to load is a gray field with tap-to-retry,
/// never an infinite film icon with no affordance.
enum RailPosterPlaceholder {
    enum Kind: String, Equatable {
        case filmIcon
        case retry
        case loading
    }

    static func kind(hasURL: Bool, failed: Bool) -> Kind {
        if !hasURL { return .filmIcon }
        if failed { return .retry }
        return .loading
    }
}

/// List thumbnails: HQ first (resolved Amazon/DMM/MGS/avbase catalogue pl), then JavDB.
/// No per-row Tenhow scrape; ImageLoader rejects DMM NOW thumbs and falls back.
public enum ListCoverPolicy {
    public static func sources(movie: Movie) -> [String] {
        let original = FrontPosterPolicy.usesOriginal(type: movie.type, number: movie.number)
        var javdb = FrontPosterPolicy.sources(thumb: movie.thumbURL, cover: movie.coverURL, original: original)
        // List thumbnails only: FrontPosterPolicy keeps original-artwork types
        // thumb-first for detail display, but in grids the 147x200 small_cover
        // upscales badly. When JavDB pairs it with a recognized 800x538 jacket,
        // lead with the jacket — MoviePosterImage crops its front (about
        // 376x538) and the thumb stays as fallback. Non-jacket covers and
        // detail-page ordering are untouched.
        if original, let cover = movie.coverURL,
           FrontPosterPolicy.isKnownWrap(cover),
           let index = javdb.firstIndex(of: cover), index > 0 {
            javdb.remove(at: index)
            javdb.insert(cover, at: 0)
        }
        var result: [String] = []
        func append(_ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { return }
            result.append(trimmed)
        }
        if !original, let learned = ListHQCoverCache.url(for: movie.number) {
            append(learned)
        }
        // Build 298: guessed DMM / catalogue full-size URLs are not fetched for every
        // cell. VisibleHQPosterUpgrade requests one safe candidate only while the card
        // is on screen. The existing thumb/cover always paints first.
        for source in javdb { append(source) }
        return result
    }
}

/// Shared by all movie lists; no gestures or detail fetches.
public struct MoviePosterImage: View {
    let movie: Movie
    var maxPixelSize: Int = 1200
    /// Build 300: every poster cell upgrades to HD once visible (opt out for blurred backdrops).
    var upgradesVisibleHQ = true

    public var body: some View {
        let original = FrontPosterPolicy.usesOriginal(type: movie.type, number: movie.number)
        let sources = ListCoverPolicy.sources(movie: movie)
        // Poster loading also when an original-artwork card leads with a
        // recognized jacket (the ListCoverPolicy reorder above): loadPoster
        // only crops known wraps / DMM jackets and passes other sources through.
        let wrapLead = sources.first.map(FrontPosterPolicy.isKnownWrap) == true
        JavDBImage(url: sources.first,
                   fallbackURL: sources.dropFirst().first,
                   secondFallbackURL: sources.dropFirst(2).first,
                   contentMode: .fill, maxPixelSize: maxPixelSize, frontPoster: !original || wrapLead, fitUncroppedLandscape: true)
            .overlay {
                if upgradesVisibleHQ, !original || movie.catalogueMetadata?.poster != nil {
                    VisibleHQPosterUpgrade(movie: movie)
                }
            }
    }
}

#if !HOME_HQ_SIMULATOR
// Simulator host has no GlassChip / ClippedAspectFill. Production still compiles these.
/// Paints nothing until a visible-card upgrade succeeds. Leaving the screen
/// cancels the task; the small image underneath is never cleared or enlarged.
struct VisibleHQPosterUpgrade: View {
    let movie: Movie
    @State private var upgraded: UIImage?
    @State private var identity: String?

    var body: some View {
        GeometryReader { geometry in
            let pixels = VisibleHQPosterPolicy.targetPixels(displayPoints: geometry.size, scale: UIScreen.main.scale)
            Color.clear
                .overlay {
                    if let upgraded, identity == requestIdentity(pixels) {
                        Image(uiImage: upgraded)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .clipped()
                .allowsHitTesting(false)
                .task(id: requestIdentity(pixels)) {
                    let current = requestIdentity(pixels)
                    // Policy lookup runs in the task, not in every body/layout pass.
                    guard let url = VisibleHQPosterPolicy.upgradeURL(movie: movie) else { return }
                    let image = await VisibleHQPosterScheduler.shared.upgrade(movie: movie, url: url, maxPixelSize: pixels)
                    guard !Task.isCancelled, let image else { return }
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        upgraded = image
                        identity = current
                    }
                }
        }
        .allowsHitTesting(false)
    }

    private func requestIdentity(_ pixels: Int) -> String {
        movie.id + "#" + (movie.number ?? "") + "#\(pixels)"
    }
}
/// 封面卡片（带番号 + 评分角标）
public struct MovieCoverCard: View {
    let movie: Movie
    let width: CGFloat

    public init(movie: Movie, width: CGFloat = 120) {
        self.movie = movie
        self.width = width
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                MoviePosterImage(movie: movie, maxPixelSize: 900)
                    .frame(width: width, height: width / 0.7)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .glassMediaFrame(cornerRadius: 10)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if let score = movie.score, score > 0 {
                    GlassChip(
                        text: String(format: "%.1f", score),
                        tint: .orange,
                        font: .caption2.bold(),
                        foreground: .white,
                        compact: true,
                        tintStrength: 0.68
                    )
                    .padding(4)
                }
            }

            Text(movie.displayNumber)
                .font(.caption).bold()
                .lineLimit(1)

            Text(movie.displayTitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }
}

#if DEBUG
/// Neutral image bounds fixture; no network, credentials or adult imagery.
struct PosterSizeRegressionGallery: View {
    private let fixtures: [(String, String, String)] = [
        ("0", "IPX-247", "portrait"), ("0", "SSIS-001", "wrap"),
        ("1", "HEYZO-3953", "wide"), ("2", "Tushy.2026.10.11", "square"),
        ("3", "FC2-PPV-1234567", "wrap"), ("1", "NEUTRAL", "portrait")
    ]
    var body: some View {
        LazyVGrid(columns: [GridItem(.fixed(140)), GridItem(.fixed(140))], spacing: 12) {
            ForEach(fixtures.indices, id: \.self) { i in
                let f = fixtures[i]
                ClippedAspectFill(aspectRatio: 0.7) {
                    MoviePosterImage(movie: Movie(id: "neutral-\(i)", type: f.0, number: f.1,
                        thumbURL: "fixture://poster/\(f.2)", coverURL: "fixture://poster/wrap"))
                        .overlay(alignment: .topTrailing) { Text("\(i)").padding(4).background(.orange) }
                }
                .frame(width: 140)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Neutral poster \(i)")
                .accessibilityIdentifier("uniform-poster-\(i)")
            }
        }
        .padding()
    }
}
#endif
#endif
