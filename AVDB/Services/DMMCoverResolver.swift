//
//  DMMCoverResolver.swift
//  AVDB
//
//  Build 282: robust DMM / FANZA HQ cover retrieval.
//  CID resolution order: cached exact mapping → avbase product CID (learned) → label→prefix
//  table (seeded + learned, persisted) → zero-pad variants. URL patterns: awsimgsrc pics_dig
//  digital/video ps (portrait single cover, ~745×1081) → awsimgsrc pl (1600×1081 jacket) →
//  mono/movie (awsimgsrc) → pics.dmm.co.jp. Images are validated (status, real dimensions,
//  NOW-printing placeholders) before they can win. Pure Foundation; unit-tested with swiftc.
//

import Foundation

enum DMMCID {
    /// "MILK-311" → ("milk", 311). Labels with a numeric catalog prefix keep it ("13DSVR-100").
    static func parts(_ number: String) -> (label: String, serial: Int)? {
        let s = number.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let m = JRHTML.matches(#"^([0-9]{0,4}[a-z]{2,10})-?0*([0-9]{1,6})$"#, s).first,
              let n = Int(m[2]), n > 0, !m[1].hasPrefix("fc2") else { return nil }
        return (m[1], n)
    }
    static func pad(_ n: Int, _ width: Int) -> String {
        let digits = String(n)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
    static func make(prefix: String, label: String, serial: Int, width: Int = 5) -> String {
        prefix + label + pad(serial, width)
    }
    /// Learn "h_1240" (+ pad width 5) from a real product id such as "h_1240milk00311".
    static func learn(cid: String, number: String) -> (prefix: String, width: Int)? {
        guard let p = parts(number) else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: p.label)
        guard let m = JRHTML.matches("^(h_[0-9]{1,5}|[0-9]{1,4}|[a-z][0-9])?" + escaped + "([0-9]{2,6})$", cid.lowercased()).first,
              Int(m[2]) == p.serial, m[2].count >= 3 else { return nil }
        return (m[1], m[2].count)
    }
    /// Ordered CID guesses for a catalog number (deduplicated, at most four).
    static func candidates(number: String, table: DMMLabelPrefixes = .shared) -> [String] {
        guard let p = parts(number) else { return [] }
        var out: [String] = []
        func add(_ c: String) { if !out.contains(c) { out.append(c) } }
        if let exact = table.cid(for: number) { add(exact) }
        if let rule = table.rule(for: p.label) { add(make(prefix: rule.prefix, label: p.label, serial: p.serial, width: rule.width)) }
        add(make(prefix: "", label: p.label, serial: p.serial))
        add(make(prefix: "", label: p.label, serial: p.serial, width: 3))
        return Array(out.prefix(4))
    }
}

/// Label → DMM digital CID prefix. Seeded from a 510-title JavDB/avbase sample (Build 282)
/// and extended on device whenever avbase links a real FANZA product id. Persisted, capped.
final class DMMLabelPrefixes: @unchecked Sendable {
    struct Rule: Codable, Equatable, Sendable { var prefix: String; var width: Int }
    static let shared = DMMLabelPrefixes(defaults: .standard)
    static let rulesKey = "avdb.dmm.labelPrefix.v1"
    static let cidsKey = "avdb.dmm.cidByNumber.v1"
    static let ruleCap = 3000
    static let cidCap = 2000

    private let lock = NSLock()
    private let defaults: UserDefaults?
    private var learned: [String: Rule]
    private var cids: [String: String]
    private var cidOrder: [String]

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        learned = (defaults?.data(forKey: Self.rulesKey)).flatMap { try? JSONDecoder().decode([String: Rule].self, from: $0) } ?? [:]
        let stored = (defaults?.data(forKey: Self.cidsKey)).flatMap { try? JSONDecoder().decode([[String]].self, from: $0) } ?? []
        cids = [:]; cidOrder = []
        for pair in stored where pair.count == 2 { cids[pair[0]] = pair[1]; cidOrder.append(pair[0]) }
    }

