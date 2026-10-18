import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

// Independently implemented optional third-party protocol. No provider code is included.
enum OnlineSubtitleError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(s) = self { return s }; return nil }
}
struct OnlineSubtitleCandidate: Identifiable, Equatable {
    let id: String
    let name: String
    let language: String
    let ext: String
    let url: URL
}
struct OnlineSubtitleCue: Equatable {
    let start: Double
    let end: Double
    let text: String
}
enum OnlineSubtitlePolicy {
    static let searchLimit = 1_048_576
    static let downloadLimit = 8_388_608
    static func searchURL(_ query: String) throws -> URL {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, q.count <= 200 else { throw OnlineSubtitleError.invalid("请输入 1–200 字查询词") }
        var c = URLComponents(string: "https://api-shoulei-ssl.xunlei.com/oracle/subtitle")!
        c.queryItems = [URLQueryItem(name: "name", value: q)]
        return c.url!
    }
    static func allowed(_ u: URL, search: Bool) -> Bool {
        guard u.scheme?.lowercased() == "https", u.user == nil, u.password == nil,
              u.port == nil || u.port == 443, u.fragment == nil else { return false }
        if search { return u.host?.lowercased() == "api-shoulei-ssl.xunlei.com" && u.path == "/oracle/subtitle" }
        // Exact public CDN and known subtitle path only; no suffix matching or URL reconstruction.
        return u.host?.lowercased() == "subtitle.v.geilijiasu.com" && u.query == nil &&
            u.path.range(of: #"^/[A-Fa-f0-9]{2}/[A-Fa-f0-9]{2}/[A-Fa-f0-9]{40}\.(srt|ass|vtt)$"#, options: .regularExpression) != nil
    }
    static func candidates(_ data: Data) throws -> [OnlineSubtitleCandidate] {
        guard data.count <= searchLimit,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = root["code"] as? Int, code == 0,
              let rows = root["data"] as? [[String: Any]] else { throw OnlineSubtitleError.invalid("第三方响应格式异常") }
        var seen = Set<String>(); var output: [OnlineSubtitleCandidate] = []
        for row in rows.prefix(500) {
            guard let raw = row["url"] as? String, let u = URL(string: raw), allowed(u, search: false),
                  seen.insert(u.absoluteString).inserted else { continue }
            let ext = (row["ext"] as? String ?? u.pathExtension).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard ["srt", "ass", "vtt"].contains(ext) else { continue }
            let name = String((row["name"] as? String ?? row["simple_name"] as? String ?? "字幕").prefix(240))
            let langs = (row["languages"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            output.append(.init(id: raw, name: name, language: langs.isEmpty ? "未知" : String(langs.joined(separator: " / ").prefix(100)), ext: ext, url: u))
            if output.count == 80 { break }
        }
        return output
    }
}

// Fresh ephemeral session for each request. No application cookies, credentials or 115 headers.
// Delegate caps memory while streaming and validates EVERY redirect before following it.
final class OnlineSubtitleRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let search: Bool
    private let limit: Int
    private var bytes = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var failure: Error?
    private let cancellationLock = NSLock()
    private var cancelled = false
    private let protocolClasses: [AnyClass]?
    init(search: Bool, protocolClasses: [AnyClass]? = nil) {
        self.search = search; self.protocolClasses = protocolClasses
        limit = search ? OnlineSubtitlePolicy.searchLimit : OnlineSubtitlePolicy.downloadLimit
    }
    private func cancel() {
        cancellationLock.lock(); cancelled = true; let running = task; cancellationLock.unlock()
        running?.cancel()
    }
    func run(_ url: URL) async throws -> Data {
        guard OnlineSubtitlePolicy.allowed(url, search: search) else { throw OnlineSubtitleError.invalid("不安全的字幕地址") }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let config = URLSessionConfiguration.ephemeral
                config.httpCookieStorage = nil; config.httpShouldSetCookies = false
                config.urlCredentialStorage = nil; config.urlCache = nil
                if let protocolClasses { config.protocolClasses = protocolClasses } // Deterministic test transport; production uses system HTTPS.
                config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 25
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                self.session = session
                var request = URLRequest(url: url); request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue(search ? "application/json" : "text/plain", forHTTPHeaderField: "Accept")
                let running = session.dataTask(with: request)
                cancellationLock.lock(); task = running; let shouldCancel = cancelled; cancellationLock.unlock()
                running.resume()
                if shouldCancel { running.cancel() }
            }
        }, onCancel: { self.cancel() })
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, OnlineSubtitlePolicy.allowed(url, search: search) else {
            failure = OnlineSubtitleError.invalid("已拒绝不安全的重定向"); completionHandler(nil); task.cancel(); return
        }
        var clean = URLRequest(url: url); clean.setValue(search ? "application/json" : "text/plain", forHTTPHeaderField: "Accept")
        completionHandler(clean)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), response.expectedContentLength <= Int64(limit), response.mimeType != "text/html" else {
            failure = OnlineSubtitleError.invalid("字幕服务错误或文件过大"); completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count + data.count <= limit else { failure = OnlineSubtitleError.invalid("字幕超过大小限制"); dataTask.cancel(); return }
        bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = failure ?? error { continuation?.resume(throwing: error) }
        else { continuation?.resume(returning: bytes) }
        continuation = nil
        cancellationLock.lock(); self.task = nil; cancellationLock.unlock()
        self.session = nil; session.finishTasksAndInvalidate()
    }
}

