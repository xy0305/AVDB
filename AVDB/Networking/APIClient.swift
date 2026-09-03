//
//  APIClient.swift
//  AVDB
//
//  JAVDB HTTP 客户端：负责签名、鉴权头、统一响应包裹解析。
//

import Foundation

/// 统一响应包裹结构
public struct JavDBResponse<T: Decodable>: Decodable {
    public let success: Int
    public let action: String?
    public let message: String?
    public let data: T?

    public var isSuccess: Bool { success == 1 }
}

/// 空数据占位（某些接口 data 为 null）
public struct EmptyData: Decodable {}

/// API 错误
public enum JavDBError: Error, LocalizedError {
    case invalidURL
    case httpError(Int, String)
    case apiError(action: String?, message: String?)
    case decodeError(String)
    case notLoggedIn
    case invalidSignature

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 URL"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .apiError(_, let message): return message ?? "请求失败"
        case .decodeError(let msg): return "解析失败: \(msg)"
        case .notLoggedIn: return "需要登录"
        case .invalidSignature: return "签名校验失败"
        }
    }
}

/// JAVDB HTTP 客户端
public final class APIClient: @unchecked Sendable {
    public static let shared = APIClient()

    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (Linux; Android 13; javdb)"

    /// 当前登录 token（JWT）
    public private(set) var token: String?
    private let tokenLock = NSLock()

    /// 当前登录用户
    @MainActor public var currentUser: User?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: config)
    }

    // MARK: - Token 管理

    public func setToken(_ token: String?) {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        self.token = token
    }

    public var hasToken: Bool {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        return token != nil
    }

    // MARK: - 基础请求

    /// 构造完整 URL（自动附加必带 query 参数）
    public func makeURL(path: String, query: [String: String]? = nil) -> URL? {
        var comps = URLComponents(string: JavDBConstants.baseURL + path)
        var items = JavDBConstants.baseQuery.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let q = query {
            for (k, v) in q {
                items.append(URLQueryItem(name: k, value: v))
            }
        }
        comps?.queryItems = items
        return comps?.url
    }

    /// 发送 GET 请求并解码
    public func get<T: Decodable>(
        _ path: String,
        query: [String: String]? = nil,
        useToken: Bool = false
    ) async throws -> T {
        guard let url = makeURL(path: path, query: query) else {
            throw JavDBError.invalidURL
        }
        return try await request(url: url, method: "GET", useToken: useToken)
    }

    /// 发送 POST 请求并解码（application/x-www-form-urlencoded）
    public func post<T: Decodable>(
        _ path: String,
        form: [String: String],
        useToken: Bool = false
    ) async throws -> T {
        guard let url = makeURL(path: path, query: nil) else {
            throw JavDBError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        return try await perform(request: request, useToken: useToken)
    }

    /// 以表单/JSON 混合优先，直接请求
    private func request<T: Decodable>(
        url: URL,
        method: String,
        useToken: Bool
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        return try await perform(request: request, useToken: useToken)
    }

    private func perform<T: Decodable>(request: URLRequest, useToken: Bool) async throws -> T {
        var req = request
        appendHeaders(to: &req, useToken: useToken)
        let (data, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 400 {
                // 400 多为 InvalidSignature 或 ParameterInvalid
                if let err = try? decode(JavDBResponse<EmptyData>.self, from: data) {
                    throw JavDBError.apiError(action: err.action, message: err.message)
                }
            } else if http.statusCode == 404 {
                throw JavDBError.apiError(action: "ResourceNotFound", message: "资源不存在")
            } else if http.statusCode >= 500 {
                throw JavDBError.httpError(http.statusCode, "服务器错误")
            }
        }

        return try decode(T.self, from: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            // 尝试解析多种日期格式
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                "yyyy-MM-dd'T'HH:mm:ssZ",
                "yyyy-MM-dd",
            ]
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            for f in formats {
                formatter.dateFormat = f
                if let d = formatter.date(from: raw) {
                    return d
                }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解析日期: \(raw)")
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw JavDBError.decodeError(error.localizedDescription)
        }
    }

    private func appendHeaders(to request: inout URLRequest, useToken: Bool) {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(JavDBSignature.make(), forHTTPHeaderField: "jdsignature")
        request.setValue("zh-CN", forHTTPHeaderField: "accept-language")
        request.setValue("keep-alive", forHTTPHeaderField: "connection")
        if useToken {
            tokenLock.lock()
            let t = token
            tokenLock.unlock()
            if let t = t {
                request.setValue("Bearer \(t)", forHTTPHeaderField: "authorization")
            }
        }
    }
}