    func rule(for label: String) -> Rule? {
        let l = label.lowercased()
        return lock.locked { learned[l] } ?? Self.seed[l].map { Rule(prefix: $0.0, width: $0.1) }
    }
    func cid(for number: String) -> String? {
        guard let key = Self.numberKey(number) else { return nil }
        return lock.locked { cids[key] }
    }
    /// Prefix admission for URL identity checks (a known namespace, never an arbitrary one).
    func allows(label: String, prefix: String) -> Bool {
        guard !prefix.isEmpty else { return true }
        return rule(for: label)?.prefix == prefix
    }
    /// Record a verified product id (from avbase / a validated image) for future list + detail use.
    @discardableResult
    func learn(cid: String, number: String) -> Bool {
        guard let p = DMMCID.parts(number), let rule = DMMCID.learn(cid: cid, number: number),
              let key = Self.numberKey(number) else { return false }
        let label = p.label
        lock.locked {
            if learned[label] == nil && learned.count >= Self.ruleCap, let any = learned.keys.first { learned[any] = nil }
            // Only the majority form becomes the label rule; odd paddings stay exact mappings.
            if learned[label] == nil || rule.width == 5 { learned[label] = Rule(prefix: rule.prefix, width: rule.width) }
            if cids[key] == nil { cidOrder.append(key) }
            cids[key] = cid.lowercased()
            while cidOrder.count > Self.cidCap { cids[cidOrder.removeFirst()] = nil }
        }
        persist()
        return true
    }
    func reset() { lock.locked { learned = [:]; cids = [:]; cidOrder = [] }; persist() }
    private func persist() {
        guard let defaults else { return }
        let (r, c) = lock.locked { (learned, cidOrder.compactMap { k in cids[k].map { [k, $0] } }) }
        if let data = try? JSONEncoder().encode(r) { defaults.set(data, forKey: Self.rulesKey) }
        if let data = try? JSONEncoder().encode(c) { defaults.set(data, forKey: Self.cidsKey) }
    }
    static func numberKey(_ number: String) -> String? {
        DMMCID.parts(number).map { $0.label + "-" + String($0.serial) }
    }
    /// (prefix, pad width). Generated from scripts/dmm282 sample + the pre-282 rules.
    static let seed: [String: (String, Int)] = DMMLabelSeed.table
}

enum DMMCoverURLs {
    static let aws = "https://awsimgsrc.dmm.co.jp/pics_dig"
    static let pics = "https://pics.dmm.co.jp"
    /// Portrait single cover first (awsimgsrc ps is the full-resolution front), then the jacket.
    static func digital(_ cid: String) -> [String] {
        ["\(aws)/digital/video/\(cid)/\(cid)ps.jpg", "\(aws)/digital/video/\(cid)/\(cid)pl.jpg"]
    }
    static func mono(_ cid: String) -> [String] {
        ["\(aws)/mono/movie/\(cid)/\(cid)ps.jpg", "\(aws)/mono/movie/\(cid)/\(cid)pl.jpg"]
    }
    static func legacy(_ cid: String) -> [String] {
        ["\(pics)/digital/video/\(cid)/\(cid)pl.jpg", "\(pics)/mono/movie/adult/\(cid)/\(cid)pl.jpg"]
    }
    static func amateur(_ cid: String) -> String { "\(pics)/digital/amateur/\(cid)/\(cid)jp.jpg" }

