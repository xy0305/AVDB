import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // Linux test host only
#endif

// Build 313: 中指通 (YouTube @fingermaster56) 每月作品精選 as a ranking source.
// Only codes recorded in the bundled/remote JSON are shown; nothing is guessed at runtime.
// Covers/details always come from the normal AVDB exact-code lookup (MissAVMetadata),
// so image quality, caching and the ImageLoader pipeline are untouched.
struct ZZTEntry: Codable, Hashable {
    let code: String
    let actresses: [String]
    let note: String?
}

struct ZZTMonth: Codable, Hashable, Identifiable {
    let month: String          // YYYY-MM (the month the picks cover)
    let title: String
    let video: String?         // YouTube watch URL of the monthly video
    let source: String?        // where the code list was read
    let sourceType: String     // "forum_list" | "youtube_transcript" | "video_title"
    let entries: [ZZTEntry]
    var id: String { month }
    enum CodingKeys: String, CodingKey {
        case month, title, video, source, entries
        case sourceType = "source_type"
    }
    var label: String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]) else { return month }
        return "\(parts[0]) 年 \(m) 月"
    }
    var year: String { String(month.prefix(4)) }
    var monthLabel: String {
        guard let m = Int(month.suffix(2)) else { return month }
        return "\(m) 月"
    }
}

/// Build 314: history back-filled, so the picker groups months by year (newest year first).
struct ZZTYear: Hashable, Identifiable {
    let year: String
    let months: [ZZTMonth]   // newest first
    var id: String { year }
    var label: String { "\(year) 年" }
}

struct ZZTCatalog: Codable, Equatable {
    let version: Int
    let updatedAt: String      // ISO date, compared lexicographically
    let months: [ZZTMonth]
    enum CodingKeys: String, CodingKey {
        case version, months
        case updatedAt = "updated_at"
    }

    /// Months grouped by year; assumes `months` is newest first (decode guarantees it).
    var years: [ZZTYear] {
        var order: [String] = []
        var buckets: [String: [ZZTMonth]] = [:]
        for month in months {
            if buckets[month.year] == nil { order.append(month.year) }
            buckets[month.year, default: []].append(month)
        }
        return order.map { ZZTYear(year: $0, months: buckets[$0] ?? []) }
    }

    static let fileName = "ZhongZhiTongMonthly"
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/xy0305/AVDB/main/AVDB/Resources/ZhongZhiTongMonthly.json")!
    static let maxBytes = 2_000_000

    static func isValidCode(_ code: String) -> Bool {
        code.range(of: #"^[0-9]{0,3}[A-Z]{2,8}-[0-9]{2,6}$"#, options: .regularExpression) != nil
    }
    static func isValidMonth(_ month: String) -> Bool {
        month.range(of: #"^20[0-9]{2}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil
    }

    /// Strict decode: schema version, month format, code format, no duplicate months.
    /// Months come back newest first; entry order (the video's order) is preserved.
    static func decode(_ data: Data) throws -> ZZTCatalog {
        guard data.count <= maxBytes else { throw ZZTError.tooLarge }
        let raw = try JSONDecoder().decode(ZZTCatalog.self, from: data)
        guard raw.version == 1, !raw.months.isEmpty else { throw ZZTError.schema }
        guard Set(raw.months.map(\.month)).count == raw.months.count else { throw ZZTError.schema }
        for month in raw.months {
            guard isValidMonth(month.month), !month.entries.isEmpty,
                  month.entries.allSatisfy({ isValidCode($0.code) }) else { throw ZZTError.schema }
        }
        return ZZTCatalog(version: raw.version, updatedAt: raw.updatedAt,
                          months: raw.months.sorted { $0.month > $1.month })
    }

    /// Remote wins only when it is valid and at least as new as what we already have.
    static func preferred(_ current: ZZTCatalog?, _ candidate: ZZTCatalog?) -> ZZTCatalog? {
        guard let candidate else { return current }
        guard let current else { return candidate }
        if candidate.updatedAt > current.updatedAt { return candidate }
        if candidate.updatedAt == current.updatedAt && candidate.months.count > current.months.count { return candidate }
        return current
    }
}

enum ZZTError: LocalizedError {
    case schema, tooLarge, missingBundle
    var errorDescription: String? {
        switch self {
        case .schema: return "中指通榜单资料格式不正确"
        case .tooLarge: return "中指通榜单资料过大"
        case .missingBundle: return "安装包内缺少中指通榜单资料"
        }
    }
}

/// Bundled copy first (works offline), then a cached remote copy, then a fresh remote fetch.
/// A failed/invalid remote never replaces a good catalog.
final class ZZTCatalogStore {
    typealias Fetcher = (URL) async throws -> Data
    private let bundledData: () -> Data?
    private let cacheFile: URL
    private let fetcher: Fetcher

    init(bundledData: @escaping () -> Data? = { ZZTCatalogStore.bundleData() },
         cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ZhongZhiTong313"),
         fetcher: @escaping Fetcher = ZZTCatalogStore.network) {
        self.bundledData = bundledData
        self.cacheFile = cacheDirectory.appendingPathComponent("catalog.json")
        self.fetcher = fetcher
    }

    static func bundleData() -> Data? {
        guard let url = Bundle.main.url(forResource: ZZTCatalog.fileName, withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    static func network(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// Local only (bundle + cache). Never touches the network.
    func local() -> ZZTCatalog? {
        let bundled = bundledData().flatMap { try? ZZTCatalog.decode($0) }
        let cached = (try? Data(contentsOf: cacheFile)).flatMap { try? ZZTCatalog.decode($0) }
        return ZZTCatalog.preferred(bundled, cached)
    }

    /// Returns the best catalog and whether the remote refresh succeeded.
    func refresh(current: ZZTCatalog?) async -> (catalog: ZZTCatalog?, remoteOK: Bool) {
        do {
            let data = try await fetcher(ZZTCatalog.remoteURL)
            let remote = try ZZTCatalog.decode(data)
            let best = ZZTCatalog.preferred(current, remote)
            if best == remote {
                try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheFile, options: .atomic)
            }
            return (best, true)
        } catch {
            return (current, false)
        }
    }
}