enum OnlineSubtitleParser {
    static func decode(_ data: Data, hint: String? = nil) throws -> String {
        guard data.count <= OnlineSubtitlePolicy.downloadLimit, !data.contains(0) else { throw OnlineSubtitleError.invalid("不支持二进制/UTF-16 字幕") }
        if hint == nil || hint == "auto" || hint == "utf8" {
            if let text = String(data: data, encoding: .utf8) { return text }
            if hint == "utf8" { throw OnlineSubtitleError.invalid("不是有效 UTF-8") }
        }
        var candidates = Set<String>()
        #if canImport(Darwin)
        for (key, cf) in [("gb18030", CFStringEncodings.GB_18030_2000), ("big5", CFStringEncodings.big5)] {
            if let hint, hint != "auto", hint != key { continue }
            let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue)))
            if let text = String(data: data, encoding: encoding), !text.contains("�"),
               let roundtrip = text.data(using: encoding), roundtrip == data { candidates.insert(text) }
        }
        #endif
        if candidates.count == 1 { return candidates.first! }
        throw OnlineSubtitleError.invalid("编码无法可靠确定，请手选 UTF-8 / GB18030 / Big5 后重新选字幕")
    }
    static func time(_ raw: String) -> Double? {
        let rawParts = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        let parts = rawParts.count == 2 ? [Substring("0")] + rawParts : rawParts
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]), h >= 0, m >= 0, m < 60, s >= 0, s < 60 else { return nil }
        let t = h * 3600 + m * 60 + s
        return t.isFinite && t <= 604800 ? t : nil
    }
    static func plain(_ input: String, ass: Bool) -> String {
        // Text only. No markup, drawing commands, links, scripts or external resources rendered.
        var s = input
        if ass {
            if s.range(of: #"\\p[1-9]"#, options: .regularExpression) != nil { return "" }
            s = s.replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\h", with: " ")
        }
        s = s.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func parse(_ data: Data, ext: String, encodingHint: String? = nil) throws -> [OnlineSubtitleCue] {
        let text = try decode(data, hint: encodingHint).replacingOccurrences(of: "\u{feff}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lower = text.prefix(1024).lowercased()
        guard !lower.contains("<!doctype"), !lower.contains("<html"), !lower.contains("<script"), !lower.contains("<?xml"), !lower.contains("<error"),
              !text.unicodeScalars.contains(where: { $0.value < 32 && ![9, 10, 13].contains($0.value) }),
              ["srt", "vtt", "ass"].contains(ext) else { throw OnlineSubtitleError.invalid("不是支持的文本字幕") }
        // Reject newline bombs before components creates an unbounded array of tiny strings.
        guard text.utf8.lazy.filter({ $0 == 10 }).prefix(150001).count < 150000 else {
            throw OnlineSubtitleError.invalid("字幕行数过多")
        }
        let lines = text.components(separatedBy: "\n")
        guard lines.count <= 150000, !lines.contains(where: { $0.utf8.count > 16384 }) else { throw OnlineSubtitleError.invalid("字幕行数或单行长度过大") }
        let deadline = Date().addingTimeInterval(2)
        var cues: [OnlineSubtitleCue] = []
        func add(_ start: Double?, _ end: Double?, _ value: String, ass: Bool = false) throws {
            guard let start, let end, end > start else { throw OnlineSubtitleError.invalid("字幕时间轴格式异常") }
            let clean = plain(value, ass: ass)
            guard clean.count <= 8192 else { throw OnlineSubtitleError.invalid("字幕段落过长") }
            if !clean.isEmpty { cues.append(.init(start: start, end: end, text: clean)) }
            guard cues.count <= 20000, Date() < deadline else { throw OnlineSubtitleError.invalid("字幕段落过多或解析超时") }
        }
        if ext == "ass" {
            var events = false
            var format = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]
            for line in lines {
                if line.hasPrefix("[") { events = line.lowercased() == "[events]" }
                guard events else { continue }
                if line.lowercased().hasPrefix("format:") { format = line.dropFirst(7).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() } }
                guard line.lowercased().hasPrefix("dialogue:") else { continue }
                guard format.last == "text", let si = format.firstIndex(of: "start"), let ei = format.firstIndex(of: "end") else { throw OnlineSubtitleError.invalid("不支持此 ASS Events 格式") }
                let p = line.dropFirst(9).split(separator: ",", maxSplits: format.count - 1, omittingEmptySubsequences: false).map(String.init)
                guard p.count == format.count else { throw OnlineSubtitleError.invalid("ASS 对白格式异常") }
                try add(time(p[si]), time(p[ei]), p.last!, ass: true)
            }
        } else {
            var i = 0
            while i < lines.count {
                if ext == "vtt", lines[i].hasPrefix("NOTE") || lines[i] == "STYLE" || lines[i] == "REGION" {
                    while i < lines.count, !lines[i].isEmpty { i += 1 }
                    continue
                }
                guard lines[i].contains("-->") else { i += 1; continue }
                let p = lines[i].components(separatedBy: "-->")
                guard p.count == 2 else { throw OnlineSubtitleError.invalid("字幕时间轴格式异常") }
                let start = time(p[0]); let end = time(String(p[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? ""))
                i += 1; var content: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { content.append(lines[i]); i += 1 }
                try add(start, end, content.joined(separator: "\n"))
            }
        }
        guard !cues.isEmpty else { throw OnlineSubtitleError.invalid("字幕没有可显示的对白") }
        return cues.sorted { $0.start < $1.start }
    }
    static func display(_ cues: [OnlineSubtitleCue], at time: Double, offset: Double) -> String {
        guard time.isFinite else { return "" }
        let t = time - offset // Positive offset means display later.
        return cues.lazy.filter { $0.start <= t && t < $0.end }.prefix(4).map(\.text).joined(separator: "\n")
    }
}

#if os(iOS) && canImport(SwiftUI) && !SUBTITLE_CORE_TEST
import SwiftUI
import UIKit
@MainActor final class OnlineSubtitleModel: ObservableObject {
    @Published var query = ""
    @Published var results: [OnlineSubtitleCandidate] = []
    @Published var status = "尚未搜索"
    @Published var selected: OnlineSubtitleCandidate?
    @Published var cues: [OnlineSubtitleCue] = []
    @Published var offset: Double = 0
    @Published var encodingHint = "auto"
    @Published var busy = false
    private var generation = 0
    private var work: Task<Void, Never>?
    private var cache: (query: String, date: Date, rows: [OnlineSubtitleCandidate])?
    private let fetch: (URL, Bool) async throws -> Data
    init(fetch: @escaping (URL, Bool) async throws -> Data = { url, search in try await OnlineSubtitleRequest(search: search).run(url) }) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--subtitle-controls-fixture") {
            // Only substitute transport bytes. Selection, parsing, cancellation,
            // generation guards, timeline display and dismissal remain production.
            self.fetch = { _, search in
                if search {
                    return Data(#"{"code":0,"data":[{"name":"自创合法测试字幕","ext":"srt","languages":[],"url":"https://subtitle.v.geilijiasu.com/AA/BB/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.srt"}]}"#.utf8)
                }
                return Data("1\n00:00:00,000 --> 00:00:06,000\n自创外置字幕第一段\n\n2\n00:00:06,000 --> 00:02:00,000\n自创外置字幕第二段\n".utf8)
            }
            return
        }
        #endif
        self.fetch = fetch
    }
    func clear() {
        generation += 1; work?.cancel(); work = nil
        cues = []; selected = nil; results = []; offset = 0; busy = false
        cache = nil; query = ""; encodingHint = "auto"; status = "尚未搜索"
    }
    func disable() {
        generation += 1; work?.cancel(); work = nil
        cues = []; selected = nil; offset = 0; busy = false; status = "字幕已关闭"
    }
    func search() {
        generation += 1; work?.cancel(); let token = generation
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = []; busy = true; status = "搜索中…"
        let fetch = self.fetch
        work = Task { [weak self] in
            do {
                let url = try OnlineSubtitlePolicy.searchURL(q)
                let rows: [OnlineSubtitleCandidate]
                if let cache = self?.cache, cache.query == q, Date().timeIntervalSince(cache.date) < 120 { rows = cache.rows }
                else {
                    let data = try await fetch(url, true)
                    rows = try OnlineSubtitlePolicy.candidates(data)
                }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.cache = (q, Date(), rows); self.results = rows
                self.status = rows.isEmpty ? "无结果，播放不受影响" : "请选择字幕；名称匹配不代表时间轴匹配"
                self.busy = false
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.status = "搜索失败：\(error.localizedDescription)"; self.busy = false
            }
        }
    }
    func choose(_ row: OnlineSubtitleCandidate) {
        generation += 1; work?.cancel(); let token = generation
        cues = []; selected = nil; offset = 0; busy = true; status = "下载选中字幕…"
        let fetch = self.fetch
        let hint = encodingHint
        work = Task { [weak self] in
            do {
                let data = try await fetch(row.url, false)
                let cues = try await Task.detached(priority: .userInitiated) { try OnlineSubtitleParser.parse(data, ext: row.ext, encodingHint: hint) }.value
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.cues = cues; self.selected = row; self.busy = false; self.status = "已加载（来源：迅雷第三方服务）"
                GlassHaptic.tap()
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.status = "加载失败：\(error.localizedDescription)"; self.busy = false
            }
        }
    }
}
// Independent presentation preferences: clearing a media request never clears style.
// Reference: KSPlayer SubtitleModel.Size/textColor; no upstream code copied.
private enum SubtitleStyleDefaults {
    static let size = 18.0
    static let x = 0.5
    static let y = 1.0
}

