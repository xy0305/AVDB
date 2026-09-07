//
//  ImageLoader.swift
//  AVDB
//
//  图片加载器：下载 CDN 加密流并解密后显示。
//  支持缓存，避免重复请求。
//

import Foundation
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

/// 图片加载器（单例，带内存 + 磁盘缓存）
@MainActor
public final class ImageLoader: ObservableObject {
    public static let shared = ImageLoader()

    @Published private var cache: [String: UIImage] = [:]

    private let cacheLimit = 300
    private let userAgent = "Mozilla/5.0 (Linux; Android 13; javdb)"

    private init() {}

    /// 获取图片（自动判断是否需要解密）
    public func load(_ urlString: String?) async -> UIImage? {
        guard let urlString = urlString, !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }

        // 命中缓存
        if let img = cache[urlString] {
            return img
        }

        do {
            let image: UIImage
            if isEncryptedCDN(urlString) {
                let encrypted = try await download(url)
                let decrypted = JavDBSignature.decryptImage(encrypted)
                guard let img = UIImage(data: decrypted) else {
                    throw ImageLoaderError.decryptFailed
                }
                image = img
            } else {
                let data = try await download(url)
                guard let img = UIImage(data: data) else {
                    throw ImageLoaderError.invalidData
                }
                image = img
            }

            // DMM/MGS 某些地址会返回通用 NOW 占位图：ps 为 147x200，
            // pl 为 590x800。pl 本应是横版剧照，因此竖向 pl 也必须判无效。
            if isExternalCover(urlString) {
                let tooSmall = max(image.size.width, image.size.height) < 500
                let portraitBackdrop = urlString.lowercased().hasSuffix("pl.jpg")
                    && image.size.height > image.size.width
                if tooSmall || portraitBackdrop { throw ImageLoaderError.invalidData }
            }
            cache[urlString] = image
            if cache.count > cacheLimit {
                cache.removeAll()
            }
            return image
        } catch {
            return nil
        }
    }

    private func isExternalCover(_ urlString: String) -> Bool {
        urlString.contains("pics.dmm.co.jp") || urlString.contains("image.mgstage.com")
    }

    /// 判断是否为 App 专用加密 CDN（tp.spfcas.com）
    private func isEncryptedCDN(_ urlString: String) -> Bool {
        return urlString.contains(JavDBConstants.imageCDNHost)
    }

    private func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ImageLoaderError.downloadFailed
        }
        return data
    }

    /// 清空缓存
    public func clearCache() {
        cache.removeAll()
    }
}

/// AsyncImage 封装：自动处理 JAVDB 加密 CDN；可选优先加载高清源并回退。
public struct JavDBImage: View {
    let url: String?
    var fallbackURL: String? = nil
    var secondFallbackURL: String? = nil
    let contentMode: ContentMode

    @State private var image: UIImage?
    @State private var loading = false

    public init(
        url: String?,
        fallbackURL: String? = nil,
        secondFallbackURL: String? = nil,
        contentMode: ContentMode = .fill
    ) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.secondFallbackURL = secondFallbackURL
        self.contentMode = contentMode
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
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: imageURLs.joined(separator: "|")) {
            // task(id:) 在候选 URL 改变时会取消旧任务；不能用 loading 拦截，
            // 否则 Tenhow poster 稍晚解析完成时会继续显示先加载到的横版 thumb。
            loading = true
            image = nil
            for candidate in imageURLs {
                guard !Task.isCancelled else { return }
                if let img = await ImageLoader.shared.load(candidate) {
                    guard !Task.isCancelled else { return }
                    image = img
                    break
                }
            }
            loading = false
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.systemGray6)
            Image(systemName: "film")
                .foregroundColor(.gray)
        }
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
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                if let score = movie.score, score > 0 {
                    Text(String(format: "%.1f", score))
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
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
    }
}
