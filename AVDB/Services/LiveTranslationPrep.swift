import Foundation

// Build 292 — translation quality layer (Foundation-only; shared by the app, the replay harness and the Linux
// regression). Sits between the recognizer and any translator (Apple Translation / NLLB / optional LLM):
//   pre:  pure moans/breaths are dropped, ≤ 3-kana interjections and common set phrases are answered from a
//         table (no MT call), lines are split at sentence boundaries so NLLB does not drop halves, title names
//         are protected and restored from the glossary.
//   post: unsupported leading 「现在」 is stripped, NLLB filler hallucinations on garbled fragments are dropped,
//         repetition loops are cut, punctuation normalised.
// Context (previous lines) is only consumed by translators that support it (LiveContextTranslating — the LLM).

struct LiveGlossaryEntry: Codable, Equatable, Sendable { var ja: String; var zh: String }

struct LiveMTContext: Sendable, Equatable {
    var history: [(ja: String, zh: String)] = []
    var glossary: [LiveGlossaryEntry] = []
    /// Seconds until the line is due on screen (LLM is only used when it can answer in time).
    var budget: Double = 3.0
    static func == (a: Self, b: Self) -> Bool {
        a.glossary == b.glossary && a.history.map(\.ja) == b.history.map(\.ja) && a.history.map(\.zh) == b.history.map(\.zh)
    }
}

/// Translators that can use previous lines + glossary (292: the optional on-device LLM, or the chain routing to it).
/// `nil` = not now (disabled / guard / not enough time) → the caller uses the per-piece Apple/NLLB path.
protocol LiveContextTranslating: LiveTranslating {
    func contextTranslate(_ japanese: String, context: LiveMTContext) async throws -> String?
}

enum LiveMTPrep {
    enum Plan: Equatable {
        case skip                       // moan / breath / noise: nothing to show in Chinese
        case direct(String)             // table answer, no MT call
        case translate([Piece])         // MT the `.mt` pieces, keep `.fixed` ones, join in order
    }
    enum Piece: Equatable { case fixed(String), mt(String) }

    // MARK: tables

