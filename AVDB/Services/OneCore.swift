import Foundation
import CryptoKit
import CommonCrypto

// Build 308: ONE 一个 native port. The uploaded one-rex.js (a Forward/Rex widget
// script for another app) is reference data only — never evaluated. This file
// re-implements its official-API protocol in Swift: guest bootstrap, AES-128-CBC
// request/response codec, MD5 request signing, month-scan feeds, local region
// classification and direct MP4 playback lines.
// Key protocol fact kept from the script: app-version 1.6.0 (old protocol) makes
// the server include the full MP4 in `video_download`; newer versions only get
// the 4-minute preview in `video_file`.

// MARK: - Models

struct OneArticle: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let isLiveReplay: Bool
    let kindLabel: String
    let author: String?
    let publishedAt: String?
    let durationSeconds: Int
    let sizeLabel: String
    let summary: String
    let cover: URL?
    let metaLine: String
    var durationText: String { OneFormat.duration(durationSeconds) }
}

struct OnePlayLine: Identifiable, Hashable, Sendable {
    let name: String
    let note: String
    let url: URL
    var id: String { url.absoluteString }
}

struct OneEpisode: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let metaLine: String
}

struct OneDetail: Sendable {
    let article: OneArticle
    let lines: [OnePlayLine]
    let tagNames: [String]
    let episodes: [OneEpisode]
    let bodyText: String
}

enum OneSection: String, CaseIterable, Identifiable, Sendable {
    case newest, hot, jp, cn, us, live
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: return "最新"
        case .hot: return "热门"
        case .jp: return "日本"
        case .cn: return "国产"
        case .us: return "欧美"
        case .live: return "直播"
        }
    }
    var partitionID: String? {
        switch self {
        case .jp: return "jp"
        case .cn: return "cn"
        case .us: return "us"
        case .live: return "live"
        case .newest, .hot: return nil
        }
    }
}

enum OneError: LocalizedError {
    case bootstrap
    case http(Int)
    case api(Int, String)
    case empty
    case blocked
    var errorDescription: String? {
        switch self {
        case .bootstrap: return "ONE 初始化失败（种子接口都不可达），请重试。"
        case .http(let code): return "ONE 接口 HTTP \(code)，请重试。"
        case .api(let code, let message): return "ONE 接口 \(code)：\(message)"
        case .empty: return "ONE 未返回数据，请重试。"
        case .blocked: return "此内容因年龄或同意风险不可显示。"
        }
    }
}

enum OneFormat {
    static func duration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
    static func monthStart(offset: Int, calendar: Calendar = .current, now: Date = Date()) -> String {
        var d = calendar.date(byAdding: .month, value: -offset, to: now) ?? now
        var comps = calendar.dateComponents([.year, .month], from: d)
        comps.day = 1
        d = calendar.date(from: comps) ?? d
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
    static func monthLabel(offset: Int, calendar: Calendar = .current, now: Date = Date()) -> String {
        let d = calendar.date(byAdding: .month, value: -offset, to: now) ?? now
        return "\(calendar.component(.year, from: d))年\(calendar.component(.month, from: d))月"
    }
}

// MARK: - Crypto (AES-128-CBC + PKCS7, MD5 hex)

enum OneCrypto {
    static let appKey = "l*bv%Ziq000Biaog"
    static let appIV = "8597506002939249"

