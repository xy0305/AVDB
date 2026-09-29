//
//  ImageLoader.swift
//  AVDB
//
//  图片加载器：下载 CDN 加密流并解密后显示。
//  支持缓存，避免重复请求。
//

import Foundation
import ImageIO
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

        // DMM 默认
        let poster = "https://pics.dmm.co.jp/digital/video/\(code)/\(code)ps.jpg"
        let backdrop = "https://pics.dmm.co.jp/digital/video/\(code)/\(code)pl.jpg"
        return (poster, backdrop)
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

/// 图片加载器（单例）：后台解密/降采样、请求合并、按内存压力自动淘汰。
public actor ImageLoader {
    public static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let userAgent = "Mozilla/5.0 (Linux; Android 13; javdb)"

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 192 * 1024 * 1024
    }

    /// 获取图片（自动判断是否需要解密）
    public func load(_ urlString: String?, maxPixelSize: Int = 2048) async -> UIImage? {
        guard let urlString = urlString, !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }
        let pixelSize = max(320, maxPixelSize)
        let cacheKey = "\(urlString)#\(pixelSize)" as NSString
        if let img = cache.object(forKey: cacheKey) {
            return img
        }

        let flightKey = "\(urlString)#\(pixelSize)"
        if let task = inFlight[flightKey] {
            return await task.value
        }

        let task = Task.detached(priority: .utility) { [userAgent] in
            await Self.fetchImage(url: url, urlString: urlString, userAgent: userAgent, maxPixelSize: pixelSize)
        }
        inFlight[flightKey] = task
        let image = await task.value
        inFlight[flightKey] = nil

        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
            cache.setObject(image, forKey: cacheKey, cost: cost)
        }
        return image
    }

    private static func isExternalCover(_ urlString: String) -> Bool {
        urlString.contains("pics.dmm.co.jp") || urlString.contains("image.mgstage.com")
    }

    /// 判断是否为 App 专用加密 CDN（tp.spfcas.com）
    private static func isEncryptedCDN(_ urlString: String) -> Bool {
        return urlString.contains(JavDBConstants.imageCDNHost)
    }

    private static func fetchImage(url: URL, urlString: String, userAgent: String, maxPixelSize: Int) async -> UIImage? {
        do {
            let downloaded = try await download(url, userAgent: userAgent)
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

    private static func download(_ url: URL, userAgent: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ImageLoaderError.downloadFailed
        }
        return data
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
    }
}

/// AsyncImage 封装：自动处理 JAVDB 加密 CDN；可选优先加载高清源并回退。
public struct JavDBImage: View {
    let url: String?
    var fallbackURL: String? = nil
    var secondFallbackURL: String? = nil
    let contentMode: ContentMode
    let maxPixelSize: Int

    @State private var image: UIImage?

    public init(
        url: String?,
        fallbackURL: String? = nil,
        secondFallbackURL: String? = nil,
        contentMode: ContentMode = .fill,
        maxPixelSize: Int = 2048
    ) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.secondFallbackURL = secondFallbackURL
        self.contentMode = contentMode
        self.maxPixelSize = maxPixelSize
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
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    placeholder
                }
            }
            .clipped()
            .task(id: imageURLs.joined(separator: "|")) {
            // 不先清空 image。LazyVGrid 滚动时 task 会被取消，先清空会让中间封面变空白。
            for candidate in imageURLs {
                guard !Task.isCancelled else { return }
                if let img = await ImageLoader.shared.load(candidate, maxPixelSize: maxPixelSize) {
                    guard !Task.isCancelled else { return }
                    image = img
                    return
                }
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemGray6), Color(.systemGray5).opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.42))
                .frame(width: 48, height: 48)
            Image(systemName: "film.stack")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
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
                JavDBImage(url: movie.coverURL ?? movie.thumbURL)
                    .frame(width: width, height: width * 1.4)
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