struct SubtitleAppearanceControls: View {
    @AppStorage("subtitle.fontPoints") private var points = SubtitleStyleDefaults.size
    @AppStorage("subtitle.positionX") private var x = SubtitleStyleDefaults.x
    @AppStorage("subtitle.positionY") private var y = SubtitleStyleDefaults.y
    var adjustPosition: () -> Void
    var body: some View {
        Section("字幕外观 · 保留到下次播放") {
            Text("字号 \(Int(points)) pt").accessibilityIdentifier("subtitle.font.value")
            Slider(value: $points, in: 14...36, step: 1) { Text("字幕字号") }
                .accessibilityIdentifier("subtitle.font.slider")
            HStack {
                Button("减小字号") { points = max(14, points - 1) }
                Spacer()
                Button("增大字号") { points = min(36, points + 1) }
            }.buttonStyle(.borderless)
            Button("调整位置（拖动字幕）", action: adjustPosition)
                .accessibilityIdentifier("subtitle.position.edit")
            HStack {
                Button("向左") { x = max(0, x - 0.05) }.accessibilityIdentifier("subtitle.nudge.left")
                Button("向右") { x = min(1, x + 0.05) }.accessibilityIdentifier("subtitle.nudge.right")
                Button("向上") { y = max(0, y - 0.05) }.accessibilityIdentifier("subtitle.nudge.up")
                Button("向下") { y = min(1, y + 0.05) }.accessibilityIdentifier("subtitle.nudge.down")
            }.buttonStyle(.borderless)
            Button("恢复默认字号与位置") {
                points = SubtitleStyleDefaults.size; x = SubtitleStyleDefaults.x; y = SubtitleStyleDefaults.y
            }.accessibilityIdentifier("subtitle.appearance.reset")
            Text("底部居中、正常字重白字与一像素细黑描边，无背景框。14–36 pt 随系统辅助字号适度放大；位置相对播放器安全区域保存。调整模式暂时隔离播放手势；没有对白时仅显示位置预览。")
                .font(.footnote)
        }
    }
}