    static func md5Hex(_ string: String) -> String {
        Insecure.MD5.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func crypt(_ data: Data, operation: CCOperation) -> Data? {
        let key = [UInt8](Data(appKey.utf8))
        let iv = [UInt8](Data(appIV.utf8))
        let input = [UInt8](data)
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outLength = 0
        let status: CCCryptorStatus = input.withUnsafeBytes { inRaw in
            key.withUnsafeBytes { keyRaw in
                iv.withUnsafeBytes { ivRaw in
                    output.withUnsafeMutableBytes { outRaw in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyRaw.baseAddress, key.count, ivRaw.baseAddress,
                                inRaw.baseAddress, input.count, outRaw.baseAddress, outputCapacity, &outLength)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(output.prefix(outLength))
    }

    static func encryptBase64(_ plain: String) -> String? {
        crypt(Data(plain.utf8), operation: CCOperation(kCCEncrypt))?.base64EncodedString()
    }

    static func decryptBase64(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64),
              let plain = crypt(data, operation: CCOperation(kCCDecrypt)) else { return nil }
        return String(data: plain, encoding: .utf8)
    }
}

// MARK: - Flexible JSON field access (API mixes String / number for the same field)

enum OneJSON {
    static func string(_ dict: [String: Any], _ key: String) -> String {
        if let s = dict[key] as? String { return s }
        if let n = dict[key] as? NSNumber { return n.stringValue }
        return ""
    }
    static func int(_ dict: [String: Any], _ key: String) -> Int {
        if let n = dict[key] as? NSNumber { return n.intValue }
        if let s = dict[key] as? String { return Int(s) ?? 0 }
        return 0
    }
    static func array(_ dict: [String: Any], _ key: String) -> [Any] {
        dict[key] as? [Any] ?? []
    }
    static func clean(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        for (a, b) in [("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Region classification (ported from the script's tag tables + title rules)

enum OneClassifier {
    static let usTags: Set<String> = ["欧美", "美国", "英国", "德国", "法国", "意大利", "西班牙", "荷兰", "瑞典", "瑞士", "奥地利", "波兰", "捷克", "匈牙利", "罗马尼亚", "保加利亚", "俄罗斯", "乌克兰", "白俄罗斯", "拉脱维亚", "立陶宛", "爱沙尼亚", "巴西", "墨西哥", "阿根廷", "哥伦比亚", "秘鲁", "智利", "古巴", "委内瑞拉", "拉美", "拉丁", "加拿大", "澳洲", "澳大利亚", "新西兰", "印度", "泰国", "越南", "菲律宾", "印尼", "马来西亚", "阿拉伯", "异域", "土耳其", "迪拜", "以色列", "伊朗", "黑人", "金发", "白人", "碧眼", "西方", "外国", "欧美无码", "欧美精品"]
    static let jpTags: Set<String> = ["日本", "日系", "日韩", "日本无码", "日本精品"]
    static let cnTags: Set<String> = ["国产", "国语", "华语", "国产精品", "国产无码", "港台", "台湾", "香港", "新加坡"]
    static let strongUS = ["p站", "onlyfans", "fansly", "faphouse", "pjgirls", "deeper", "tushy", "vixen", "blacked", "brazzers", "realitykings", "bangbros", "teamskeet", "mylf", "chaturbate", "cb站", "推特", "fansone", "manyvids"]
    static let strongCN = ["ai短剧", "短剧", "探花", "门事件", "绿播", "微密圈", "抖音", "快手", "b站", "91", "抖阴", "杏吧", "麻豆", "天美", "糖心", "精东", "国语", "华语", "国产精品"]
    static let usWords = ["pornhub", "onlyfans", "fansly", "faphouse", "pjgirls", "deeper", "tushy", "vixen", "blacked", "brazzers", "realitykings", "naughty", "bangbros", "teamskeet", "mylf", "chaturbate", "p站", "cb站", "推特", "x站", "洋马", "白人", "金发", "碧眼", "欧美", "美国", "英国", "德国", "法国", "俄罗斯", "乌克兰", "巴西", "拉美", "拉丁", "大洋马", "洋妞", "老外", "外国", "bbc", "bwc", "尼哥", "黑大炮", "捷克", "西班牙", "意大利", "加拿大", "澳洲", "印度", "泰国", "越南", "菲律宾", "印尼", "马来西亚", "阿拉伯", "异域", "土耳其", "迪拜", "以色列", "韩国", "韩系", "波兰", "匈牙利", "罗马尼亚", "latina", "ebony", "russian", "blonde"]
    static let jpWords = ["无码", "有码", "人妻", "女优", "痴女", "素人", "日系", "日本", "和服", "风俗", "fc2", "heyzo", "jav", "myfans", "oppai", "s1", "sod", "falen", "moodyz", "prestige", "ideapocket", "ipx", "ssni", "miaa", "madonna", "ダスッ", "カリビアン", "加勒比", "一本道", "天然むすめ", "tokyo hot", "10musume", "heydouga", "无修正", "中文字幕", "熟女", "女教师", "痴汉", "电车", "东京", "大阪", "温泉"]
    static let cnWords = ["ai短剧", "短剧", "探花", "门事件", "绿播", "福利姬", "网红", "主播", "大秀", "微密圈", "抖音", "快手", "b站", "私拍", "旗袍", "学生妹", "御姐", "大圈", "传媒", "天美", "麻豆", "星空", "糖心", "91", "抖阴", "杏吧", "蜜桃", "精东", "国产", "国语", "华语", "coser", "cosplay", "推特福利", "私人订制", "定制合集"]

    static func tagNames(_ dict: [String: Any]) -> [String] {
        var out: [String] = []
        for raw in OneJSON.array(dict, "tags") {
            let value: String
            if let s = raw as? String { value = s }
            else if let d = raw as? [String: Any] {
                value = [OneJSON.string(d, "slug"), OneJSON.string(d, "name"), OneJSON.string(d, "title"), OneJSON.string(d, "tag_name")].first { !$0.isEmpty } ?? ""
            } else { value = "" }
            let v = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { out.append(v) }
        }
        return out
    }

    private static func regionByTags(_ dict: [String: Any]) -> String? {
        var us = 0, jp = 0, cn = 0
        for t in tagNames(dict) {
            if usTags.contains(t) { us += 1 }
            else if jpTags.contains(t) { jp += 1 }
            else if cnTags.contains(t) { cn += 1 }
        }
        if us > 0, us >= jp, us >= cn { return "us" }
        if jp > 0, jp >= cn { return "jp" }
        if cn > 0 { return "cn" }
        return nil
    }

    private static func hasKana(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
    }

    private static func hasCodePattern(_ s: String) -> Bool {
        let re = try? NSRegularExpression(pattern: "\\b[a-z]{2,5}[-_]\\d{2,5}\\b", options: [.caseInsensitive])
        return re?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func classifyByText(_ dict: [String: Any]) -> String {
        let title = OneJSON.string(dict, "title").isEmpty ? OneJSON.string(dict, "video_name") : OneJSON.string(dict, "title")
        let text = title + " " + OneJSON.string(dict, "author")
        let low = text.lowercased()
        if hasKana(text) { return "jp" }
        if usWords.contains(where: { low.contains($0) }) { return "us" }
        if hasCodePattern(low) { return "jp" }
        if jpWords.contains(where: { low.contains($0) }) { return "jp" }
        if cnWords.contains(where: { low.contains($0) }) { return "cn" }
        let cjk = text.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }.count
        let latin = text.unicodeScalars.filter { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }.count
        if latin > cjk * 3 / 2, latin > 6 { return "us" }
        return "cn"
    }

    /// Returns "jp" / "cn" / "us" / "live".
    static func partition(_ dict: [String: Any]) -> String {
        let title = OneJSON.string(dict, "title").isEmpty ? OneJSON.string(dict, "video_name") : OneJSON.string(dict, "title")
        if title.contains("[ONE直播") { return "live" }
        if title.contains("直播回放"), title.lowercased().contains("one直播") { return "live" }
        let low = title.lowercased()
        if strongUS.contains(where: { low.contains($0) }) { return "us" }
        if strongCN.contains(where: { low.contains($0) }) { return "cn" }
        if hasKana(title) { return "jp" }
        if hasCodePattern(low) { return "jp" }
        if let byTag = regionByTags(dict) { return byTag }
        return classifyByText(dict)
    }
}

// MARK: - Parsing helpers shared by the client

enum OneParse {
    static func stripLiveTag(_ raw: String) -> (title: String, live: Bool) {
        let re = try? NSRegularExpression(pattern: "^\\[(ONE\\s*直播[^\\]]*)\\]\\s*", options: [.caseInsensitive])
        guard let re, let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(m.range, in: raw) else { return (raw, false) }
        return (String(raw[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines), true)
    }

    static func sizeLabel(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        let re = try? NSRegularExpression(pattern: "^\\d+(\\.\\d+)?\\s*(KB|MB|GB|TB)$", options: [.caseInsensitive])
        return re?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil ? t : ""
    }

    static func durationSeconds(_ dict: [String: Any]) -> Int {
        let vl = OneJSON.int(dict, "video_length")
        if vl > 0 { return vl }
        let len = OneJSON.string(dict, "length").isEmpty ? OneJSON.string(dict, "duration") : OneJSON.string(dict, "length")
        let t = len.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return 0 }
        if t.contains(":") {
            let parts = t.split(separator: ":").map { Int($0) ?? -1 }
            if parts.allSatisfy({ $0 >= 0 }) {
                if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
                if parts.count == 2 { return parts[0] * 60 + parts[1] }
            }
        }
        func capture(_ pattern: String) -> Double? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: t) else { return nil }
            return Double(t[r])
        }
        if let mins = capture("(\\d+(?:\\.\\d+)?)\\s*(?:分钟|分|min)") { return Int((mins * 60).rounded()) }
        if let hrs = capture("(\\d+(?:\\.\\d+)?)\\s*(?:小时|h)") { return Int((hrs * 3600).rounded()) }
        if let secs = capture("(\\d+)\\s*(?:秒|s)$") { return Int(secs) }
        return 0
    }

    static func modelName(_ modelID: Int) -> String {
        switch modelID {
        case 1: return "图集"
        case 2, 3: return "视频"
        case 4: return "图文"
        case 5: return "音频"
        case 6: return "长视频"
        default: return "内容"
        }
    }

    static func isPreviewOnly(_ dict: [String: Any]) -> Bool {
        if !OneJSON.string(dict, "video_download").isEmpty { return false }
        let file = OneJSON.string(dict, "video_file")
        if file.isEmpty {
            // Search-style trimmed items carry no video fields at all: unknown, not preview.
            return !OneJSON.string(dict, "preview_video").isEmpty
        }
        if OneJSON.string(dict, "preview_video") == file { return true }
        let low = file.lowercased()
        return low.contains("preview") || low.contains("sample") || low.contains("_pr.mp4") || low.contains("-pr.mp4")
    }
}

// MARK: - Client

actor OneClient {
    static let shared = OneClient()

    private static let appVersion = "1.6.0"
    private static let signSalt = "m4n2hjPeYWkD6tFpqKF^3HO^h24P@idT"
    private static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    private static let seedHosts = [
        "https://api.2b37894.com", "https://api.35a46dd.com", "https://api.43b8477.com",
        "https://api.5ce3771.com", "https://api.61c76a0.com", "https://api.632d809.com",
        "https://api.3459381.com", "https://api.em1oifd0.com", "https://api.j7y675.com"
    ]
    private static let plainImageHosts = ["https://imgpw807.s7n7ue8.com", "https://imgpw807.2u7qzt7.com",
                                          "https://img807.hkq57tt.com", "https://imgsu807.hkq57tt.com"]
    private static let encryptedImageHosts = ["gdliren123.com", "u3wwetf.com", "m6qzbb4.com", "bdsy56.com", "gzjsqx.com", "k8b3rsp.com"]
    private static let badHosts = ["imgsu807.hkq57tt.com"]
    private static let sessionKey = "one.session.v2"

    private var uuid = ""
    private var token = ""
    private var host = ""
    private var domains: [String: [String]] = [:]
    private var sessionLoaded = false

    private struct MonthEntry { let ts: Date; let rows: [[String: Any]] }
    private var monthCache: [String: MonthEntry] = [:]

    private struct Accumulator {
        var items: [OneArticle] = []
        var seen: Set<Int> = []
        var offset = 0
        var emptyRun = 0
        var done = false
    }
    private var newestAcc = Accumulator()
    private var hotAcc = Accumulator()
    private var partAcc: [String: Accumulator] = [:]

    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    // MARK: Session persistence

    private func loadSessionIfNeeded() {
        guard !sessionLoaded else { return }
        sessionLoaded = true
        if let data = UserDefaults.standard.data(forKey: Self.sessionKey),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            uuid = OneJSON.string(dict, "uuid")
            token = OneJSON.string(dict, "token")
            host = OneJSON.string(dict, "host")
            if let dom = dict["domain"] as? [String: Any] {
                for (k, v) in dom {
                    if let arr = v as? [String] { domains[k] = arr }
                    else if let s = v as? String { domains[k] = [s] }
                }
            }
        }
        if uuid.isEmpty {
            uuid = UUID().uuidString.lowercased()
            saveSession()
        }
    }

    private func saveSession() {
        var dom: [String: Any] = [:]
        for (k, v) in domains { dom[k] = v }
        let dict: [String: Any] = ["uuid": uuid, "token": token, "host": host, "domain": dom]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        }
    }

    // MARK: Transport

    private func hostCandidates() -> [String] {
        var list: [String] = []
        if !host.isEmpty { list.append(host) }
        for h in domains["api"] ?? [] where !list.contains(h) { list.append(h) }
        for h in Self.seedHosts where !list.contains(h) { list.append(h) }
        return list
    }

    private func buildHeaders(token override: String?) -> [String: String] {
        let ts = Int(Date().timeIntervalSince1970)
        let sign = OneCrypto.md5Hex(OneCrypto.md5Hex("0.0.0.0.3.\(ts)..\(uuid)") + Self.signSalt)
        return [
            "platform": "3",
            "uuid": uuid,
            "timestamp": String(ts),
            "token": override ?? token,
            "app-version": Self.appVersion,
            "sign": sign,
            "user-key": "",
            "ip": "0.0.0.0",
            "User-Agent": Self.ua,
            "Accept": "*/*",
            "Content-Type": "application/x-www-form-urlencoded"
        ]
    }

    private func parsePayload(_ text: String) -> [String: Any]? {
        let str = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }
        if str.hasPrefix("{") {
            return (try? JSONSerialization.jsonObject(with: Data(str.utf8))) as? [String: Any]
        }
        guard let plain = OneCrypto.decryptBase64(str) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(plain.utf8))) as? [String: Any]
    }

