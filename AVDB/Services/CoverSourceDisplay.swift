import Foundation

struct CoverProvenance: Equatable, Sendable {
    let url: String
    let rawWidth: Int
    let rawHeight: Int
    let effectiveWidth: Int
    let effectiveHeight: Int
    var name: String { CoverSourceDisplay.name(host: URL(string: url)?.host ?? "") }
    var line: String {
        let native = rawWidth > 0 ? " · 原图 \(rawWidth)×\(rawHeight)" : ""
        return "封面来源：" + name + native + " · 有效 \(effectiveWidth)×\(effectiveHeight)"
    }
}
enum CoverSourceDisplay {
    static let pending = "封面来源：正在选择"
    static func safeURL(_ raw: String) -> String {
        guard var c = URLComponents(string: raw) else { return "" }
        c.user = nil; c.password = nil; c.query = nil; c.fragment = nil
        return c.string ?? ""
    }
    static func name(host: String) -> String {
        let h = host.lowercased()
        if ["tp.spfcas.com", "c0.jdbstatic.com"].contains(h) { return "JavDB" }
        if h == "cdn.theporndb.net" { return "ThePornDB" }
        if WesternCoverPolicy.sites.contains(where: { h == "cdn." + $0.key + ".com" }) { return "片商" }
        if ["cdn.dt18.com", "bdn.dt18.com", "www.data18.com"].contains(h) { return "Data18" }
        if h == "www.tenhow.net" { return "Tenhow" }
        if ["m.media-amazon.com", "images-na.ssl-images-amazon.com", "images-fe.ssl-images-amazon.com", "images.amazon.com"].contains(h) { return "日亚" }
        if ["pics.dmm.co.jp", "awsimgsrc.dmm.co.jp"].contains(h) { return "DMM" }
        if h == "image.mgstage.com" { return "MGStage" }
        return h.isEmpty ? "未加载" : h
    }
}
/// Evidence belongs to a successfully decoded load, not a resolver assumption.
final class CoverLoadEvidence: @unchecked Sendable {
    static let shared = CoverLoadEvidence()
    private let lock = NSLock(); private var items: [String: CoverProvenance] = [:]
    func save(request: String, final: URL, rawWidth: Int, rawHeight: Int, width: Int, height: Int) {
        lock.lock(); defer { lock.unlock() }
        if items.count > 256 { items.removeAll() }
        items[request] = CoverProvenance(url: CoverSourceDisplay.safeURL(final.absoluteString), rawWidth: rawWidth, rawHeight: rawHeight, effectiveWidth: width, effectiveHeight: height)
    }
    func value(_ request: String) -> CoverProvenance? { lock.lock(); defer { lock.unlock() }; return items[request] }
}
