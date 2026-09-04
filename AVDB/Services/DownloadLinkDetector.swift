//
//  DownloadLinkDetector.swift
//  AVDB
//
//  从评论文本中识别下载链接（磁力 / ed2k）与番号。
//  对齐 98堂-115离线助手 的正则（magnet:/ed2k: 识别，混合文字自动提取）。
//

import Foundation

/// 识别结果
public enum DownloadLinkKind: Equatable {
    case magnet(String)
    case ed2k(String)
    case number(String)

    public var rawValue: String {
        switch self {
        case .magnet(let s), .ed2k(let s), .number(let s): return s
        }
    }

    public var isDownloadLink: Bool {
        switch self {
        case .magnet, .ed2k: return true
        case .number: return false
        }
    }

    public var label: String {
        switch self {
        case .magnet: return "磁力链接"
        case .ed2k: return "ed2k 链接"
        case .number: return "番号"
        }
    }
}

/// 从文本中识别磁力 / ed2k / 番号。
public enum DownloadLinkDetector {

    // MARK: - 链接提取（对齐参考脚本 matchLinksFast）

    /// magnet 链接：magnet:?xt=urn:btih:xxx（可带 &dn= 等后缀，遇空白/中文标点截断）
    private static let magnetPattern = #"magnet:\?[^\s<>"'，。；、]+"#

    /// ed2k 链接：ed2k://|file|...|/（到 |/ 结束，或遇空白/常见标点截断）
    private static let ed2kPattern = #"ed2k://\|file\|[\s\S]*?\|\/(?=$|\s|[<>"'，。；、\]）】)])"#

    /// 提取文本里所有下载链接（磁力 + ed2k），去重、保持顺序。
    public static func downloadLinks(in text: String) -> [DownloadLinkKind] {
        let cleaned = clean(text)
        guard !cleaned.isEmpty else { return [] }

        var result: [DownloadLinkKind] = []
        var seen = Set<String>()

        // 磁力
        if let regex = try? NSRegularExpression(pattern: magnetPattern, options: [.caseInsensitive]) {
            for m in regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
                if let r = Range(m.range, in: cleaned) {
                    let value = normalizeDownloadLink(String(cleaned[r]))
                    if !value.isEmpty, isValidLink(value), seen.insert(value.lowercased()).inserted {
                        result.append(.magnet(value))
                    }
                }
            }
        }

        // ed2k
        if let regex = try? NSRegularExpression(pattern: ed2kPattern, options: [.caseInsensitive]) {
            for m in regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
                if let r = Range(m.range, in: cleaned) {
                    let value = normalizeDownloadLink(String(cleaned[r]))
                    if !value.isEmpty, isValidLink(value), seen.insert(value.lowercased()).inserted {
                        result.append(.ed2k(value))
                    }
                }
            }
        }
        return result
    }

    /// 提取文本里的番号（形如 ABC-123 / ABC123，2-6 位字母 + 3-5 位数字，可带连字符）。
    /// 已排除 FC2PPV / HEYZO / 纯数字等误识别，尽量保守。保留连字符。
    public static func numbers(in text: String) -> [String] {
        let cleaned = clean(text)
        guard !cleaned.isEmpty else { return [] }
        // 常见番号：字母开头，连字符可选，数字结尾；排除含中文的片段
        let pattern = #"(?<![A-Za-z0-9])([A-Z]{2,10}-?\d{3,5})(?![A-Za-z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        var result: [String] = []
        var seen = Set<String>()
        for m in regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
            if let r = Range(m.range(at: 1), in: cleaned) {
                let num = String(cleaned[r]).uppercased()
                if seen.insert(num).inserted {
                    result.append(num)
                }
            }
        }
        return result
    }

    // MARK: - 辅助

    private static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    private static func normalizeDownloadLink(_ raw: String) -> String {
        var v = clean(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉结尾多余标点
        while let last = v.last, ")]】》>，。；;、".contains(last) {
            v.removeLast()
        }
        v = v.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.lowercased().hasPrefix("magnet:?") {
            v = v.replacingOccurrences(of: "&amp;", with: "&")
        } else if v.lowercased().hasPrefix("ed2k://") {
            v = v.replacingOccurrences(of: " ", with: "%20")
        }
        return v
    }

    private static func isValidLink(_ link: String) -> Bool {
        let l = link.lowercased()
        if l.hasPrefix("magnet:?") {
            return l.contains("xt=")
        }
        if l.hasPrefix("ed2k://") {
            // ed2k://|file|<name>|<size>|<hash>|/
            return l.contains("|file|") && l.hasSuffix("|/")
        }
        return false
    }
}