    /// Whole-line interjections / answers (after normalisation: punctuation, ー, 〜, small っ stripped at the end).
    static let interjections: [String: String] = [
        "うん": "嗯", "うんうん": "嗯嗯", "ううん": "不", "はい": "是", "はいはい": "好好", "ええ": "嗯", "え": "诶", "えー": "诶",
        "ええと": "那个", "えっと": "那个", "あの": "那个", "あのー": "那个", "あ": "啊", "ああ": "啊", "あー": "啊", "あれ": "咦",
        "おお": "哦", "おー": "哦", "お": "哦", "ねえ": "喂", "ね": "对吧", "ほら": "你看", "よし": "好", "はあ": "哈", "ふふ": "呵呵",
        "そう": "是吗", "そうか": "这样啊", "そっか": "这样啊", "そうだね": "是啊", "そうね": "是啊", "そうなんだ": "原来如此",
        "なるほど": "原来如此", "なに": "什么", "何": "什么", "なんで": "为什么", "何で": "为什么", "どう": "怎么样", "どうして": "为什么",
        "ちょっと": "等一下", "だめ": "不行", "ダメ": "不行", "だめだめ": "不行不行", "いや": "不要", "いやだ": "不要", "やだ": "讨厌",
        "嫌": "不要", "ほんと": "真的吗", "本当": "真的吗", "マジ": "真的假的", "まじ": "真的假的", "すごい": "好厉害", "凄い": "好厉害",
        "気持ちいい": "好舒服", "気持ち": "好舒服", "いく": "要去了", "イク": "要去了", "いっちゃう": "要去了", "イっちゃう": "要去了",
        "やめて": "不要", "待って": "等一下", "まって": "等一下", "痛い": "好痛", "可愛い": "好可爱", "かわいい": "好可爱",
        "大丈夫": "没事", "大丈夫？": "没事吧？", "ありがとう": "谢谢", "ごめん": "对不起", "ごめんね": "对不起哦", "おいしい": "好吃",
        "美味しい": "好吃", "おいで": "过来", "こっち": "这边", "もう": "真是的", "もっと": "再来", "早く": "快点", "はやく": "快点",
        "やった": "太好了", "よかった": "太好了", "えい": "嘿", "はーい": "好的", "どうぞ": "请", "うそ": "骗人", "嘘": "骗人",
        "おはよう": "早上好", "おやすみ": "晚安", "じゃあね": "再见", "またね": "回头见", "バイバイ": "拜拜", "ただいま": "我回来了",
        "おかえり": "欢迎回来", "おかえりなさい": "欢迎回来", "いただきます": "我开动了", "ごちそうさま": "多谢款待",
        "は": "啊", "じゃあ": "那么", "じゃ": "那么", "ん": "嗯", "んん": "嗯", "うう": "呜", "おい": "喂", "ねぇ": "喂",
        "違う": "不是", "ちがう": "不是", "いいよ": "可以哦", "いい": "好", "そうだよ": "是啊", "だよね": "是吧", "でしょ": "对吧",
    ]
    /// Set phrases matched as a whole sentence piece (optionally followed by ね/よ/ねえ and polite variants).
    static let phrases: [(String, String)] = [
        ("いらっしゃいませ", "欢迎光临"), ("よろしくお願いします", "拜托了"), ("よろしくお願いいたします", "拜托了"),
        ("よろしくね", "拜托了"), ("よろしく", "拜托了"), ("お願いします", "拜托了"), ("お願い", "拜托了"),
        ("失礼します", "打扰了"), ("失礼しました", "打扰了"), ("お邪魔します", "打扰了"), ("お疲れ様です", "辛苦了"),
        ("お疲れ様でした", "辛苦了"), ("お疲れ様", "辛苦了"), ("おつかれさま", "辛苦了"), ("ありがとうございます", "谢谢"),
        ("ありがとうございました", "谢谢"), ("すみません", "不好意思"), ("すいません", "不好意思"), ("ごめんなさい", "对不起"),
        ("申し訳ありません", "非常抱歉"), ("申し訳ございません", "非常抱歉"), ("おはようございます", "早上好"),
        ("こんにちは", "你好"), ("こんばんは", "晚上好"), ("初めまして", "初次见面"), ("はじめまして", "初次见面"),
        ("お待たせしました", "久等了"), ("お待たせ", "久等了"), ("かしこまりました", "好的"), ("わかりました", "明白了"),
        ("分かりました", "明白了"), ("わかった", "知道了"), ("分かった", "知道了"), ("了解", "了解"), ("行ってきます", "我出门了"),
        ("行ってらっしゃい", "路上小心"), ("気をつけて", "路上小心"), ("気をつけてね", "路上小心"), ("おやすみなさい", "晚安"),
        ("いただきます", "我开动了"), ("ごちそうさまでした", "多谢款待"), ("どうしたの", "怎么了"), ("どうした", "怎么了"),
        ("どうしたんですか", "怎么了"), ("大丈夫ですか", "没事吧"), ("大丈夫だよ", "没事的"), ("気持ちいい", "好舒服"),
        ("ちょっと待って", "等一下"), ("やめてください", "请住手"), ("本当に", "真的"), ("そうなんですか", "是这样吗"),
        ("そうですね", "是啊"), ("ありがとう", "谢谢"), ("ごめんね", "对不起"), ("ごめん", "对不起"), ("そうですか", "这样啊"), ("いいよ", "可以哦"), ("いいですよ", "可以哦"),
    ]
    static let moanChars = Set("あぁいぃうぅえぇおぉんっはぁふひゃゅょー〜…ッンアハフ")

    // MARK: normalisation

