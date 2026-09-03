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

/// AsyncImage 封装：自动处理 JAVDB 加密 CDN
public struct JavDBImage: View {
    let url: String?
    let contentMode: ContentMode

    @State private var image: UIImage?
    @State private var loading = false

    public init(url: String?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
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
                        guard !loading, let u = url else { return }
                        loading = true
                        image = await ImageLoader.shared.load(u)
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