    private func postRaw(host: String, path: String, params: [String: String]?, token override: String?) async throws -> [String: Any] {
        guard let url = URL(string: host + "/v2.5/" + path) else { throw OneError.empty }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (k, v) in buildHeaders(token: override) { request.setValue(v, forHTTPHeaderField: k) }
        var body = ""
        if let params, !params.isEmpty {
            let query = params.keys.sorted().map { key in
                let k = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
                let v = (params[key] ?? "").addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")) ?? ""
                return "\(k)=\(v)"
            }.joined(separator: "&")
            body = OneCrypto.encryptBase64(query) ?? ""
        }
        request.httpBody = Data(body.utf8)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OneError.http(http.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8), let json = parsePayload(text) else { throw OneError.empty }
        return json
    }

    private func bootstrap(force: Bool) async throws {
        loadSessionIfNeeded()
        if !force, !token.isEmpty, !host.isEmpty { return }
        var lastError: Error = OneError.bootstrap
        for candidate in hostCandidates() {
            do {
                let json = try await postRaw(host: candidate, path: "bootstrap", params: nil, token: "")
                guard OneJSON.int(json, "code") == 200, let data = json["data"] as? [String: Any] else {
                    lastError = OneError.bootstrap
                    continue
                }
                let user = data["user"] as? [String: Any] ?? [:]
                host = candidate
                token = OneJSON.string(user, "token")
                if let dom = data["domain"] as? [String: Any] {
                    for (k, v) in dom {
                        if let arr = v as? [String], !arr.isEmpty { domains[k] = arr }
                        else if let s = v as? String, !s.isEmpty { domains[k] = [s] }
                    }
                }
                saveSession()
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Mirrors the script's call(): host failover, one forced re-bootstrap on 401 / cold start.
    private func callData(path: String, params: [String: String]?) async throws -> Any {
        loadSessionIfNeeded()
        var retried = false
        var bootstrapped = !token.isEmpty
        for _ in 0..<3 {
            var lastError: Error = OneError.empty
            var saw401 = false
            for candidate in hostCandidates() {
                do {
                    let json = try await postRaw(host: candidate, path: path, params: params, token: nil)
                    let code = OneJSON.int(json, "code")
                    if code == 200 {
                        host = candidate
                        saveSession()
                        return json["data"] ?? NSNull()
                    }
                    if code == 401 { saw401 = true; lastError = OneError.api(401, OneJSON.string(json, "message")); break }
                    lastError = OneError.api(code, OneJSON.string(json, "message"))
                } catch {
                    lastError = error
                }
            }
            if !retried, saw401 || !bootstrapped {
                retried = true
                try await bootstrap(force: true)
                bootstrapped = true
                continue
            }
            throw lastError
        }
        throw OneError.empty
    }

    private func callArray(path: String, params: [String: String]?) async throws -> [[String: Any]] {
        let data = try await callData(path: path, params: params)
        if let arr = data as? [[String: Any]] { return arr }
        if let dict = data as? [String: Any], let arr = dict["list"] as? [[String: Any]] { return arr }
        return []
    }

    // MARK: Media URL resolution

    private func imageHosts() -> [String] {
        var list: [String] = []
        func add(_ arr: [String]?) {
            for raw in arr ?? [] {
                var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                while trimmed.hasSuffix("/") { trimmed.removeLast() }
                guard trimmed.hasPrefix("http"), !list.contains(trimmed) else { continue }
                if Self.badHosts.contains(where: { trimmed.contains($0) }) { continue }
                list.append(trimmed)
            }
        }
        add(domains["flutter_img"])
        add(domains["resource"])
        add(Self.plainImageHosts)
        return list
    }

    private func pickImageHost(path: String) -> String {
        let hosts = imageHosts()
        guard !hosts.isEmpty else { return "https://img807.hkq57tt.com" }
        var h: UInt32 = 0
        for unit in path.utf16 { h = h &* 31 &+ UInt32(unit) }
        return hosts[Int(h % UInt32(hosts.count))]
    }

    private func absImage(_ raw: String) -> URL? {
        let p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return nil }
        if p.hasPrefix("http://") || p.hasPrefix("https://") {
            if Self.encryptedImageHosts.contains(where: { p.contains($0) }) {
                guard let slash = p.range(of: "/", options: [], range: (p.range(of: "://")?.upperBound ?? p.startIndex)..<p.endIndex) else { return nil }
                let path = String(p[slash.lowerBound...])
                return URL(string: pickImageHost(path: path) + path)
            }
            return URL(string: p)
        }
        let path = p.hasPrefix("/") ? p : "/" + p
        return URL(string: pickImageHost(path: path) + path)
    }

    private func gifToJpeg(_ url: URL) -> URL {
        let s = url.absoluteString
        guard s.lowercased().contains(".gif") else { return url }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        let encoded = s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        return URL(string: "https://wsrv.nl/?url=" + encoded + "&output=jpg&w=520") ?? url
    }

    private func bestImage(_ dict: [String: Any]) -> URL? {
        var candidates: [String] = []
        for key in ["thumbnail", "thumb", "video_cover", "cover", "thumb_tiny"] {
            let v = OneJSON.string(dict, key)
            if !v.isEmpty { candidates.append(v) }
        }
        for key in ["multi_pic_thumbnail", "thumbnail_list"] {
            for raw in OneJSON.array(dict, key) {
                if let s = raw as? String, !s.isEmpty { candidates.append(s) }
            }
        }
        var gif: URL?
        for raw in candidates {
            guard let u = absImage(raw) else { continue }
            if u.absoluteString.lowercased().contains(".gif") { if gif == nil { gif = u }; continue }
            return u
        }
        return gif.map(gifToJpeg)
    }

    private func mediaHosts(from keys: [String]) -> [String] {
        var list: [String] = []
        for key in keys {
            for raw in domains[key] ?? [] {
                let h = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
                if !h.isEmpty, !list.contains(h) { list.append(h) }
            }
        }
        return list
    }

    private func videoHosts() -> [String] {
        let list = mediaHosts(from: ["video", "flutter_video_download", "flutter_video_play", "audio_download", "audio"])
        return list.isEmpty ? ["https://46e9nz.mfpt8g.com", "https://f86xxm.upmf83.com"] : list
    }

    private func absMedia(_ raw: String, hosts: [String]) -> URL? {
        let p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return nil }
        if p.hasPrefix("http://") || p.hasPrefix("https://") { return URL(string: p) }
        guard let first = hosts.first else { return nil }
        return URL(string: first + (p.hasPrefix("/") ? p : "/" + p))
    }

    private func videoLines(_ dict: [String: Any]) -> [OnePlayLine] {
        var lines: [OnePlayLine] = []
        let hosts = videoHosts()
        func pushMp4(_ path: String, _ label: String, _ note: String) {
            let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { return }
            if p.hasPrefix("http") {
                if let u = URL(string: p) { lines.append(OnePlayLine(name: label, note: note, url: u)) }
                return
            }
            for (i, h) in hosts.prefix(5).enumerated() {
                if let u = URL(string: h + (p.hasPrefix("/") ? p : "/" + p)) {
                    lines.append(OnePlayLine(name: "\(label) · 线路 \(i + 1)" + (p.lowercased().contains("h265") ? "（H.265）" : ""), note: note, url: u))
                }
            }
        }
        let previewOnly = OneParse.isPreviewOnly(dict)
        pushMp4(OneJSON.string(dict, "video_download"), "完整版 MP4", "ONE 直连 · 完整片 · 支持拖动")
        let videoFile = OneJSON.string(dict, "video_file")
        if !previewOnly, !videoFile.isEmpty, videoFile != OneJSON.string(dict, "video_download") {
            pushMp4(videoFile, "MP4", "ONE 直连 · 支持拖动")
        } else if previewOnly, !videoFile.isEmpty {
            pushMp4(videoFile, "预告 MP4", "ONE 直连 · 预告片（非完整版）")
        }
        if lines.isEmpty || previewOnly {
            let hlsHosts = mediaHosts(from: ["video_hls"]).isEmpty ? videoHosts() : mediaHosts(from: ["video_hls"])
            if let u = absMedia(OneJSON.string(dict, "video_hls"), hosts: hlsHosts) {
                lines.append(OnePlayLine(name: "HLS 备用", note: "ONE HLS · 加密清单，可能无法直接播放", url: u))
            }
            if let u = absMedia(OneJSON.string(dict, "video_hls_h265"), hosts: hlsHosts) {
                lines.append(OnePlayLine(name: "HLS H.265 备用", note: "ONE HLS · 加密清单，可能无法直接播放", url: u))
            }
        }
        if let u = absMedia(OneJSON.string(dict, "audio_file"), hosts: mediaHosts(from: ["audio"]).isEmpty ? videoHosts() : mediaHosts(from: ["audio"])) {
            lines.append(OnePlayLine(name: "音频", note: "ONE FM", url: u))
        }
        if lines.isEmpty, let u = absMedia(OneJSON.string(dict, "preview_video"), hosts: videoHosts()) {
            lines.append(OnePlayLine(name: "预览", note: "ONE 预览片段", url: u))
        }
        // Same URL can repeat when video_download == video_file on some hosts; keep first occurrence.
        var seen: Set<String> = []
        return lines.filter { seen.insert($0.url.absoluteString).inserted }
    }

    // MARK: Conversion

    private func convert(_ dict: [String: Any], metaPrefix: String? = nil) -> OneArticle? {
        let id = OneJSON.int(dict, "id")
        guard id > 0 else { return nil }
        let rawTitle = OneJSON.string(dict, "title").isEmpty ? OneJSON.string(dict, "video_name") : OneJSON.string(dict, "title")
        let stripped = OneParse.stripLiveTag(OneJSON.clean(rawTitle.isEmpty ? "ONE #\(id)" : rawTitle))
        let tags = OneClassifier.tagNames(dict)
        // Same age/consent screen the Tangxin port applies to external sources.
        guard TangxinPolicy.permitted(([stripped.title] + tags).joined(separator: " ")) else { return nil }
        let kind = OneParse.modelName(OneJSON.int(dict, "model_id"))
        var bits: [String] = [stripped.live ? "直播回放" : kind]
        let author = OneJSON.clean(OneJSON.string(dict, "author"))
        if !author.isEmpty { bits.append(author) }
        let published = OneJSON.string(dict, "published_at")
        if !published.isEmpty { bits.append(String(published.prefix(10))) }
        let views = OneJSON.string(dict, "views")
        if !views.isEmpty, views != "0" { bits.append("观看 " + views) }
        let likes = OneJSON.string(dict, "like_number")
        if !likes.isEmpty, likes != "0" { bits.append("赞 " + likes) }
        let seconds = OneParse.durationSeconds(dict)
        if seconds > 0 { bits.append(OneFormat.duration(seconds)) }
        let size = OneParse.sizeLabel(OneJSON.string(dict, "size"))
        if !size.isEmpty { bits.append(size) }
        let summary = OneJSON.clean(OneJSON.string(dict, "description").isEmpty ? OneJSON.string(dict, "subtitle") : OneJSON.string(dict, "description"))
        let meta = (metaPrefix.map { $0 + " · " } ?? "") + bits.joined(separator: " · ")
        return OneArticle(id: id, title: stripped.title, isLiveReplay: stripped.live, kindLabel: kind,
                          author: author.isEmpty ? nil : author,
                          publishedAt: published.isEmpty ? nil : String(published.prefix(10)),
                          durationSeconds: seconds, sizeLabel: size, summary: summary,
                          cover: bestImage(dict), metaLine: meta)
    }

    // MARK: Month feeds (the script scans month by month; page = month offset)

    private func discovery(model: Int, monthOffset: Int, page: Int, size: Int, sort: String) async -> [[String: Any]] {
        let params: [String: String] = [
            "model_id": String(model),
            "published_at": OneFormat.monthStart(offset: monthOffset),
            "page": String(page),
            "size": String(size),
            "sort": sort
        ]
        return (try? await callArray(path: "article/discovery", params: params)) ?? []
    }

    private func monthFeed(offset: Int) async -> [[String: Any]] {
        let key = "m\(offset)"
        let ttl: TimeInterval = offset <= 1 ? 600 : 12 * 3600
        if let entry = monthCache[key], Date().timeIntervalSince(entry.ts) < ttl { return entry.rows }
        var chunks: [[[String: Any]]] = []
        var moreJobs: [(model: Int, page: Int)] = []
        for model in [6, 3] {
            let first = await discovery(model: model, monthOffset: offset, page: 1, size: 100, sort: "published_at")
            chunks.append(first)
            if first.count >= 100 { for pg in 2...4 { moreJobs.append((model, pg)) } }
        }
        for job in moreJobs {
            chunks.append(await discovery(model: job.model, monthOffset: offset, page: job.page, size: 100, sort: "published_at"))
        }
        var seen: Set<Int> = []
        var rows: [[String: Any]] = []
        for chunk in chunks {
            for row in chunk {
                let id = OneJSON.int(row, "id")
                guard id > 0, seen.insert(id).inserted, !OneParse.isPreviewOnly(row) else { continue }
                rows.append(row)
            }
        }
        rows.sort { OneJSON.string($0, "published_at") > OneJSON.string($1, "published_at") }
        monthCache[key] = MonthEntry(ts: Date(), rows: rows)
        return rows
    }

    private func hotMonth(offset: Int) async -> [[String: Any]] {
        let key = "h\(offset)"
        let ttl: TimeInterval = offset <= 1 ? 600 : 6 * 3600
        if let entry = monthCache[key], Date().timeIntervalSince(entry.ts) < ttl { return entry.rows }
        var seen: Set<Int> = []
        var rows: [[String: Any]] = []
        for model in [6, 3] {
            for row in await discovery(model: model, monthOffset: offset, page: 1, size: 100, sort: "like_number") {
                let id = OneJSON.int(row, "id")
                guard id > 0, seen.insert(id).inserted, !OneParse.isPreviewOnly(row) else { continue }
                rows.append(row)
            }
        }
        rows.sort { OneJSON.int($0, "like_number") > OneJSON.int($1, "like_number") }
        monthCache[key] = MonthEntry(ts: Date(), rows: rows)
        return rows
    }

    private func consume(acc: Accumulator, page: Int, size: Int,
                         nextMonth: (Int) async -> [OneArticle]) async -> (acc: Accumulator, slice: [OneArticle]) {
        var acc = acc
        let need = page * size
        while acc.items.count < need, !acc.done, acc.offset < 400 {
            let articles = await nextMonth(acc.offset)
            if articles.isEmpty {
                acc.emptyRun += 1
                acc.offset += 1
                if acc.emptyRun >= 8 { acc.done = true }
                continue
            }
            acc.emptyRun = 0
            for article in articles where acc.seen.insert(article.id).inserted {
                acc.items.append(article)
            }
            acc.offset += 1
        }
        let from = (page - 1) * size
        guard from < acc.items.count else { return (acc, []) }
        return (acc, Array(acc.items[from..<min(from + size, acc.items.count)]))
    }

    // MARK: Public API

    func resetFeeds() {
        newestAcc = Accumulator()
        hotAcc = Accumulator()
        partAcc = [:]
    }

    func sectionPage(_ section: OneSection, page: Int) async throws -> [OneArticle] {
        try await bootstrap(force: false)
        let size = 24
        switch section {
        case .live:
            let rows = try await callArray(path: "article/search", params: [
                "keyword": "ONE直播", "model_id": "0", "series_category": "0",
                "page": String(max(1, page)), "size": String(size)
            ])
            return rows.filter { !OneParse.isPreviewOnly($0) }.compactMap { convert($0) }
        case .newest:
            let result = await consume(acc: newestAcc, page: page, size: size) { [self] offset in
                let label = OneFormat.monthLabel(offset: offset)
                return await monthFeed(offset: offset).compactMap { convert($0, metaPrefix: label) }
            }
            newestAcc = result.acc
            return result.slice
        case .hot:
            let result = await consume(acc: hotAcc, page: page, size: size) { [self] offset in
                let label = OneFormat.monthLabel(offset: offset) + " 热门"
                return await hotMonth(offset: offset).compactMap { convert($0, metaPrefix: label) }
            }
            hotAcc = result.acc
            return result.slice
        case .jp, .cn, .us:
            let pid = section.partitionID ?? ""
            let start = partAcc[pid] ?? Accumulator()
            let result = await consume(acc: start, page: page, size: size) { [self] offset in
                let label = OneFormat.monthLabel(offset: offset)
                return await monthFeed(offset: offset)
                    .filter { OneClassifier.partition($0) == pid }
                    .compactMap { convert($0, metaPrefix: label) }
            }
            partAcc[pid] = result.acc
            return result.slice
        }
    }

    func searchPage(keyword: String, page: Int) async throws -> [OneArticle] {
        try await bootstrap(force: false)
        let rows = try await callArray(path: "article/search", params: [
            "keyword": keyword, "model_id": "0", "series_category": "0",
            "page": String(max(1, page)), "size": "24"
        ])
        return rows.compactMap { convert($0) }
    }

    func detail(id: Int) async throws -> OneDetail {
        try await bootstrap(force: false)
        let data = try await callData(path: "article/detail", params: ["id": String(id)])
        guard let dict = data as? [String: Any] else { throw OneError.empty }
        let rawTitle = OneJSON.string(dict, "title").isEmpty ? OneJSON.string(dict, "video_name") : OneJSON.string(dict, "title")
        var tagNames: [String] = []
        let tagSource = !OneJSON.array(dict, "tag_list").isEmpty ? OneJSON.array(dict, "tag_list") : OneJSON.array(dict, "tags")
        for raw in tagSource {
            let name: String
            if let s = raw as? String { name = s }
            else if let d = raw as? [String: Any] {
                name = [OneJSON.string(d, "slug"), OneJSON.string(d, "name"), OneJSON.string(d, "title"), OneJSON.string(d, "tag_name")].first { !$0.isEmpty } ?? ""
            } else { name = "" }
            let cleaned = OneJSON.clean(name)
            if !cleaned.isEmpty, !tagNames.contains(cleaned) { tagNames.append(cleaned) }
        }
        let summary = OneJSON.clean(OneJSON.string(dict, "description"))
        guard TangxinPolicy.permitted(([rawTitle, summary] + tagNames).joined(separator: " ")) else { throw OneError.blocked }
        guard let article = convert(dict) else { throw OneError.blocked }
        var episodes: [OneEpisode] = []
        for (index, raw) in OneJSON.array(dict, "collection_list").enumerated() {
            guard let ep = raw as? [String: Any] else { continue }
            let epID = OneJSON.int(ep, "id")
            guard epID > 0 else { continue }
            let epTitle = OneJSON.clean(OneJSON.string(ep, "video_name").isEmpty ? OneJSON.string(ep, "title") : OneJSON.string(ep, "video_name"))
            var bits = ["第 \(OneJSON.int(ep, "episode") > 0 ? OneJSON.int(ep, "episode") : index + 1) 场"]
            let epLen = OneJSON.string(ep, "length")
            if !epLen.isEmpty { bits.append(epLen) }
            let epDate = OneJSON.string(ep, "published_at")
            if !epDate.isEmpty { bits.append(String(epDate.prefix(10))) }
            episodes.append(OneEpisode(id: epID, title: epTitle.isEmpty ? bits[0] : epTitle, metaLine: bits.joined(separator: " · ")))
        }
        return OneDetail(article: article, lines: videoLines(dict), tagNames: tagNames,
                         episodes: episodes, bodyText: summary)
    }
}