    static let punct = Set("。、，,.！!？?…・♪〜~「」『』（）() 　")
    static func body(_ s: String) -> String { String(s.filter { !punct.contains($0) }) }
    static func norm(_ s: String) -> String {
        var b = body(s).replacingOccurrences(of: "ー", with: "")
        while b.count > 1, b.hasSuffix("っ") || b.hasSuffix("ッ") { b.removeLast() }
        return b
    }
    static func isQuestion(_ s: String) -> Bool { s.hasSuffix("？") || s.hasSuffix("?") }
    static func hasKanji(_ s: String) -> Bool { s.unicodeScalars.contains { (0x4E00 ... 0x9FFF).contains($0.value) } }
    static func kanaOnly(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy { (0x3040 ... 0x30FF).contains($0.value) }
    }

    /// Pure moan / breath: kana-only, built from vowels / ん / っ / は-row, at least one "breathy" mark, and not a word.
    static func isMoan(_ s: String) -> Bool {
        let b = body(s)
        guard !b.isEmpty, b.allSatisfy({ moanChars.contains($0) }) else { return false }
        if interjections[norm(s)] != nil { return false }
        return b.count >= 2 && (b.contains("ん") || b.contains("っ") || b.contains("ぁ") || b.contains("ン") || b.contains("ッ")
                                || b.hasPrefix("は") || b.hasPrefix("ふ") || b.count >= 4)
    }

    /// A set phrase covering the whole piece (allowing trailing ね/よ/ねえ/！/？ and leading じゃ/では/あ/はい).
    static func phrase(_ piece: String) -> String? {
        var b = norm(piece)
        for lead in ["じゃあ", "じゃ", "では", "あ", "はい"] where b.hasPrefix(lead) && b.count > lead.count + 2 {
            let rest = String(b.dropFirst(lead.count))
            if phrases.contains(where: { rest.hasPrefix($0.0) }) { b = rest; break }
        }
        for (ja, zh) in phrases {
            guard b.hasPrefix(ja) else { continue }
            let tail = String(b.dropFirst(ja.count))
            if ["", "ね", "よ", "ねえ", "よね", "な", "ませ"].contains(tail) { return zh + (isQuestion(piece) ? "？" : "") }
        }
        return nil
    }

    /// Sentence pieces: SenseVoice punctuates 、。？！ — split there when both sides carry ≥ 3 content chars
    /// (NLLB otherwise translates the first clause and drops the rest).
    static func pieces(_ s: String) -> [String] {
        var out: [String] = [], cur = ""
        for ch in s {
            cur.append(ch)
            if "。？！?!".contains(ch) { out.append(cur); cur = "" }
        }
        if !body(cur).isEmpty { out.append(cur) } else if !cur.isEmpty, !out.isEmpty { out[out.count - 1] += cur }
        out = out.flatMap(splitAtFinalParticle)
        // merge too-short pieces into the neighbour
        var merged: [String] = []
        for p in out {
            if let last = merged.last, body(last).count < 3 || body(p).count < 3, phrase(last) == nil || phrase(p) == nil,
               !(phrase(last) != nil && body(p).count >= 3) {
                merged[merged.count - 1] = last + p
            } else { merged.append(p) }
        }
        return merged
    }

    /// SenseVoice often runs two sentences together without punctuation: 「そろそろ行くよ夜ご飯どうする？」.
    /// Split after a sentence-final よ/ね/わ/ぞ (not よね/ねえ…) when a kanji/katakana word follows and both sides
    /// keep ≥ 4 content characters.
    static func splitAtFinalParticle(_ s: String) -> [String] {
        let c = Array(s)
        guard c.count >= 9 else { return [s] }
        for i in 3 ..< c.count - 4 where "よねわぞ".contains(c[i]) {
            let next = c[i + 1]
            let nextIsWord = next.unicodeScalars.first.map { (0x4E00 ... 0x9FFF).contains($0.value) || (0x30A0 ... 0x30FF).contains($0.value) } ?? false
            guard nextIsWord, !"よねなのか".contains(c[i - 1]) || c[i] == "よ" && c[i - 1] == "る" else { continue }
            let a = String(c[0 ... i]), b = String(c[(i + 1)...])
            if body(a).count >= 4, body(b).count >= 4 { return [a + "。"] + splitAtFinalParticle(b) }
        }
        return [s]
    }

