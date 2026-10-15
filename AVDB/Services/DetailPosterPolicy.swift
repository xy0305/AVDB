import Foundation

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
            let base = "https://image.mgstage.com/images/\(maker)/\(lower)/\(index)"
            return ["\(base)/pf_e_\(lower)-\(index).jpg", "\(base)/pf_o1_\(lower)-\(index).jpg"]
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
