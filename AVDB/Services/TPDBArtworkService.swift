import Foundation
import UIKit
import ImageIO

private final class TPDBRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let authenticated: Bool
    private var count = 0
    init(authenticated: Bool) { self.authenticated = authenticated }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        count += 1
        guard let url = request.url, TPDBPolicy.permitsRedirect(authenticated: authenticated, count: count, target: url),
              let clean = TPDBPolicy.request(url, token: nil, timeout: request.timeoutInterval) else {
            completionHandler(nil); return
        }
        completionHandler(clean)
    }
}

struct TPDBLandscape: @unchecked Sendable {
    let image: UIImage
    let width: Int
    let height: Int
    var label: String { "封面来源：ThePornDB · \(width) × \(height)" }
}

/// Separate budget and cache. Never participates in Japanese DVD front scoring.
enum TPDBArtworkService {
    private static let cache = DetailPosterCache<TPDBLandscape>(positiveTTL: 300, negativeTTL: 30)
    static func clear() { cache.invalidate() }
    static func identity(_ movie: Movie) -> TPDBPolicy.Identity? {
        TPDBPolicy.identity(type: movie.type, number: movie.number, title: movie.originTitle ?? movie.title,
                            date: movie.releaseDate, minutes: movie.duration, official: movie.originalURL)
    }
    static func resolve(movie: Movie, namespace: String) async -> TPDBLandscape? {
        let settings = TPDBCoverSettings.shared.snapshot()
        guard settings.enabled, let token = settings.token, !token.isEmpty else { return nil }
        guard let identity = identity(movie) else {
            TPDBCoverSettings.shared.record("作品身份不完整或品牌不在范围内；保留 JavDB", generation: settings.namespace)
            return nil
        }
        let key = settings.namespace.uuidString + "#" + namespace + "#" + identity.title + "#" + identity.date + "#" + String(identity.seconds) + "#" + (identity.official ?? "")
        return await cache.value(key: key) {
            let deadline = ProcessInfo.processInfo.systemUptime + 12
            do {
                var components = URLComponents(string: "https://api.theporndb.net/scenes")!
                if let official = identity.official {
                    components.queryItems = [URLQueryItem(name: "url", value: official)]
                } else {
                    components.queryItems = [URLQueryItem(name: "title", value: identity.title),
                                             URLQueryItem(name: "site", value: TPDBPolicy.brands[identity.brand]),
                                             URLQueryItem(name: "date", value: identity.date)]
                }
                components.queryItems?.append(URLQueryItem(name: "per_page", value: "25"))
                let query = try await metadata(components.url!, token: token, deadline: deadline)
                guard let match = TPDBPolicy.uniqueQuery(query, identity), let uuid = match["id"] as? String else {
                    throw Failure.message("没有唯一且完全核对的作品；保留 JavDB")
                }
                let detail = try await metadata(URL(string: "https://api.theporndb.net/scenes/" + uuid)!, token: token, deadline: deadline)
                guard let verified = detail["data"] as? [String: Any], verified["id"] as? String == uuid,
                      TPDBPolicy.matches(verified, identity) else { throw Failure.message("UUID 详情身份冲突；保留 JavDB") }
                var best: TPDBLandscape?
                for url in TPDBPolicy.images(verified).prefix(2) {
                    try Task.checkCancellation()
                    guard TPDBCoverSettings.shared.namespace == settings.namespace else { return nil }
                    do {
                        let data = try await fetch(url, token: nil, deadline: deadline, limit: 8 * 1024 * 1024)
                        if let candidate = decode(data), best == nil || candidate.width * candidate.height > best!.width * best!.height { best = candidate }
                    } catch is CancellationError { throw CancellationError() }
                    catch { /* The other independently fetched original remains eligible. */ }
                }
                guard !Task.isCancelled, TPDBCoverSettings.shared.namespace == settings.namespace else { return nil }
                TPDBCoverSettings.shared.record(best.map { "作品身份核对通过；" + $0.label } ?? "原生横图不可用、超限或解码失败；保留 JavDB", generation: settings.namespace)
                return best
            } catch is CancellationError { return nil }
            catch let error as Failure {
                TPDBCoverSettings.shared.record(error.text, generation: settings.namespace); return nil
            } catch {
                TPDBCoverSettings.shared.record("网络中断、超时或 TLS 失败；未判断 Token 失效，保留 JavDB", generation: settings.namespace); return nil
            }
        }
    }
    enum Failure: Error {
        case message(String)
        var text: String { switch self { case .message(let value): return value } }
    }
    private static func metadata(_ url: URL, token: String, deadline: TimeInterval) async throws -> [String: Any] {
        let data = try await fetch(url, token: token, deadline: deadline, limit: 1024 * 1024)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.message("JSON 不完整或格式无效；保留 JavDB")
        }
        return object
    }
    private static func fetch(_ url: URL, token: String?, deadline: TimeInterval, limit: Int) async throws -> Data {
        guard token == nil ? TPDBPolicy.imageAllowed(url) : TPDBPolicy.apiAllowed(url) else { throw Failure.message("请求域名或协议被安全策略拒绝") }
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { throw Failure.message("12 秒预算已用完；保留 JavDB") }
        try Task.checkCancellation()
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = min(5, remaining); config.timeoutIntervalForResource = min(5, remaining)
        let session = URLSession(configuration: config, delegate: TPDBRedirectGuard(authenticated: token != nil), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        guard let request = TPDBPolicy.request(url, token: token, timeout: min(5, remaining)) else { throw Failure.message("请求身份或域名策略拒绝") }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.message("无效 HTTP 响应") }
        guard http.statusCode == 200 else { throw Failure.message(TPDBPolicy.status(http.statusCode)) }
        guard let final = response.url, token == nil ? TPDBPolicy.imageAllowed(final) : final == url,
              response.expectedContentLength <= limit else { throw Failure.message("响应地址或大小超限") }
        guard let mime = response.mimeType, token == nil ? mime.hasPrefix("image/") : mime == "application/json" else { throw Failure.message("响应类型不是预期 JSON / 图片") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit, ProcessInfo.processInfo.systemUptime < deadline else { throw Failure.message("响应大小或总时间超限") }
            data.append(byte)
        }
        guard TPDBPolicy.completeLength(actual: data.count, expected: response.expectedContentLength,
                                        encoding: http.value(forHTTPHeaderField: "Content-Encoding")) else { throw Failure.message("响应读取不完整；保留 JavDB") }
        return data
    }
    private static func decode(_ data: Data) -> TPDBLandscape? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = p[kCGImagePropertyPixelWidth] as? Int, let height = p[kCGImagePropertyPixelHeight] as? Int,
              width >= 640, height >= 360, width <= 8000, height <= 8000, width * height <= 20_000_000,
              Double(width) / Double(height) >= 1.3, Double(width) / Double(height) <= 2.2,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048,
                  kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return TPDBLandscape(image: UIImage(cgImage: image), width: width, height: height)
    }
}