    static func plan(_ raw: String) -> Plan {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = norm(s)
        if n.isEmpty || s.allSatisfy({ $0.isASCII }) { return .skip }          // "The." / "." — SenseVoice language slips
        if let d = interjections[n] ?? interjections[body(s)] {
            return .direct(d + (isQuestion(s) && !d.hasSuffix("？") ? "？" : ""))
        }
        if isMoan(s) { return .skip }
        if let p = phrase(s) { return .direct(p) }
        let ps = pieces(s)
        return .translate(ps.map { p in
            if let d = interjections[norm(p)] { return .fixed(d + (isQuestion(p) ? "？" : "，")) }
            if let ph = phrase(p) { return .fixed(ph + (isQuestion(p) ? "" : "，")) }
            if isMoan(p) { return .fixed("") }
            return .mt(p)
        })
    }

    // MARK: glossary (title metadata: actress names)

    /// Names from title metadata. Full name plus 2+2 / 2+1 kanji family / given halves when unambiguous.
    static func glossary(names: [(ja: String, zh: String?)]) -> [LiveGlossaryEntry] {
        var out: [LiveGlossaryEntry] = []
        for (ja, zh) in names {
            let j = ja.trimmingCharacters(in: .whitespaces)
            guard j.count >= 2 else { continue }
            let z = zh.flatMap { $0.isEmpty ? nil : $0 } ?? j
            out.append(.init(ja: j, zh: z))
            let c = Array(j), zc = Array(z)
            if c.count == 4, hasKanji(String(c[0 ..< 2])), hasKanji(String(c[2 ..< 4])), zc.count == 4 {
                out.append(.init(ja: String(c[0 ..< 2]), zh: String(zc[0 ..< 2])))
                out.append(.init(ja: String(c[2 ..< 4]), zh: String(zc[2 ..< 4])))
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.ja).inserted }
    }
    /// Replace glossary terms with placeholders NLLB copies verbatim; `restore` puts the Chinese form back.
    static func protect(_ s: String, _ g: [LiveGlossaryEntry]) -> (String, [String]) {
        var t = s, used: [String] = []
        for e in g.sorted(by: { $0.ja.count > $1.ja.count }) where t.contains(e.ja) {
            t = t.replacingOccurrences(of: e.ja, with: "[\(used.count)]"); used.append(e.zh)
        }
        return (t, used)
    }
    static func restore(_ s: String, _ used: [String]) -> String {
        var t = s
        for (i, z) in used.enumerated() {
            for form in ["[\(i)]", "［\(i)］", "【\(i)】", "(\(i))", "（\(i)）"] { t = t.replacingOccurrences(of: form, with: z) }
        }
        return t
    }

    // MARK: post-processing

