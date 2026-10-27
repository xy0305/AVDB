import Foundation

// Live HTML fetch for javverse.com rankings. Gate cookies stay in an ephemeral jar;
// never log cookie or token values. Bundled snapshot remains the offline fallback.

enum JavVerseLiveClient {
    static let origin = "https://javverse.com"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private static let maxParallel = 3

    static func fetchSnapshot(session: URLSession? = nil) async throws -> JavVerseSnapshot {
        let transport = session ?? makeSession()
        defer { if session == nil { transport.invalidateAndCancel() } }
        try await passGate(session: transport)
        let capturedAt = isoNow()
        var boards: [JavVerseBoard] = []
        var grok: JavVerseGrokSnapshot?

        async let weeklyHTML = getHTML("\(origin)/rankings/dmm", session: transport)
        async let dailyHTML = getHTML("\(origin)/rankings/dmm?term=daily", session: transport)
        async let monthlyHTML = getHTML("\(origin)/rankings/dmm?term=monthly", session: transport)
        async let actressHTML = getHTML("\(origin)/rankings/dmm-actresses", session: transport)
        async let seriesHTML = getHTML("\(origin)/rankings/dmm-series", session: transport)
        async let grokHTML = getHTML("\(origin)/actresses/top250", session: transport)

        let weeklyPage = try await weeklyHTML
        let dailyPage = try await dailyHTML
        let monthlyPage = try await monthlyHTML
        let actressPage = try await actressHTML
        let seriesPage = try await seriesHTML
        let grokPage = try await grokHTML

        let weeklyTargets = JavVerseHTMLParser.periodTargets(
            in: weeklyPage, term: "weekly",
            defaultPath: "/rankings/dmm", base: origin
        )
        let dailyTargets = JavVerseHTMLParser.periodTargets(
            in: dailyPage, term: "daily",
            defaultPath: "/rankings/dmm?term=daily", base: origin
        )

        boards.append(contentsOf: try await fetchMovieBoards(
            primaryHTML: weeklyPage, primaryURL: "\(origin)/rankings/dmm",
            targets: weeklyTargets, term: "weekly", title: "FANZA 销量周榜",
            capturedAt: capturedAt, session: transport
        ))
        boards.append(contentsOf: try await fetchMovieBoards(
            primaryHTML: dailyPage, primaryURL: "\(origin)/rankings/dmm?term=daily",
            targets: dailyTargets, term: "daily", title: "FANZA 销量日榜",
            capturedAt: capturedAt, session: transport
        ))

        let monthlyURL = "\(origin)/rankings/dmm?term=monthly"
        boards.append(try JavVerseHTMLParser.movieBoard(
            html: monthlyPage, pageURL: monthlyURL, term: "monthly",
            title: "FANZA 销量月榜", capturedAt: capturedAt,
            isPrimary: true, forcedPeriodKey: nil, forcedLabel: nil
        ))

        boards.append(try JavVerseHTMLParser.personBoard(
            html: actressPage,
            pageURL: "\(origin)/rankings/dmm-actresses",
            id: "actresses", title: "FANZA 演员月榜", kind: "actor",
            hrefPrefix: "/actress/", capturedAt: capturedAt
        ))
        boards.append(try JavVerseHTMLParser.personBoard(
            html: seriesPage,
            pageURL: "\(origin)/rankings/dmm-series",
            id: "series", title: "FANZA 系列月榜", kind: "series",
            hrefPrefix: "/series/", capturedAt: capturedAt
        ))

        let people = try JavVerseHTMLParser.grokPeople(in: grokPage)
        guard people.count == 250 else {
            throw JavVerseFailure.message("Grok实时名单人数不是250；拒绝补位")
        }
        grok = JavVerseGrokSnapshot(
            capturedAt: capturedAt,
            sourceURL: "\(origin)/actresses/top250",
            sortEvidence: "liveFetch from public top250 page JSON",
            people: people
        )

        // Featured / recent are homepage rails; keep offline evidence when live home is skipped.
        if let bundled = try? JavVerseSnapshot.bundled() {
            for board in bundled.boards where ["featured", "recent"].contains(board.id) {
                if !boards.contains(where: { $0.id == board.id }) {
                    boards.append(board)
                }
            }
        }

        let snapshot = JavVerseSnapshot(
            schemaVersion: 2,
            mode: "liveFetch",
            origin: origin,
            preparedAt: capturedAt,
            boards: boards,
            grok: grok,
            resourceRevision: nil
        )
        try snapshot.validate()
        return snapshot
    }

