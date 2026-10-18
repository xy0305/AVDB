import Foundation

/// Read-only label for the source URL already chosen by the existing winner.
/// It never selects, downloads, caches, or forwards a token.
enum CoverSourceDisplay {
    struct Label: Equatable, Sendable {
        let name: String
        /// Safe URL without query, fragment, user, or password. Copy uses this.
        let copyText: String
        let truncated: Bool
        var line: String { "封面来源：" + name }
        var accessibility: String { "封面来源：" + name + "，" + copyText }
    }

    static let pending = "封面来源：正在选择"
    static let unavailable = "封面来源：未找到更优封面"

    /// Positive winner only. Nil means hide — never invent a source.
    static func label(sourceURL: String?) -> Label? {
        guard let sourceURL, !sourceURL.isEmpty, let url = URL(string: sourceURL),
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        let name = name(host: host, path: url.path)
        let safe = safeURL(url)
        let shown = safe.count > 48 ? String(safe.prefix(45)) + "…" : safe
        return Label(name: name, copyText: safe, truncated: shown != safe)
    }

    static func name(host: String, path: String) -> String {
        let host = host.lowercased()
        let path = path.lowercased()
        if host == "tp.spfcas.com" || host == "c0.jdbstatic.com" || host.contains("javdb") { return "JavDB" }
        if host == "cdn.theporndb.net" || host == "api.theporndb.net" || host.contains("theporndb") { return "ThePornDB" }
        if host == "cdn.blackedraw.com" || host.contains("blackedraw") { return "片商主图" }
        if host == "cdn.dt18.com" || host == "bdn.dt18.com" || host.contains("data18") { return "Data18" }
        if host == "www.tenhow.net" || host.contains("tenhow") { return "Tenhow" }
        if host.contains("amazon.") || host.hasSuffix("amazon.com") || host.hasSuffix("media-amazon.com") { return "日亚" }
        if host.contains("dmm.co.jp") || host.contains("dmm.com") { return "DMM" }
        if host == "image.mgstage.com" { return path.contains("/pf_e_") ? "MGS" : "MGStage" }
        if host.contains("mgstage") { return "MGStage" }
        return "其他 " + host
    }

    /// Drop credentials and every query/fragment, including tokens.
    static func safeURL(_ url: URL) -> String {
        var parts = URLComponents()
        parts.scheme = url.scheme
        parts.host = url.host
        if let port = url.port { parts.port = port }
        parts.path = url.path
        return parts.string ?? (url.host ?? "")
    }
}
