import Foundation

/// Scores only the decoded, EXIF-oriented, actually usable portrait (after crop).
/// Rendering never upscales; resolutions above the 1800-point raster ceiling tie.
struct DetailPosterQuality: Sendable {
    let source: String
    let width: Int
    let height: Int
    let originalPortrait: Bool
    var score: Double { min(Double(width) / 0.7, Double(height), 1800) }

    static func winner(_ values: [Self]) -> Self? {
        let eligible = values.filter { DetailPosterPolicy.eligible(width: $0.width, height: $0.height) }
        guard let maximum = eligible.map(\.score).max() else { return nil }
        // An untouched portrait within 5% of the maximum linear resolution is
        // preferable to a derived front. Do not accumulate pairwise tolerances.
        let originals = eligible.filter { $0.originalPortrait && $0.score >= maximum * 0.95 }
        return (originals.isEmpty ? eligible : originals).sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.originalPortrait != $1.originalPortrait { return $0.originalPortrait }
            return $0.source < $1.source
        }.first
    }
}

/// Two image jobs, six distinct validated sources, one monotonic total budget.
/// The timer cancels outstanding I/O; only completed successes are returned.
/// This is the production scheduler, also exercised with controlled delayed jobs.
enum DetailPosterSelection {
    static let maxAttempts = 6
    static let concurrency = 2
    static let totalBudget: TimeInterval = 12
    static func collect<Value: Sendable>(sources: [String], budget: TimeInterval = totalBudget,
        operation: @escaping @Sendable (String, TimeInterval) async -> Value?) async -> [Value] {
        guard !Task.isCancelled, budget > 0 else { return [] }
        var seen = Set<String>()
        let candidates = Array(sources.filter { seen.insert($0).inserted }.prefix(maxAttempts))
        guard !candidates.isEmpty else { return [] }
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        return await withTaskGroup(of: (Int, Value?).self) { group in
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(budget * 1_000_000_000))
                return (-1, nil)
            }
            var next = 0
            func enqueue(_ index: Int) {
                let source = candidates[index]
                group.addTask {
                    let remaining = deadline - ProcessInfo.processInfo.systemUptime
                    guard remaining > 0, !Task.isCancelled else { return (index, nil) }
                    let value = await operation(source, min(5, remaining))
                    guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime <= deadline else { return (index, nil) }
                    return (index, value)
                }
            }
            for _ in 0..<min(concurrency, candidates.count) { enqueue(next); next += 1 }
            var completed = 0
            var values: [Value] = []
            while let (index, value) = await group.next() {
                if index < 0 || Task.isCancelled { break }
                completed += 1
                if let value { values.append(value) }
                if next < candidates.count, ProcessInfo.processInfo.systemUptime < deadline {
                    enqueue(next); next += 1
                } else if completed == candidates.count { break }
            }
            group.cancelAll()
            return Task.isCancelled ? [] : values
        }
    }
}

/// Independently implemented from the public image naming rules in the supplied
/// jable.js (1582–1655) and Pan115.js. No JavaScript or provider credentials run.
/// Only COMPLETE catalog numbers are accepted; a filename/title is not an identity.
enum DetailPosterPolicy {
    static func candidates(number: String?) -> [String] {
        guard let raw = number?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              let regex = try? NSRegularExpression(pattern: #"^([A-Z]+|390JAC)-([0-9]{2,5})$"#),
              let m = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let p = Range(m.range(at: 1), in: raw), let n = Range(m.range(at: 2), in: raw),
              let index = Int(raw[n]), index > 0 else { return [] }
        let prefix = String(raw[p]), lower = prefix.lowercased()
        let makers = ["ABF":"prestige", "ABW":"prestige", "ABP":"prestige",
                      "CHN":"prestige", "JUFE":"prestige", "MAAN":"prestige",
                      "PPT":"prestige", "390JAC":"jackson"]
        if let maker = makers[prefix] {
            // Jable uses parseInt (1); Pan115 uses number3 (001). Both are
            // evidenced provider variants, not arbitrary URL/search guesses.
            let number3 = String(repeating: "0", count: max(0, 3 - String(index).count)) + String(index)
            let numbers = number3 == String(index) ? [String(index)] : [String(index), number3]
            return numbers.flatMap { digits in
                let base = "https://image.mgstage.com/images/\(maker)/\(lower)/\(digits)"
                return ["\(base)/pf_e_\(lower)-\(digits).jpg", "\(base)/pf_o1_\(lower)-\(digits).jpg"]
            }
        }
        let mapping = ["WSA":"2", "FSDSS":"1", "FCDSS":"1", "FNS":"1", "FTHTD":"1",
                       "FALENO":"1", "FGAN":"1", "FSNF":"1", "FLAV":"1",
                       "ABP":"118", "CHN":"118", "STARS":"1", "STAR":"1", "START":"1",
                       "SODS":"1", "REBD":"h_346", "REBDB":"h_346", "GSHRB":"h_346"]
        let cid = (mapping[prefix] ?? "") + lower + String(repeating: "0", count: max(0, 5 - String(index).count)) + String(index)
        return ["https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/\(cid)/\(cid)ps.jpg",
                "https://pics.dmm.co.jp/digital/video/\(cid)/\(cid)ps.jpg"]
    }

    /// Portrait geometry is NOT a single-person or semantic classification.
    /// 376×538 proven jacket fronts pass, 147×200 thumbnails never do.
    static func eligible(width: Int, height: Int) -> Bool {
        guard width >= 360, height >= 500 else { return false }
        return (0.5...0.82).contains(Double(width) / Double(height))
    }

    static func allowedPublicImage(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil else { return false }
        let host = url.host?.lowercased() ?? ""
        let p = url.path.lowercased()
        switch host {
        case "image.mgstage.com": return p.hasPrefix("/images/") && (p.contains("/pf_e_") || p.contains("/pf_o1_")) && p.hasSuffix(".jpg")
        case "awsimgsrc.dmm.co.jp": return p.hasPrefix("/pics_dig/digital/video/") && p.hasSuffix("ps.jpg")
        case "pics.dmm.co.jp": return p.hasPrefix("/digital/video/") && p.hasSuffix("ps.jpg")
        default: return false
        }
    }
}
