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

            cache[urlString] = image
            if cache.count > cacheLimit {
                cache.removeAll()
            }
            return image
        } catch {
            return nil
        }
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
    let contentMode: ContentMode

    @State private var image: UIImage?
    @State private var loading = false

    public init(url: String?, fallbackURL: String? = nil, contentMode: ContentMode = .fill) {
        self.url = url
        self.fallbackURL = fallbackURL
        self.contentMode = contentMode
    }

    private var imageURLs: [String] {
        var result: [String] = []
        if let url, !url.isEmpty { result.append(url) }
        if let fallbackURL, !fallbackURL.isEmpty, !result.contains(fallbackURL) {
            result.append(fallbackURL)
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
                    .task {
                        guard !loading else { return }
                        loading = true
                        for candidate in imageURLs {
                            if let img = await ImageLoader.shared.load(candidate) {
                                image = img
                                break
                            }
                        }
                        loading = false
                    }
            }
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