    /// NLLB filler outputs it produces for garbled / near-empty fragments. Kept only when the source supports them.
    static let fillerOutputs: [(zh: String, support: [String])] = [
        ("现在我知道", ["分か", "わか", "知", "今", "いま"]), ("我知道", ["分か", "わか", "知"]), ("现在", ["今", "いま", "現在"]),
        ("我很抱歉", ["ごめん", "すみません", "すいません", "申し訳", "失礼"]), ("我也很喜欢", ["好き", "も"]),
        ("我很喜欢", ["好き"]), ("我很高兴", ["嬉し", "うれし", "良かった", "よかった"]),
    ]
    static func post(_ zhRaw: String, source ja: String) -> String {
        var z = LiveText.chinesePunctuation(zhRaw)
        let supportsNow = ["今", "いま", "現在", "最近", "これから", "もう"].contains { ja.contains($0) }
        // leading 「现在，」 / 「现在」 that the Japanese does not support
        if !supportsNow {
            for lead in ["现在，", "现在,", "现在我们", "现在"] where z.hasPrefix(lead) {
                let rest = String(z.dropFirst(lead == "现在我们" ? 2 : lead.count))
                if !body(rest).isEmpty { z = rest }
                break
            }
            z = z.replacingOccurrences(of: "，现在，", with: "，")
        }
        // whole output is a filler the source does not support → nothing to show (the Japanese is garbled)
        let zb = String(body(z))
        for f in fillerOutputs where zb == f.zh {
            if !f.support.contains(where: { ja.contains($0) }) { return "" }
        }
        z = cutRepetition(z)
        // over-long output for a short source (runaway decode)
        let jn = max(1, body(ja).count)
        if body(z).count > max(12, jn * 3) { z = String(z.prefix(max(12, jn * 2))) + "…" }
        return z.trimmingCharacters(in: CharacterSet(charactersIn: "，, "))
    }
    /// 「子,子,子,子」/「我很害怕,我很害怕」: a 1–8 char unit repeated (with or without separators) → once.
    static func cutRepetition(_ s: String) -> String {
        var parts = s.components(separatedBy: CharacterSet(charactersIn: "，,、"))
        if parts.count >= 2 {
            var out: [String] = []
            for p in parts {
                if let last = out.last, body(last) == body(p), !body(p).isEmpty {
                    if let end = p.last, "。？！…".contains(end), !(last.last.map { "。？！…".contains($0) } ?? false) { out[out.count - 1] = last + String(end) }
                } else { out.append(p) }
            }
            parts = out
        }
        let joined = parts.joined(separator: "，")
        // unit repeated ≥ 3 times without separator
        let c = Array(joined)
        var out: [Character] = [], i = 0
        outer: while i < c.count {
            for len in 1 ... min(8, max(1, (c.count - i) / 3)) where i + 3 * len <= c.count {
                let unit = c[i ..< i + len]
                var reps = 1
                while i + (reps + 1) * len <= c.count, c[(i + reps * len) ..< (i + (reps + 1) * len)] == unit { reps += 1 }
                if reps >= 3 { out += unit; i += reps * len; continue outer }
            }
            out.append(c[i]); i += 1
        }
        return String(out)
    }

    /// Joins translated pieces (Chinese punctuation, no doubled commas).
    static func join(_ parts: [String]) -> String {
        var out = ""
        for p in parts where !p.isEmpty {
            if !out.isEmpty, !"，。？！…".contains(out.last!) { out += "，" }
            out += p
        }
        while out.hasSuffix("，") { out.removeLast() }
        return out
    }
}

/// Runs plan → (protect → translate → restore → post) per piece. Context goes to LiveContextTranslating only.
enum LiveMTRunner {
    static func run(_ ja: String, mt: LiveTranslating, context: LiveMTContext) async throws -> String {
        try await runDetailed(ja, mt: mt, context: context).zh
    }
    /// `contextual` = the line was answered by a LiveContextTranslating (LLM) rather than the per-piece path.
    static func runDetailed(_ ja: String, mt: LiveTranslating, context: LiveMTContext) async throws -> (zh: String, contextual: Bool) {
        switch LiveMTPrep.plan(ja) {
        case .skip: return ("", false)
        case .direct(let z): return (z, false)
        case .translate(let pieces):
            if let ctx = mt as? LiveContextTranslating, let z = try? await ctx.contextTranslate(ja, context: context) {
                // the LLM gets the whole line (it handles clauses itself) + history + glossary
                let p = LiveMTPrep.post(z, source: ja)
                if !p.isEmpty || z.isEmpty { return (p, true) }
            }
            var out: [String] = []
            for p in pieces {
                switch p {
                case .fixed(let z): out.append(z)
                case .mt(let src):
                    let (prot, used) = LiveMTPrep.protect(src, context.glossary)
                    let z = LiveMTPrep.restore(try await mt.translate(prot), used)
                    out.append(LiveMTPrep.post(z, source: src))
                }
            }
            return (LiveMTPrep.join(out), false)
        }
    }
}