private struct SubtitleTextSizeKey: PreferenceKey {
    static var defaultValue = CGSize(width: 1, height: 1)
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Normal watching is entirely non-interactive. In edit mode the full overlay shields
/// the underlying UIKit recognizers; only the caption itself owns the drag gesture.
struct SubtitlePresentationOverlay: View {
    var text: String
    var safeArea: EdgeInsets
    var editing: Bool
    var finish: () -> Void
    @AppStorage("subtitle.fontPoints") private var points = SubtitleStyleDefaults.size
    @AppStorage("subtitle.positionX") private var x = SubtitleStyleDefaults.x
    @AppStorage("subtitle.positionY") private var y = SubtitleStyleDefaults.y
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var dynamicScale = 1.0
    @GestureState private var translation = CGSize.zero
    @State private var textSize = CGSize(width: 1, height: 48)
    private func bounded(_ value: Double) -> CGFloat {
        CGFloat(value.isFinite ? min(1, max(0, value)) : 0.5)
    }
    var body: some View {
        GeometryReader { geo in
            // Use identical bounds whether controls are visible or hidden, so toggling chrome never jumps captions.
            // Only a small device-edge margin is reserved; a fixed 116-point control reservation blocked downward movement.
            let left = safeArea.leading + 12
            let top = safeArea.top + 12
            let bottom = safeArea.bottom + 12
            let available = CGSize(width: max(1, geo.size.width - left - safeArea.trailing - 12),
                                   height: max(1, geo.size.height - top - bottom))
            let height = min(available.height, max(1, textSize.height))
            let renderedText = text.isEmpty ? "字幕位置预览\n拖动此处调整" : text
            let fontSize: CGFloat = min(48, max(14, points.isFinite ? points : 18) * min(1.35, dynamicScale))
            let measured = (renderedText as NSString).boundingRect(with: CGSize(width: max(1, available.width * 0.86 - 20), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: UIFont.systemFont(ofSize: fontSize, weight: .regular)], context: nil)
            let width = min(available.width, max(40, ceil(measured.width) + 20))
            let travelX = max(0, available.width - width)
            let travelY = max(0, available.height - height)
            let px = min(travelX, max(0, bounded(x) * travelX + translation.width))
            let py = min(travelY, max(0, bounded(y) * travelY + translation.height))
            ZStack(alignment: .topLeading) {
                if editing {
                    Color.black.opacity(0.001).contentShape(Rectangle())
                        .onTapGesture { } // absorb taps; never toggle chrome/playback
                }
                if editing || !text.isEmpty {
                    ScrollView(.vertical) {
                        Text(renderedText)
                            .font(.system(size: fontSize, weight: .regular))
                            .foregroundStyle(.white).multilineTextAlignment(.center)
                            .shadow(color: .black, radius: 0, x: 1 / displayScale, y: 0)
                            .shadow(color: .black, radius: 0, x: -1 / displayScale, y: 0)
                            .shadow(color: .black, radius: 0, x: 0, y: 1 / displayScale)
                            .shadow(color: .black, radius: 0, x: 0, y: -1 / displayScale)
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .frame(width: width)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: SubtitleTextSizeKey.self, value: proxy.size)
                            })
                    }
                    .scrollDisabled(!editing || textSize.height <= available.height)
                    .frame(width: width, height: height)
                    .onPreferenceChange(SubtitleTextSizeKey.self) { textSize = $0 }
                    .onChange(of: points) { _, _ in textSize = CGSize(width: 1, height: 1) }
                    .contentShape(Rectangle())
                    .highPriorityGesture(DragGesture(minimumDistance: 2)
                        .updating($translation) { value, state, _ in if editing { state = value.translation } }
                        .onEnded { value in
                            guard editing else { return }
                            if travelX > 0 { x = Double(min(travelX, max(0, bounded(x) * travelX + value.translation.width)) / travelX) }
                            if travelY > 0 { y = Double(min(travelY, max(0, bounded(y) * travelY + value.translation.height)) / travelY) }
                        })
                    .position(x: left + width / 2 + px, y: top + height / 2 + py)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(text.isEmpty ? "字幕位置预览" : text)
                    .accessibilityHint(editing ? "上下轻扫调整垂直位置，更多方向可在字幕设置中调整" : "")
                    .accessibilityAdjustableAction { direction in
                        guard editing else { return }
                        y = min(1, max(0, y + (direction == .increment ? -0.05 : 0.05)))
                    }
                    .accessibilityIdentifier("subtitle.rendered")
                }
                if editing {
                    HStack {
                        Text("拖动字幕调整位置").font(.callout)
                        Spacer()
                        Button("重置位置") { x = SubtitleStyleDefaults.x; y = SubtitleStyleDefaults.y }
                            .accessibilityIdentifier("subtitle.position.reset")
                        Button("完成", action: finish).accessibilityIdentifier("subtitle.position.done")
                    }
                    .foregroundStyle(.white).buttonStyle(.bordered)
                    .padding(12).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.leading, safeArea.leading + 12).padding(.trailing, safeArea.trailing + 12)
                    .padding(.top, safeArea.top + 8)
                }
            }
        }
        .allowsHitTesting(editing)
    }
}