    private static func fetchMovieBoards(
        primaryHTML: String, primaryURL: String,
        targets: [JavVerseHTMLParser.PeriodTarget],
        term: String, title: String, capturedAt: String,
        session: URLSession
    ) async throws -> [JavVerseBoard] {
        var boards: [JavVerseBoard] = []
        var remaining: [(JavVerseHTMLParser.PeriodTarget, String?)] = []
        for (index, target) in targets.enumerated() {
            let isPrimary = index == 0
            if isPrimary {
                boards.append(try JavVerseHTMLParser.movieBoard(
                    html: primaryHTML, pageURL: primaryURL, term: term, title: title,
                    capturedAt: capturedAt, isPrimary: true,
                    forcedPeriodKey: target.periodKey, forcedLabel: target.label
                ))
            } else {
                remaining.append((target, nil))
            }
        }
        try await withThrowingTaskGroup(of: JavVerseBoard.self) { group in
            var iterator = remaining.makeIterator()
            var inflight = 0
            func enqueue() {
                while inflight < maxParallel, let (target, _) = iterator.next() {
                    inflight += 1
                    let url = target.url
                    group.addTask {
                        let html = try await getHTML(url, session: session)
                        return try JavVerseHTMLParser.movieBoard(
                            html: html, pageURL: url, term: term, title: title,
                            capturedAt: capturedAt, isPrimary: false,
                            forcedPeriodKey: target.periodKey, forcedLabel: target.label
                        )
                    }
                }
            }
            enqueue()
            while let board = try await group.next() {
                boards.append(board)
                inflight -= 1
                enqueue()
            }
        }
        // Primary first, then periodKey descending for stable menus.
        return boards.sorted { lhs, rhs in
            let lp = lhs.periodKey ?? "", rp = rhs.periodKey ?? ""
            if (lhs.id == term) != (rhs.id == term) { return lhs.id == term }
            return lp > rp
        }
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }

    private static func passGate(session: URLSession) async throws {
        var request = URLRequest(url: URL(string: "\(origin)/_browse/gate")!)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("1", forHTTPHeaderField: "x-jv-gate")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("\(origin)/rankings", forHTTPHeaderField: "Referer")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JavVerseFailure.message("年龄门非HTTP响应")
        }
        guard http.statusCode == 204 || (200..<300).contains(http.statusCode) else {
            throw JavVerseFailure.message("年龄门未通过（\(http.statusCode)）")
        }
    }

    private static func getHTML(_ url: String, session: URLSession) async throws -> String {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JavVerseFailure.message("榜单非HTTP响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw JavVerseFailure.message("榜单请求失败（\(http.statusCode)）")
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw JavVerseFailure.message("榜单HTML无法解码")
        }
        return html
    }

    static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}

enum JavVerseHTMLParser {
    struct PeriodTarget: Equatable {
        let url: String
        let periodKey: String
        let label: String
        let periodEnd: String?
    }