    /// Upgrade a metadata DMM image (pics pl / ps, any storefront) to the HQ awsimgsrc pair.
    static func upgrade(_ source: String) -> [String] {
        guard let url = URL(string: source), let host = url.host,
              host == "pics.dmm.co.jp" || host == "awsimgsrc.dmm.co.jp" else { return [] }
        let path = host == "awsimgsrc.dmm.co.jp" ? String(url.path.dropFirst("/pics_dig".count)) : url.path
        if let m = JRHTML.matches(#"^/digital/video/([a-z0-9_]+)/([a-z0-9_]+)(?:ps|pl)\.jpg$"#, path).first, m[1] == m[2] {
            return digital(m[1])
        }
        if let m = JRHTML.matches(#"^/mono/movie/(?:adult/|japanese/)?([a-z0-9_]+)/([a-z0-9_]+)(?:ps|pl)\.jpg$"#, path).first, m[1] == m[2] {
            return mono(m[1])
        }
        return []
    }
    /// CID named by a DMM image path, if any.
    static func cid(_ source: String) -> String? {
        guard let url = URL(string: source) else { return nil }
        let path = url.path
        return JRHTML.matches(#"/(?:digital/(?:video|amateur)|mono/movie(?:/adult|/japanese)?)/([a-z0-9_]+)/([a-z0-9_]+)(?:ps|pl|jp)\.jpg$"#, path)
            .first.flatMap { $0[1] == $0[2] ? $0[1] : nil }
    }
    /// Build 284: DVD (mono) CID for a digital CID: same namespace, serial without the 5-digit pad
    /// (ipx00706 → ipx706, h_1240milk00311 → h_1240milk311).
    static func monoCID(_ digital: String) -> String? {
        guard let m = JRHTML.matches(#"^([a-z0-9_]*?[a-z])0*([0-9]{1,6})$"#, digital).first, let n = Int(m[2]), n > 0 else { return nil }
        return m[1] + DMMCID.pad(n, 3)
    }
    /// Build 284: same-image alternates tried inside one selection slot when a DMM URL fails
    /// (HTTP error, timeout, proxy/region refusal or a NOW placeholder): other host, then the
    /// DVD storefront. Never a different title: the CID namespace and serial are preserved.
    static func fallbacks(for source: String) -> [String] {
        guard let url = URL(string: source), url.host == "awsimgsrc.dmm.co.jp" || url.host == "pics.dmm.co.jp",
              let cid = cid(source) else { return [] }
        let kind = url.lastPathComponent.hasSuffix("pl.jpg") ? "pl" : (url.lastPathComponent.hasSuffix("ps.jpg") ? "ps" : "")
        guard !kind.isEmpty else { return [] }
        let isDigital = url.path.contains("/digital/video/")
        var out: [String] = []
        if isDigital {
            if kind == "pl" { out.append("\(pics)/digital/video/\(cid)/\(cid)pl.jpg") }
            if let mono = monoCID(cid) {
                out.append("\(aws)/mono/movie/\(mono)/\(mono)\(kind).jpg")
                if kind == "pl" { out.append("\(pics)/mono/movie/adult/\(mono)/\(mono)pl.jpg") }
            }
        } else if kind == "pl" {
            out.append("\(pics)/mono/movie/adult/\(cid)/\(cid)pl.jpg")
        }
        return out.filter { $0 != source }
    }
    static func isJacket(_ source: String) -> Bool {
        guard let url = URL(string: source), ["pics.dmm.co.jp", "awsimgsrc.dmm.co.jp"].contains(url.host ?? "") else { return false }
        return url.lastPathComponent.hasSuffix("pl.jpg")
    }
}

enum DMMImageValidation {
    enum Kind: Equatable { case portrait, jacket, placeholder, tooSmall }
    /// DMM answers missing works with a redirect to now_printing.jpg (or a 404 with the same
    /// 2,732-byte body), with a 147×200 ps or a portrait 590×800 "NOW PRINTING" pl.
    static func isPlaceholderURL(_ url: URL?) -> Bool {
        guard let path = url?.path.lowercased() else { return false }
        return path.contains("now_printing") || path.contains("/noimage/")
    }
    static func classify(width: Int, height: Int, bytes: Int, source: String, finalURL: URL? = nil) -> Kind {
        if isPlaceholderURL(finalURL) || bytes == 2732 { return .placeholder }
        if (width == 147 && height == 200) || (width == 590 && height == 800 && source.hasSuffix("pl.jpg")) { return .placeholder }
        let ratio = Double(width) / Double(max(1, height))
        if source.hasSuffix("pl.jpg") {
            if ratio < 1 { return .placeholder }           // a jacket is never portrait
            return width >= 760 && (1.35...1.65).contains(ratio) ? .jacket : .tooSmall
        }
        return width >= 360 && height >= 500 && (0.5...0.82).contains(ratio) ? .portrait : .tooSmall
    }
    /// Right-hand front of a DMM jacket (measured 745/1081 = 0.69 of the height on MILK-311).
    static func frontCrop(width: Int, height: Int) -> (x: Int, width: Int)? {
        let ratio = Double(width) / Double(max(1, height))
        guard (1.35...1.65).contains(ratio) else { return nil }
        let w = Int((Double(height) * 0.69).rounded())
        return w < width ? (width - w, w) : nil
    }
}

/// Network policy for DMM image probes: small concurrency, short retries, short negative TTL.
enum DMMProbePolicy {
    static let concurrency = 2
    static let retries = 1
    static func backoff(_ attempt: Int) -> TimeInterval { 0.35 * pow(2, Double(attempt)) }
    /// Retry only transient failures (timeouts / 5xx); a 404 is definitive.
    static func shouldRetry(status: Int?) -> Bool { status == nil || (status! >= 500 && status! < 600) || status == 429 }
    static let negativeTTL: TimeInterval = 300
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
}

private extension NSLock {
    func locked<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}