struct OnlineSubtitlePanel: View {
    @ObservedObject var model: OnlineSubtitleModel
    var adjustPosition: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("可选第三方服务 · 迅雷") {
                    Text("仅点击搜索后才会将下方查询词发送至迅雷。请勿输入私人文件名、路径或链接。本功能没有官方接口保证；失败不影响播放。")
                        .font(.footnote)
                    TextField("公开番号或片名", text: $model.query).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().accessibilityIdentifier("subtitle.query")
                    Button("搜索（同意发送本次查询词）") { model.search() }
                        .accessibilityIdentifier("subtitle.search")
                    Text(model.status).font(.footnote).accessibilityIdentifier("subtitle.status")
                }
                Section("显示设置") {
                    Picker("字幕编码（重选字幕生效）", selection: $model.encodingHint) {
                        Text("自动（歧义时报错）").tag("auto")
                        Text("UTF-8").tag("utf8")
                        Text("GB18030").tag("gb18030")
                        Text("Big5").tag("big5")
                    }.accessibilityIdentifier("subtitle.encoding")
                    if let selected = model.selected { Text("来源：迅雷 · \(selected.name)") }
                    Text("关闭字幕只关闭本机加载的外置字幕；视频画面内已烧录的文字无法移除。顶部“关闭字幕”同时取消下载并返回播放；“完成”仅关闭设置面板。")
                        .font(.footnote)
                    HStack {
                        Button("提前 0.5 秒") { model.offset = max(-120, model.offset - 0.5) }.accessibilityIdentifier("subtitle.earlier")
                        Spacer()
                        Text(String(format: "%+.1f 秒", model.offset)).monospacedDigit()
                        Spacer()
                        Button("延后 0.5 秒") { model.offset = min(120, model.offset + 0.5) }.accessibilityIdentifier("subtitle.later")
                    }.buttonStyle(.borderless)
                    Button("重置偏移") { model.offset = 0 }.accessibilityIdentifier("subtitle.reset")
                    Text("正值延后，负值提前。时长和名称仅供参考，需手动校准。SRT / VTT / 基本 ASS 文本；不支持 ASS 复杂特效。仅本机播放器叠层，PiP / AirPlay 外部屏幕不保证显示。切换视频或播放 URL（含清晰度）会清除字幕，以免串片。")
                        .font(.footnote)
                }
                Section("搜索结果（不会自动选择）") {
                    ForEach(model.results) { row in
                        let isSelected = model.selected?.id == row.id
                        Button { model.choose(row) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.name).lineLimit(3)
                                    Text("\(row.language) · \(row.ext.uppercased())").font(.caption)
                                    if isSelected {
                                        Text(model.status).font(.caption.weight(.semibold)).foregroundStyle(.green)
                                            .accessibilityIdentifier("subtitle.selection.feedback")
                                    }
                                }
                                Spacer(minLength: 8)
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
                                }
                            }
                        }.accessibilityIdentifier("subtitle.candidate")
                            .accessibilityValue(isSelected ? model.status : "")
                    }
                }
                SubtitleAppearanceControls(adjustPosition: adjustPosition)
            }
            .navigationTitle("在线字幕")
            .toolbar {
                // Pinned outside Form: scrolling must never hide the only off switch.
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭字幕") { model.disable(); dismiss() }
                        .accessibilityIdentifier("subtitle.disable")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("subtitle.panel.done")
                }
            }
        }
    }
}
#endif

#if DEBUG && os(iOS)
struct OnlineSubtitleFixtureView: View {
    @State private var presented = false
    @StateObject private var model = OnlineSubtitleModel(fetch: { _, search in
        if search {
            return Data(#"{"code":0,"result":"ok","data":[{"name":"自创合法测试字幕","ext":"srt","languages":[""],"url":"https://subtitle.v.geilijiasu.com/AA/BB/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.srt"}]}"#.utf8)
        }
        return Data("1\n00:00:00,000 --> 00:00:10,000\n自创测试对白\n".utf8)
    })
    var body: some View {
        Button("在线字幕") { model.query = "公开测试片名"; presented = true }
            .accessibilityIdentifier("player.subtitle.settings")
            .sheet(isPresented: $presented) { OnlineSubtitlePanel(model: model) }
    }
}
#endif