    static func periodTargets(in html: String, term: String, defaultPath: String, base: String) -> [PeriodTarget] {
        let nav = firstMatch(#"<div class="rank-period">[\s\S]*?</nav>"#, in: html) ?? html
        var items: [(href: String, label: String, active: Bool)] = []
        let pattern = #"<a\b([^>]*?)href="([^"]+)"([^>]*)>([\s\S]*?)</a>"#
        for match in matches(pattern, in: nav) {
            let href = htmlUnescape(match[2])
            guard href.contains("/rankings/dmm") else { continue }
            let attrs = match[1] + match[3]
            let label = stripTags(match[4])
                .replacingOccurrences(of: "最新", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }
            let query = URLComponents(string: href)?.queryItems ?? []
            let hrefTerm = query.first(where: { $0.name == "term" })?.value
            if term == "weekly" {
                if hrefTerm != nil { continue } // daily/monthly links in shared chrome
            } else if term == "daily" {
                if hrefTerm != "daily" && !href.contains("term=daily") { continue }
            }
            items.append((href, label, attrs.contains("aria-current=\"page\"") || attrs.contains("class=\"active\"")))
        }
        // Ensure default path present as primary when nav listed it.
        if !items.contains(where: { normalizePath($0.href) == normalizePath(defaultPath) }) {
            items.insert((defaultPath, items.first?.label ?? term, true), at: 0)
        }
        // Put active / default first.
        items.sort { lhs, rhs in
            let lDefault = normalizePath(lhs.href) == normalizePath(defaultPath)
            let rDefault = normalizePath(rhs.href) == normalizePath(defaultPath)
            if lDefault != rDefault { return lDefault }
            if lhs.active != rhs.active { return lhs.active }
            return false
        }

        let years = items.compactMap { year(in: $0.href) }
        let yearHint = years.max() ?? Calendar(identifier: .gregorian).component(.year, from: Date())

        var result: [PeriodTarget] = []
        var seen = Set<String>()
        for item in items {
            let absolute = absoluteURL(item.href, base: base)
            let key: String
            let end: String?
            if let period = queryValue(item.href, name: "period") {
                key = period
                end = inferredEnd(label: item.label, start: period, term: term, year: yearHint)
            } else {
                let inferred = inferPeriodKey(label: item.label, term: term, year: yearHint, siblingPeriods: items.compactMap { queryValue($0.href, name: "period") })
                key = inferred.key
                end = inferred.end
            }
            guard seen.insert(key).inserted else { continue }
            result.append(PeriodTarget(url: absolute, periodKey: key, label: item.label, periodEnd: end))
        }
        // Cap history: daily keep ~8 (primary + 7), weekly keep primary + 1 prior.
        let limit = term == "weekly" ? 2 : 8
        if result.count > limit { return Array(result.prefix(limit)) }
        return result
    }

    static func movieBoard(
        html: String, pageURL: String, term: String, title: String,
        capturedAt: String, isPrimary: Bool,
        forcedPeriodKey: String?, forcedLabel: String?
    ) throws -> JavVerseBoard {
        let entries = try movieEntries(in: html, pageURL: pageURL)
        let meta = definitionList(in: html)
        let periodKey: String
        let periodEnd: String?
        let selectionTitle: String
        let period: String

        if term == "monthly" {
            let raw = meta["统计时间"] ?? forcedLabel ?? "月份未公布"
            let normalized = raw.replacingOccurrences(of: "–", with: "—").replacingOccurrences(of: "-", with: "—")
            period = normalized.contains("年份") ? normalized : "\(normalized)（原站未显示年份）"
            let month = firstMatch(#"(\d{1,2})月"#, in: raw).flatMap { Int($0) } ?? 0
            periodKey = month > 0 ? String(format: "year-unknown-%02d", month) : "year-unknown"
            periodEnd = nil
            selectionTitle = month > 0 ? "\(month)月 · 年份未公布" : "月份 · 年份未公布"
        } else {
            let key = forcedPeriodKey ?? queryValue(pageURL, name: "period") ?? inferPeriodKey(
                label: forcedLabel ?? "", term: term,
                year: Calendar(identifier: .gregorian).component(.year, from: Date()),
                siblingPeriods: []
            ).key
            periodKey = key
            let end = forcedLabel.flatMap { inferredEnd(label: $0, start: key, term: term, year: year(in: key) ?? 2026) }
                ?? (term == "daily" ? key : nil)
            periodEnd = end
            if term == "daily" {
                period = key
                selectionTitle = forcedLabel?.isEmpty == false ? forcedLabel! : shortDay(key)
            } else {
                let finish = end ?? key
                period = "\(key) — \(finish)"
                selectionTitle = forcedLabel?.isEmpty == false ? compactWeekLabel(forcedLabel!) : weekSelection(start: key, end: finish)
            }
        }

        let id = isPrimary ? term : "\(term)-\(periodKey)"
        return JavVerseBoard(
            id: id, title: title, period: period, capturedAt: capturedAt,
            sourceURL: pageURL, coverage: "complete", entries: entries,
            term: term, periodKey: periodKey, periodEnd: periodEnd, selectionTitle: selectionTitle
        )
    }

    static func personBoard(
        html: String, pageURL: String, id: String, title: String,
        kind: String, hrefPrefix: String, capturedAt: String
    ) throws -> JavVerseBoard {
        let meta = definitionList(in: html)
        let period: String
        if id == "series" {
            let stats = meta["统计时间"] ?? "FANZA 未公布"
            let collected = meta["本站采集"] ?? ""
            period = collected.isEmpty ? stats : "\(stats)；原站采集 \(collected)"
        } else {
            let raw = meta["统计时间"] ?? "期间未公布"
            let normalized = raw.replacingOccurrences(of: "–", with: "—")
            period = normalized.contains("年份") || normalized.contains("未公布") ? normalized : "\(normalized)（原站未显示年份）"
        }

        var entries: [JavVerseEntry] = []
        let pattern = #"<(a)\b([^>]*\bid="rank-(\d+)"[^>]*)>([\s\S]*?)(?=<a\b[^>]*\bid="rank-\d+"|\z)"#
        for match in matches(pattern, in: html) {
            let rank = Int(match[3]) ?? 0
            let attrs = match[2]
            let body = match[4]
            guard let href = firstMatch(#"href="(\#(hrefPrefix)\d+)""#, in: attrs)
                    ?? firstMatch(#"href="(\#(hrefPrefix)\d+)""#, in: body) else {
                throw JavVerseFailure.message("\(title)第\(rank)名缺少来源链接")
            }
            guard let name = firstMatch(#"class="rank-entry-name"[^>]*>([^<]+)"#, in: body)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else {
                throw JavVerseFailure.message("\(title)第\(rank)名缺少名称")
            }
            var aliases: [String] = []
            if kind == "actor", let alias = firstMatch(#"[（(]([^）)]+)[）)]"#, in: name) {
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { aliases = [trimmed] }
            }
            entries.append(JavVerseEntry(
                rank: rank, kind: kind, label: name,
                sourceURL: "\(JavVerseLiveClient.origin)\(href)",
                code: nil, aliases: aliases
            ))
        }
        entries.sort { $0.rank < $1.rank }
        guard !entries.isEmpty, entries.map(\.rank) == Array(1...entries.count) else {
            throw JavVerseFailure.message("\(title)名次不完整；拒绝补位")
        }
        return JavVerseBoard(
            id: id, title: title, period: period, capturedAt: capturedAt,
            sourceURL: pageURL, coverage: "complete", entries: entries
        )
    }

    static func movieEntries(in html: String, pageURL: String) throws -> [JavVerseEntry] {
        var entries: [JavVerseEntry] = []
        let pattern = #"<(a|div)\b([^>]*\bid="rank-(\d+)"[^>]*)>([\s\S]*?)(?=<(?:a|div)\b[^>]*\bid="rank-\d+"|\z)"#
        for match in matches(pattern, in: html) {
            let rank = Int(match[3]) ?? 0
            let attrs = match[2]
            let body = match[4]
            let code = firstMatch(#"aria-label="([A-Z0-9]+-[A-Z0-9]+)""#, in: attrs + String(body.prefix(900)))
                ?? firstMatch(#"alt="([A-Z0-9]+-[A-Z0-9]+) 封面""#, in: body)
            guard let raw = code, let identity = JavVerseIdentity.code(raw) else {
                throw JavVerseFailure.message("销量榜第\(rank)名番号无效")
            }
            let work = firstMatch(#"href="(/work/\d+)""#, in: attrs)
            let source: String
            if let work {
                source = "\(JavVerseLiveClient.origin)\(work)"
            } else {
                let base = pageURL.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? pageURL
                source = "\(base)#rank-\(rank)"
            }
            entries.append(JavVerseEntry(
                rank: rank, kind: "movie", label: identity,
                sourceURL: source, code: identity, aliases: []
            ))
        }
        entries.sort { $0.rank < $1.rank }
        guard entries.count == 100, entries.map(\.rank) == Array(1...100) else {
            throw JavVerseFailure.message("销量榜名次不是连续1…100；拒绝补位")
        }
        return entries
    }

    static func grokPeople(in html: String) throws -> [JavVerseGrokPerson] {
        // Page embeds RSC payload with escaped quotes: \"people\":[{...}]
        guard let markerRange = html.range(of: "\\\"people\\\":") ?? html.range(of: "\"people\":") else {
            throw JavVerseFailure.message("Grok页未找到people载荷")
        }
        let fromMarker = String(html[markerRange.lowerBound...])
        let unescaped: String
        if fromMarker.hasPrefix("\\\"people\\\"") {
            unescaped = fromMarker
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        } else {
            unescaped = fromMarker
        }
        guard let bracket = unescaped.firstIndex(of: "[") else {
            throw JavVerseFailure.message("Grok people数组缺失")
        }
        var depth = 0
        var end: String.Index?
        for index in unescaped[bracket...].indices {
            let ch = unescaped[index]
            if ch == "[" { depth += 1 }
            else if ch == "]" {
                depth -= 1
                if depth == 0 { end = unescaped.index(after: index); break }
            }
        }
        guard let end else { throw JavVerseFailure.message("Grok people数组未闭合") }
        let data = Data(unescaped[bracket..<end].utf8)
        struct Row: Decodable {
            let id: String
            let nameJa: String
            let nameZh: String
            let years: String
            let status: String
            let scores: [String: Int]
            let scoreText: [String: String]
            let actressId: Int
        }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return rows.map {
            JavVerseGrokPerson(
                id: $0.id, nameJa: $0.nameJa, nameZh: $0.nameZh, years: $0.years,
                status: $0.status, scores: $0.scores, scoreText: $0.scoreText, actressId: $0.actressId
            )
        }
    }

    // MARK: - helpers

    private static func definitionList(in html: String) -> [String: String] {
        var result: [String: String] = [:]
        for match in matches(#"<dt>([^<]+)</dt>\s*<dd>([\s\S]*?)</dd>"#, in: html) {
            let key = match[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = stripTags(match[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            if result[key] == nil { result[key] = value }
        }
        return result
    }

    private static func inferPeriodKey(label: String, term: String, year: Int, siblingPeriods: [String]) -> (key: String, end: String?) {
        let cleaned = label
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: " ", with: "")
        let yHint = siblingPeriods.compactMap { year(in: $0) }.max() ?? year
        if term == "daily" {
            if let parts = matches(#"(\d{1,2})\.(\d{1,2})"#, in: cleaned).first, parts.count >= 3,
               let mo = Int(parts[1]), let day = Int(parts[2]) {
                    let key = String(format: "%04d-%02d-%02d", yHint, mo, day)
                    return (key, key)
            }
            if let latest = siblingPeriods.max(), let date = dateByAdding(days: 1, to: latest) {
                return (date, date)
            }
            return (String(format: "%04d-01-01", yHint), String(format: "%04d-01-01", yHint))
        }
        // weekly "10.16-10.22"
        if let parts = matches(#"(\d{1,2})\.(\d{1,2})\s*-\s*(\d{1,2})\.(\d{1,2})"#, in: cleaned).first,
           parts.count >= 5,
           let m1 = Int(parts[1]), let d1 = Int(parts[2]), let m2 = Int(parts[3]), let d2 = Int(parts[4]) {
                let start = String(format: "%04d-%02d-%02d", yHint, m1, d1)
                var endYear = yHint
                if m2 < m1 { endYear += 1 }
                let end = String(format: "%04d-%02d-%02d", endYear, m2, d2)
                return (start, end)
        }
        if let prior = siblingPeriods.max(), let next = dateByAdding(days: 7, to: prior) {
            let end = dateByAdding(days: 6, to: next) ?? next
            return (next, end)
        }
        return (String(format: "%04d-01-01", yHint), nil)
    }

    private static func inferredEnd(label: String, start: String, term: String, year: Int) -> String? {
        if term == "daily" { return start }
        let cleaned = label.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        if let parts = matches(#"(\d{1,2})\.(\d{1,2})\s*-\s*(\d{1,2})\.(\d{1,2})"#, in: cleaned).first,
           parts.count >= 5,
           let m1 = Int(parts[1]), let m2 = Int(parts[3]), let d2 = Int(parts[4]) {
                var endYear = year(in: start) ?? year
                if m2 < m1 { endYear += 1 }
                return String(format: "%04d-%02d-%02d", endYear, m2, d2)
        }
        return dateByAdding(days: 6, to: start)
    }

    private static func shortDay(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3 else { return key }
        return "\(parts[1]).\(parts[2])"
    }

    private static func weekSelection(start: String, end: String) -> String {
        let a = start.split(separator: "-"), b = end.split(separator: "-")
        guard a.count == 3, b.count == 3 else { return "\(start)—\(end)" }
        return "\(a[1]).\(a[2])–\(b[1]).\(b[2])"
    }

    private static func compactWeekLabel(_ label: String) -> String {
        label.replacingOccurrences(of: " – ", with: "–").replacingOccurrences(of: " ", with: "")
    }

    private static func year(in text: String) -> Int? {
        guard let m = firstMatch(#"(\d{4})"#, in: text) else { return nil }
        return Int(m)
    }

    private static func dateByAdding(days: Int, to ymd: String) -> String? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components),
              let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func queryValue(_ url: String, name: String) -> String? {
        URLComponents(string: htmlUnescape(url))?.queryItems?.first(where: { $0.name == name })?.value
    }

    private static func absoluteURL(_ href: String, base: String) -> String {
        let value = htmlUnescape(href)
        if value.hasPrefix("http") { return value }
        if value.hasPrefix("/") { return base + value }
        return base + "/" + value
    }

    private static func normalizePath(_ href: String) -> String {
        let value = htmlUnescape(href)
        if let comps = URLComponents(string: value.hasPrefix("http") ? value : "https://javverse.com\(value.hasPrefix("/") ? value : "/\(value)")") {
            let path = comps.path
            let items = (comps.queryItems ?? []).sorted { $0.name < $1.name }.map { "\($0.name)=\($0.value ?? "")" }
            return items.isEmpty ? path : path + "?" + items.joined(separator: "&")
        }
        return value
    }

    private static func htmlUnescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        matches(pattern, in: text).first.flatMap { $0.count > 1 ? $0[1] : $0[0] }
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
        }
    }
}
