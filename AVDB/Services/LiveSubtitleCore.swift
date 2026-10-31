import Foundation

// Build 287: on-device real-time AI subtitles (Japanese speech → Japanese text → Simplified Chinese).
// Foundation-only core shared by the app, the macOS CI pipeline bench and the Linux regression:
// settings, energy VAD, look-ahead scheduler, segment store (dedupe / hallucination filter / per-video cache),
// thermal/battery guard verdicts, latency ledger, NLLB tokenizer + greedy decoder, and the pipeline itself.

// MARK: - Settings

enum LiveSubtitleMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off, japanese, chinese, bilingual
    var id: String { rawValue }
    var title: String {
        switch self { case .off: "关"; case .japanese: "日文"; case .chinese: "中文"; case .bilingual: "双语" }
    }
    static let defaultsKey = "live.subtitle.mode"
    static var current: LiveSubtitleMode {
        LiveSubtitleMode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .off
    }
    var needsChinese: Bool { self == .chinese || self == .bilingual }
}

/// Live recognizers (build 289). SenseVoice-Small (FunAudioLLM, non-autoregressive CTC, int8 ONNX via sherpa-onnx)
/// is the default; Apple on-device recognition is the light fallback (thermal / falling behind); Whisper
/// (argmaxinc/whisperkit-coreml, MIT) is manual only — small is bundled, turbo is downloaded on demand.
enum LiveASRTier: String, CaseIterable, Identifiable, Codable, Sendable {
    case senseVoice = "sensevoice", apple, turbo, small
    var id: String { rawValue }
    var folder: String {
        switch self {
        case .senseVoice: "sensevoice-small-int8"
        case .apple: "apple-on-device"
        case .turbo: "openai_whisper-large-v3-v20240930_turbo_632MB"
        case .small: "openai_whisper-small_216MB"
        }
    }
    var isWhisper: Bool { self == .turbo || self == .small }
    var tokenizer: String { self == .turbo ? "tokenizer-large-v3" : "tokenizer-small" }
    var title: String {
        switch self {
        case .senseVoice: "SenseVoice"
        case .apple: "苹果系统识别"
        case .turbo: "Whisper large-v3-turbo"
        case .small: "Whisper small"
        }
    }
}

/// User-facing recognizer choice. New defaults key in 289 so every install starts on SenseVoice.
enum LiveTierPreference: String, CaseIterable, Identifiable, Sendable {
    case senseVoice = "sensevoice", apple, small, turbo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .senseVoice: "SenseVoice（默认）"
        case .apple: "苹果系统识别"
        case .small: "Whisper small"
        case .turbo: "Whisper turbo"
        }
    }
    static let defaultsKey = "live.subtitle.recognizer291"
    static let legacyKeys = ["live.subtitle.recognizer289", "live.subtitle.tier"]
    /// 291: a fresh key. Legacy values (288 `small` defaults, 289 picks) migrate once; a stale Whisper choice is
    /// never carried over (it loaded Whisper small for 27.8 s on old sessions) — SenseVoice unless re-picked.
    static var current: LiveTierPreference { current(UserDefaults.standard) }
    static func current(_ d: UserDefaults) -> LiveTierPreference {
        if let v = d.string(forKey: defaultsKey), let p = LiveTierPreference(rawValue: v) { return p }
        let legacy = legacyKeys.lazy.compactMap { d.string(forKey: $0) }.first.flatMap(LiveTierPreference.init(rawValue:))
        let migrated: LiveTierPreference = legacy == .apple ? .apple : .senseVoice
        d.set(migrated.rawValue, forKey: defaultsKey)
        return migrated
    }
    var tier: LiveASRTier {
        switch self {
        case .senseVoice: .senseVoice
        case .apple: .apple
        case .small: .small
        case .turbo: .turbo
        }
    }
    func resolve(physicalMemory: UInt64) -> LiveASRTier { tier }
}

/// Apple on-device Japanese recognition availability (289 fallback recognizer).
enum AppleASRStatus: String, Sendable {
    case unknown, installed, needsDownload, unsupported, denied
    var title: String {
        switch self {
        case .unknown: "检测中"
        case .installed: "可用（本机）"
        case .needsDownload: "需下载系统日语识别模型"
        case .unsupported: "本机不支持离线日语识别"
        case .denied: "未授权语音识别"
        }
    }
}

// MARK: - Guard (thermal / battery)

enum LiveSubtitleGuard {
    enum Verdict: Equatable, Sendable {
        case run(LiveASRTier)
        case degrade(LiveASRTier, String)
        case pause(String)
        var tier: LiveASRTier? {
            switch self { case .run(let t), .degrade(let t, _): t; case .pause: nil }
        }
        var notice: String? {
            switch self { case .run: nil; case .degrade(_, let n), .pause(let n): n }
        }
    }
    /// thermal: 0 nominal, 1 fair, 2 serious, 3 critical (ProcessInfo.ThermalState.rawValue).
    /// 291: SenseVoice runs at ~0.05× realtime, so heat / Low Power / low battery only throttle the read-ahead —
    /// they no longer swap recognizers. (289 handed over to Apple at thermal ≥ serious; on a phone hovering
    /// between fair and serious that restarted the engine every 20–60 s and each restart dropped queued audio.)
    /// Whisper (manual) still steps down to SenseVoice when hot; only `critical` hands over to Apple.
    static func verdict(preferred: LiveASRTier, thermal: Int, lowPower: Bool, battery: Float, charging: Bool) -> Verdict {
        if !charging, battery >= 0, battery < 0.10 { return .pause("电量低于 10%，AI 字幕已暂停") }
        if preferred == .apple { return .run(.apple) }
        if thermal >= 3 { return .degrade(.apple, "设备过热，已切换苹果系统识别") }
        if preferred.isWhisper, thermal >= 2 || lowPower { return .degrade(.senseVoice, "设备发热，已切换 SenseVoice") }
        return .run(preferred)
    }
    /// 292: the optional LLM translator only runs cool, off Low Power, and above 20 % battery (or charging).
    static func llmAllowed(thermal: Int, lowPower: Bool, battery: Float, charging: Bool) -> (ok: Bool, why: String) {
        if thermal >= 2 { return (false, "设备发热") }
        if lowPower { return (false, "低电量模式") }
        if !charging, battery >= 0, battery < 0.20 { return (false, "电量低于 20%") }
        return (true, "")
    }
    /// 291 hysteresis: after a heat step-down, return to the preferred recognizer only once the device has stayed
    /// below the trigger level for this long (thermal state flaps between neighbouring levels).
    static let recoverSeconds = 120.0

    /// Read-ahead under thermal pressure: fewer seconds decoded ahead = less CPU/network competing with playback.
    static func throttledLead(_ lead: Double, thermal: Int) -> Double {
        switch thermal {
        case 0: lead
        case 1: max(6, lead * 0.75)
        default: min(lead, 8)
        }
    }
}

// MARK: - Audio / VAD

struct LiveUtterance: Equatable, Sendable {
    var start: Double          // media seconds of samples[0]
    var end: Double            // media seconds after the last sample
    var speechEnd: Double      // last voiced frame end (before the hangover tail)
    var samples: [Float]       // 16 kHz mono
    var final: Bool
    var split = false          // closed by the max-length rule, not by a pause
}

/// Energy VAD with an adaptive noise floor. 20 ms frames; an utterance ends after `endSilence` of quiet
/// (low latency) or is split at the quietest frame once it reaches `maxLength` (bounded ASR latency).
final class LiveVAD {
    static let rate = 16_000
    let frame = 320
    var endSilence = 0.32, minSpeech = 0.22, maxLength = 5.0, preRoll = 0.20, tail = 0.12
    private(set) var floorDB: Float = -60
    /// 291: utterances discarded as too short (< minSpeech voiced) — diagnostics only.
    private(set) var rejectedShort = 0
    /// 291: the adaptive floor may not climb above this (continuous BGM used to lift it until speech over the music
    /// no longer cleared floor+10 dB — the CAWB-044 ~1 min gap); the voiced threshold is capped likewise.
    static let floorCeiling: Float = -46, thresholdCeiling: Float = -36
    private var pending: [Float] = []
    private var pendingStart: Double?
    private var buffer: [Float] = []       // current utterance incl. pre-roll
    private var bufferStart = 0.0
    private var frameDB: [Float] = []
    private var inSpeech = false
    private var silentFrames = 0
    private var voicedFrames = 0
    private var lastVoicedEnd = 0.0
    private var ring: [Float] = []          // pre-roll history while idle
    private var ringEnd = 0.0
    private(set) var position = 0.0        // media time after the last consumed sample

    func reset(at time: Double) {
        pending = []; pendingStart = nil; buffer = []; frameDB = []; inSpeech = false
        silentFrames = 0; voicedFrames = 0; ring = []; position = time; ringEnd = time
    }

    /// Feed contiguous PCM starting at `start`. Returns utterances completed by this chunk.
    func feed(_ samples: [Float], start: Double) -> [LiveUtterance] {
        if pendingStart == nil || abs(start - (pendingStart! + Double(pending.count) / Double(Self.rate))) > 0.05 {
            if !pending.isEmpty || inSpeech { /* discontinuity: drop the partial frame */ }
            pending = []; pendingStart = start
        }
        pending += samples
        var out: [LiveUtterance] = []
        var i = 0
        while pending.count - i >= frame {
            let f = Array(pending[i ..< i + frame])
            let t0 = pendingStart! + Double(i) / Double(Self.rate)
            if let u = step(f, t0) { out.append(u) }
            i += frame
        }
        pending.removeFirst(i); pendingStart = pendingStart! + Double(i) / Double(Self.rate)
        position = pendingStart!
        return out
    }

    /// Voiced audio collected so far for the open utterance (for streaming partials).
    func openUtterance(minimum: Double = 0.6) -> LiveUtterance? {
        guard inSpeech, Double(buffer.count) / Double(Self.rate) >= minimum else { return nil }
        return LiveUtterance(start: bufferStart, end: bufferStart + Double(buffer.count) / Double(Self.rate),
                             speechEnd: lastVoicedEnd, samples: buffer, final: false)
    }
    var openStart: Double? { inSpeech ? bufferStart : nil }
    var openLength: Double { inSpeech ? Double(buffer.count) / Double(Self.rate) : 0 }

    /// End of stream: flush the open utterance.
    func finish() -> LiveUtterance? {
        guard inSpeech, Double(voicedFrames) * 0.02 >= minSpeech else { return nil }
        defer { inSpeech = false; buffer = []; frameDB = [] }
        return LiveUtterance(start: bufferStart, end: bufferStart + Double(buffer.count) / Double(Self.rate),
                             speechEnd: lastVoicedEnd, samples: buffer, final: true)
    }

    private func step(_ f: [Float], _ t0: Double) -> LiveUtterance? {
        var e: Float = 0
        for s in f { e += s * s }
        let db = 10 * log10(max(e / Float(f.count), 1e-10))
        // Floor follows quiet frames quickly and loud frames very slowly.
        floorDB = db < floorDB ? floorDB * 0.9 + db * 0.1 : min(floorDB + 0.02, Self.floorCeiling)
        let voiced = db > min(max(floorDB + 10, -48), Self.thresholdCeiling)
        let t1 = t0 + 0.02
        if !inSpeech {
            ring += f; ringEnd = t1
            let keep = Int(preRoll * Double(Self.rate))
            if ring.count > keep { ring.removeFirst(ring.count - keep) }
            if voiced {
                inSpeech = true; buffer = ring; bufferStart = t1 - Double(ring.count) / Double(Self.rate)
                frameDB = Array(repeating: floorDB, count: max(0, ring.count / frame - 1)) + [db]
                voicedFrames = 1; silentFrames = 0; lastVoicedEnd = t1; ring = []
            }
            return nil
        }
        buffer += f; frameDB.append(db)
        if voiced { voicedFrames += 1; silentFrames = 0; lastVoicedEnd = t1 } else { silentFrames += 1 }
        let length = Double(buffer.count) / Double(Self.rate)
        if Double(silentFrames) * 0.02 >= endSilence {
            inSpeech = false
            let tailSamples = Int(tail * Double(Self.rate))
            // 291 crash fix: after a max-length split the carried remainder can start AFTER the last voiced frame
            // (cut at the quietest frame past it); `keep` went negative and `prefix(-n)` trapped the reader thread.
            let keep = max(0, min(buffer.count, Int((lastVoicedEnd - bufferStart) * Double(Self.rate)) + tailSamples))
            let u = LiveUtterance(start: bufferStart, end: bufferStart + Double(keep) / Double(Self.rate),
                                  speechEnd: lastVoicedEnd, samples: Array(buffer.prefix(keep)), final: true)
            ring = Array(buffer.suffix(Int(preRoll * Double(Self.rate)))); buffer = []; frameDB = []
            if keep < frame { return nil }
            if Double(voicedFrames) * 0.02 >= minSpeech { return u }
            rejectedShort += 1; return nil
        }
        if length >= maxLength {
            // Split at the quietest frame in the last 30 % (keeps words whole), carry the rest over.
            let n = frameDB.count, from = max(1, Int(Double(n) * 0.7))
            var cut = n - 1, best = Float.greatestFiniteMagnitude
            for k in from ..< n where frameDB[k] < best { best = frameDB[k]; cut = k }
            let cutSamples = min(buffer.count, (cut + 1) * frame)
            let u = LiveUtterance(start: bufferStart, end: bufferStart + Double(cutSamples) / Double(Self.rate),
                                  speechEnd: min(lastVoicedEnd, bufferStart + Double(cutSamples) / Double(Self.rate)),
                                  samples: Array(buffer.prefix(cutSamples)), final: true, split: true)
            bufferStart += Double(cutSamples) / Double(Self.rate)
            buffer.removeFirst(cutSamples); frameDB.removeFirst(min(frameDB.count, cut + 1))
            voicedFrames = max(1, frameDB.count)
            return u
        }
        return nil
    }
}

// MARK: - Segments, dedupe, cache

struct LiveSegment: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var start: Double
    var end: Double
    var ja: String
    var zh: String?
    var final: Bool
    var tier: String
    /// 291: playhead (media s) when the line became displayable. A line that arrives after its own time window
    /// is shown from `arrival` for a short hold instead of being silently skipped (late-but-valid lines).
    var arrival: Double? = nil
    /// 292: which translator produced `zh` ("llm" = on-device LLM → the overlay shows 机翻; "table", "mt").
    var mt: String? = nil
}

struct LiveCaption: Equatable, Sendable {
    var ja: String?
    var zh: String?
    var partial: Bool
    var pendingChinese: Bool
    /// 292: the Chinese line is LLM machine translation (Sakura licence: label 机翻).
    var machine = false
    static let empty = LiveCaption(ja: nil, zh: nil, partial: false, pendingChinese: false)
    var isEmpty: Bool { (ja ?? "").isEmpty && (zh ?? "").isEmpty }
}

enum LiveText {
    /// Whisper's well-known silence/outro hallucinations (Japanese YouTube training data).
    static let hallucinations = ["ご視聴ありがとうございました", "ご視聴ありがとうございます", "チャンネル登録", "最後までご視聴",
                                 "字幕作成", "おやすみなさい。おやすみなさい", "ご清聴ありがとうございました", "お疲れ様でした。お疲れ様でした"]
    static func clean(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\(（\[［][^\)）\]］]{0,12}[\)）\]］]"#, with: "", options: .regularExpression)   // (拍手) [音楽]
            .replacingOccurrences(of: #"(?<=[^\x00-\x7F])[ \t\u3000]+(?=[^\x00-\x7F])"#, with: "", options: .regularExpression)   // 289: SenseVoice BPE spaces "君 のこ とが"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        s = collapseRepeats(s)
        return s
    }
    static func isNoise(_ s: String) -> Bool {
        let body = s.filter { !"。、！？!?….・♪〜~ 　「」『』".contains($0) }
        if body.isEmpty { return true }
        return hallucinations.contains { s.contains($0) }
    }
    /// "ありがとうありがとうありがとうありがとう" → at most two repeats of any 1–8 char unit.
    static func collapseRepeats(_ s: String) -> String {
        let c = Array(s)
        guard c.count > 6 else { return s }
        var out: [Character] = []
        var i = 0
        outer: while i < c.count {
            let maxLen = min(8, (c.count - i) / 3)
            for len in stride(from: 1, through: maxLen, by: 1) {
                let unit = c[i ..< i + len]
                var reps = 1
                while i + (reps + 1) * len <= c.count, c[(i + reps * len) ..< (i + (reps + 1) * len)] == unit { reps += 1 }
                if reps >= 3 { out += unit; out += unit; i += reps * len; continue outer }
            }
            out.append(c[i]); i += 1
        }
        return String(out)
    }
    /// Character-bigram Dice similarity (Japanese has no spaces).
    static func similarity(_ a: String, _ b: String) -> Double {
        func grams(_ s: String) -> [String: Int] {
            let c = Array(s.filter { !$0.isWhitespace && !$0.isPunctuation })
            guard c.count > 1 else { return c.isEmpty ? [:] : [String(c): 1] }
            var d: [String: Int] = [:]
            for i in 0 ..< c.count - 1 { d[String(c[i ... i + 1]), default: 0] += 1 }
            return d
        }
        let x = grams(a), y = grams(b)
        let nx = x.values.reduce(0, +), ny = y.values.reduce(0, +)
        guard nx + ny > 0 else { return 1 }
        let inter = x.reduce(0) { $0 + min($1.value, y[$1.key] ?? 0) }
        return 2 * Double(inter) / Double(nx + ny)
    }
    /// NLLB writes ASCII punctuation; Chinese subtitles use full-width.
    static func chinesePunctuation(_ s: String) -> String {
        var out = ""
        let chars = Array(s.trimmingCharacters(in: .whitespacesAndNewlines))
        for (i, ch) in chars.enumerated() {
            let prev = i > 0 ? chars[i - 1] : " ", next = i + 1 < chars.count ? chars[i + 1] : " "
            func cjk(_ c: Character) -> Bool { c.unicodeScalars.first.map { (0x3000 ... 0x9FFF).contains($0.value) || (0xFF00 ... 0xFFEF).contains($0.value) } ?? false }
            switch ch {
            case ",": out.append(prev.isNumber && next.isNumber ? "," : "，")
            case ".": out.append(prev.isNumber && next.isNumber ? "." : "。")
            case "?": out.append("？")
            case "!": out.append("！")
            case ":": out.append(prev.isNumber && next.isNumber ? ":" : "：")
            case ";": out.append("；")
            case " " where cjk(prev) || cjk(next) || "，。？！：；".contains(prev): continue
            default: out.append(ch)
            }
        }
        return out
    }
}

/// Ordered final segments + one partial. Final inserts are de-duplicated against overlapping neighbours
/// (re-transcribed windows after a seek, max-length splits, cache merges).
struct LiveSegmentStore: Codable, Equatable {
    private(set) var segments: [LiveSegment] = []
    var partial: LiveSegment?
    /// Media ranges already decoded and transcribed (speech or silence): a rewatch skips them.
    private(set) var covered: [ClosedRange<Double>] = []
    private var nextID = 1

    enum CodingKeys: String, CodingKey { case segments, covered, nextID }
    init() {}

    /// 293: stitch adjacent finals that VAD closed at a short pause (often the 。 between two clauses of one
    /// spoken utterance). Gap ≤ 0.85 s and combined body ≤ 64 → one segment / one Chinese line covering the full span.
    static let adjacentMergeGap = 0.85
    static let adjacentMergeMaxBody = 64

    @discardableResult
    mutating func insert(start: Double, end: Double, ja raw: String, tier: String, arrival: Double? = nil) -> LiveSegment? {
        let ja = LiveText.clean(raw)
        guard !ja.isEmpty, !LiveText.isNoise(ja), end > start else { return nil }
        for (k, s) in segments.enumerated() {
            let overlap = min(s.end, end) - max(s.start, start)
            guard overlap > 0 else { continue }
            let frac = overlap / max(0.01, min(s.end - s.start, end - start))
            if frac > 0.5, LiveText.similarity(s.ja, ja) > 0.55 || s.ja.contains(ja) || ja.contains(s.ja) {
                // Same line: keep the longer text (more context), widen the timing.
                // 293: when JA grows we clear zh and RETURN the segment so translate() re-runs on the full string
                // (previously returned nil → Chinese could stay on the short first recognition until a later tick).
                var grew = false
                if ja.count > s.ja.count { segments[k].ja = ja; segments[k].zh = nil; segments[k].mt = nil; grew = true }
                segments[k].start = min(s.start, start); segments[k].end = max(s.end, end)
                if partial.map({ $0.start < end }) == true { partial = nil }
                return grew ? segments[k] : nil
            }
        }
        // Consecutive duplicates (Whisper repeating the previous line on a silent tail). 291: Whisper only —
        // SenseVoice does not hallucinate repeats, and real repeated short lines (「気持ちいい」×2) were being dropped.
        if tier == LiveASRTier.small.rawValue || tier == LiveASRTier.turbo.rawValue,
           let last = segments.last(where: { $0.end <= start + 0.05 }), start - last.end < 1.5, LiveText.similarity(last.ja, ja) > 0.9 { return nil }
        // 293: merge a clause that follows the previous final within ~0.85 s (VAD pause at 。) into one utterance.
        // Previous must end with 。？！ (clause boundary) or the gap must be ≤ 0.85 s — so two dialogue turns
        // ~1 s apart without a final (e.g. 「一行目です」「二行目です」) stay separate.
        // SenseVoice only: Whisper/Apple harnesses and the 287 paced pipeline expect one segment per VAD cut.
        if tier == LiveASRTier.senseVoice.rawValue,
           let k = segments.indices.last(where: { segments[$0].end <= start + 0.05 }) {
            let gap = start - segments[k].end
            let prev = segments[k]
            let prevFinal = prev.ja.last.map { "。？！?!".contains($0) } ?? false
            if gap <= Self.adjacentMergeGap, prevFinal || gap <= 0.85 {
                let combinedBody = LiveText.clean(prev.ja + ja).filter { !$0.isWhitespace && !"。、，,.！!？?…・♪〜~「」『』（）()　".contains($0) }
                if combinedBody.count <= Self.adjacentMergeMaxBody, LiveText.similarity(prev.ja, ja) < 0.9 {
                    var m = prev
                    let needDot = !prevFinal
                    m.ja = prev.ja + (needDot ? "。" : "") + ja
                    m.end = max(prev.end, end)
                    m.zh = nil; m.mt = nil
                    if let arrival { m.arrival = arrival }
                    segments[k] = m
                    if partial.map({ $0.start < end }) == true { partial = nil }
                    return segments[k]
                }
            }
        }
                let seg = LiveSegment(id: nextID, start: start, end: end, ja: ja, zh: nil, final: true, tier: tier, arrival: arrival)
        nextID += 1
        let idx = segments.firstIndex { $0.start > start } ?? segments.count
        segments.insert(seg, at: idx)
        if partial.map({ $0.start < end }) == true { partial = nil }
        return seg
    }

    mutating func setChinese(id: Int, _ zh: String, engine: String? = nil) {
        if let k = segments.firstIndex(where: { $0.id == id }) { segments[k].zh = zh; segments[k].mt = engine }
    }
    /// 292: translation context — the ≤ `n` previous lines with Chinese, within `window` s before `s`.
    func history(before s: LiveSegment, n: Int = 3, window: Double = 15) -> [(ja: String, zh: String)] {
        let prev = segments.filter { $0.id != s.id && $0.start < s.start && s.start - $0.end <= window && !($0.zh ?? "").isEmpty
            && $0.zh != "（翻译失败）" }
        return prev.suffix(n).map { ($0.ja, $0.zh ?? "") }
    }

    mutating func cover(_ start: Double, _ end: Double) {
        guard end > start else { return }
        var r = start ... end
        var rest: [ClosedRange<Double>] = []
        for c in covered {
            if c.upperBound + 0.05 >= r.lowerBound && c.lowerBound - 0.05 <= r.upperBound {
                r = min(c.lowerBound, r.lowerBound) ... max(c.upperBound, r.upperBound)
            } else { rest.append(c) }
        }
        rest.append(r); covered = rest.sorted { $0.lowerBound < $1.lowerBound }
    }
    mutating func uncover(_ start: Double, _ end: Double) {
        var rest: [ClosedRange<Double>] = []
        for c in covered {
            if c.upperBound <= start || c.lowerBound >= end { rest.append(c); continue }
            if c.lowerBound < start { rest.append(c.lowerBound ... start) }
            if c.upperBound > end { rest.append(end ... c.upperBound) }
        }
        covered = rest
    }
    /// End of the covered run containing `t` (nil if `t` is not covered).
    func coveredEnd(at t: Double) -> Double? { covered.first { $0.contains(t) }?.upperBound }

    func needsChinese() -> [LiveSegment] { segments.filter { $0.zh == nil } }

    /// 291: a line that becomes ready after its own window is still shown, from its arrival, unless it is more
    /// than `lateLimit` seconds stale (then it is counted as dropped-late and only appears on rewatch).
    static let lateLimit = 8.0
    static func lateHold(_ s: LiveSegment) -> Double { min(3.5, max(1.5, (s.end - s.start) * 0.5 + 1.0)) }
    /// Display window(s) for segment `k`: the normal on-time window and, for a late arrival, the clamped one.
    func windows(_ k: Int) -> [(Double, Double)] {
        let s = segments[k]
        let nextStart = k + 1 < segments.count ? segments[k + 1].start : .infinity
        let hold = min(nextStart, max(s.end + 0.8, s.start + 1.2))
        var w = [(s.start - 0.05, hold)]
        if let a = s.arrival, a > hold - 0.3, a - s.end <= Self.lateLimit { w.append((a, a + Self.lateHold(s))) }
        return w
    }
    /// The segment to show at `t` (newest window start wins, so a fresh line replaces a late one).
    func currentSegment(at t: Double) -> LiveSegment? {
        var best: (start: Double, k: Int)?
        for k in segments.indices {
            if segments[k].start > t + 0.05 { break }
            for (a, b) in windows(k) where t >= a && t < b {
                if best == nil || a >= best!.start { best = (a, k) }
            }
        }
        return best.map { segments[$0.k] }
    }
    /// What to draw at media time `t`. A final line stays at least 1.2 s and holds until the next line
    /// (max +0.8 s past its end) so short lines stay readable; late lines are clamped to their arrival.
    func caption(at t: Double, mode: LiveSubtitleMode) -> LiveCaption {
        guard mode != .off else { return .empty }
        if let s = currentSegment(at: t) {
            var c = compose(ja: s.ja, zh: s.zh, partial: false, mode: mode)
            c.machine = s.mt == "llm" && !(c.zh ?? "").isEmpty
            return c
        }
        if let p = partial, t >= p.start - 0.05, t < p.end + 1.5 {
            return compose(ja: p.ja, zh: p.zh, partial: true, mode: mode)
        }
        return .empty
    }
    private func compose(ja: String, zh: String?, partial: Bool, mode: LiveSubtitleMode) -> LiveCaption {
        switch mode {
        case .off: return .empty
        case .japanese: return LiveCaption(ja: ja, zh: nil, partial: partial, pendingChinese: false)
        // 中文: until the translation lands, show the Japanese line dimmed (instant feedback).
        case .chinese: return zh.map { LiveCaption(ja: nil, zh: $0, partial: partial, pendingChinese: false) }
            ?? LiveCaption(ja: ja, zh: nil, partial: partial, pendingChinese: true)
        case .bilingual: return LiveCaption(ja: ja, zh: zh, partial: partial, pendingChinese: zh == nil)
        }
    }
}

/// Per-video cache of final segments (Caches/LiveSubtitles, LRU by file count / bytes).
final class LiveSubtitleCache: @unchecked Sendable {
    static let shared = LiveSubtitleCache()
    let directory: URL
    var maxFiles = 200, maxBytes = 40 << 20
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LiveSubtitles", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }
    static func key(video: String, tier: LiveASRTier) -> String {
        // Online session URLs carry rotating tokens; callers pass 番号+来源 (resume key) when known.
        var h: UInt64 = 0xcbf29ce484222325
        for b in "\(video)#\(tier.rawValue)#v287".utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(format: "%016llx", h)
    }
    func load(_ key: String) -> LiveSegmentStore? {
        let url = directory.appendingPathComponent(key + ".json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return try? JSONDecoder().decode(LiveSegmentStore.self, from: data)
    }
    func save(_ store: LiveSegmentStore, key: String) {
        guard !store.segments.isEmpty, let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: directory.appendingPathComponent(key + ".json"), options: .atomic)
        trim()
    }
    func totalBytes() -> Int { files().reduce(0) { $0 + $1.1 } }
    func clear() { for (u, _, _) in files() { try? FileManager.default.removeItem(at: u) } }
    private func files() -> [(URL, Int, Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        return ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []).compactMap {
            let v = try? $0.resourceValues(forKeys: Set(keys))
            return ($0, v?.fileSize ?? 0, v?.contentModificationDate ?? .distantPast)
        }
    }
    private func trim() {
        var list = files().sorted { $0.2 > $1.2 }
        var bytes = list.reduce(0) { $0 + $1.1 }
        while list.count > maxFiles || bytes > maxBytes, let last = list.popLast() {
            bytes -= last.1; try? FileManager.default.removeItem(at: last.0)
        }
    }
}

// MARK: - Look-ahead scheduling

enum LiveScheduler {
    enum Job: Equatable { case final(Int), partial, idle }
    /// - finals: start times of queued final utterances (in arrival order).
    /// - openStart: start of the utterance still being spoken (decoder side), if any.
    static func next(finals: [Double], ends: [Double]? = nil, openStart: Double?, openLength: Double, playhead: Double,
                     sinceLastPartial: Double, partialHop: Double = 0.8, allowPartial: Bool = true) -> Job {
        if !finals.isEmpty {
            // Lines still on screen (or ahead) first, earliest first; lines the playhead already left are backfill.
            let ends = ends ?? finals
            let live = finals.indices.filter { ends[$0] >= playhead - 1.0 }
            let pool = live.isEmpty ? Array(finals.indices) : live
            return .final(pool.min(by: { finals[$0] < finals[$1] })!)
        }
        // Streaming partials only when the reader is NOT ahead (the playhead is inside the open utterance) and the
        // recogniser is fast enough that a partial cannot delay the next final.
        if allowPartial, let s = openStart, s <= playhead + 0.4, openLength >= 0.7, sinceLastPartial >= partialHop { return .partial }
        return .idle
    }
    /// Reader pacing: keep decoding until `lead` seconds of audio exist beyond the playhead.
    static func readerShouldRun(decodedEnd: Double, playhead: Double, lead: Double, rate: Double) -> Bool {
        decodedEnd < playhead + lead * max(1, rate)
    }
}

// MARK: - Latency ledger

struct LiveLatencyRecord: Codable, Equatable, Sendable {
    var segment: Int
    var start: Double, speechEnd: Double            // media seconds
    var audioReady: Double                          // playhead (media s) when the utterance was closed by the VAD
    var jaReady: Double, zhReady: Double?           // playhead when Japanese / Chinese became displayable
    var firstPartial: Double?                       // playhead when the first partial showed
    var asrMs: Double, mtMs: Double?, queueMs: Double
    var split = false
    /// 291: lateness split. `sourceLag` = the audio itself reached the pipeline late (reader behind the playhead:
    /// slow 2nd HLS connection, restart, stalled pacing) — a faster recognizer cannot fix that. `computeMs` = queue
    /// wait + recognition, the only part a recognizer switch can improve.
    var sourceLag: Double { max(0, audioReady - speechEnd) }
    var computeMs: Double { queueMs + asrMs }
    var computeLate: Bool { computeMs > 2000 }
    /// End of speech → shown (0 = the line was ready before the speaker finished, i.e. in sync).
    var jaLatency: Double { max(0, jaReady - speechEnd) }
    var zhLatency: Double? { zhReady.map { max(0, $0 - speechEnd) } }
    /// Ready before the line starts (look-ahead): shown exactly at speech start.
    var inSync: Bool { (zhReady ?? jaReady) <= start + 0.05 }
}

// MARK: - NLLB tokenizer (SentencePiece BPE, trimmed ja/zh vocabulary) + greedy decoder

struct NLLBVocab: Decodable {
    let srcLen: Int, tgtLen: Int, vocabSize: Int
    let bos: Int, pad: Int, eos: Int, unk: Int
    let jpn_Jpan: Int, zho_Hans: Int, pieceOffset: Int
    let pieces: [[NLLBPieceField]]
    enum NLLBPieceField: Decodable {
        case s(String), d(Double)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let v = try? c.decode(String.self) { self = .s(v) } else { self = .d(try c.decode(Double.self)) }
        }
    }
}

final class NLLBTokenizer {
    let vocab: NLLBVocab
    private var ids: [String: Int] = [:]
    private var scores: [String: Double] = [:]
    private var pieceOf: [Int: String] = [:]
    init(vocab: NLLBVocab) {
        self.vocab = vocab
        for (k, row) in vocab.pieces.enumerated() {
            guard case .s(let p)? = row.first, case .d(let sc)? = row.last else { continue }
            ids[p] = vocab.pieceOffset + k; scores[p] = sc; pieceOf[vocab.pieceOffset + k] = p
        }
    }
    convenience init(json: Data) throws { self.init(vocab: try JSONDecoder().decode(NLLBVocab.self, from: json)) }

    /// [jpn_Jpan] + BPE pieces + [</s>], truncated to srcLen.
    func encode(_ text: String) -> [Int] {
        let norm = text.precomposedStringWithCompatibilityMapping
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let s = "▁" + norm.replacingOccurrences(of: " ", with: "▁")
        var sym = s.map { String($0) }
        while sym.count > 1 {
            var best = -Double.infinity, at = -1
            for i in 0 ..< sym.count - 1 {
                if let sc = scores[sym[i] + sym[i + 1]], sc > best { best = sc; at = i }
            }
            guard at >= 0 else { break }
            sym[at] += sym[at + 1]; sym.remove(at: at + 1)
        }
        var out = [vocab.jpn_Jpan]
        for p in sym { out.append(ids[p] ?? vocab.unk) }
        out.append(vocab.eos)
        if out.count > vocab.srcLen { out = Array(out.prefix(vocab.srcLen - 1)) + [vocab.eos] }
        return out
    }
    func decode(_ tokens: [Int]) -> String {
        let s = tokens.compactMap { pieceOf[$0] }.joined().replacingOccurrences(of: "▁", with: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }
}

enum NLLBGreedy {
    /// `logits(prefix, position)` returns next-token logits for the prefix (padded by the caller).
    /// Starts with [</s>, zho_Hans]; stops at </s>, `tgtLen`, or a 3-gram repeated 3 times.
    static func run(vocab: NLLBVocab, logits: ([Int], Int) throws -> [Float]) rethrows -> [Int] {
        var seq = [vocab.eos, vocab.zho_Hans]
        while seq.count < vocab.tgtLen {
            let l = try logits(seq, seq.count - 1)
            var best = 0, bv = -Float.infinity
            for (i, v) in l.enumerated() where v > bv && i != vocab.pad && i != vocab.unk && i != vocab.bos && i != vocab.jpn_Jpan { bv = v; best = i }
            seq.append(best)
            if best == vocab.eos { break }
            if seq.count >= 11 {
                let tri = Array(seq.suffix(3))
                var reps = 0
                for k in stride(from: seq.count - 3, through: 2, by: -3) where Array(seq[k ..< k + 3]) == tri { reps += 1 }
                if reps >= 3 { seq.removeLast(6); break }
            }
        }
        return seq.filter { $0 != vocab.eos && $0 != vocab.zho_Hans }
    }
}

// MARK: - Pipeline (platform-neutral orchestration)

protocol LiveSpeechRecognizer: AnyObject, Sendable {
    var tier: LiveASRTier { get }
    /// Japanese transcription of 16 kHz mono samples; `prompt` is the previous line (rolling context).
    func transcribe(_ samples: [Float], prompt: String?) async throws -> String
}
protocol LiveTranslating: AnyObject, Sendable {
    var name: String { get }
    func translate(_ japanese: String) async throws -> String
}

/// Thread-safe pipeline state; the decoder thread feeds PCM, a single worker task runs ASR → MT in
/// playhead order. All media times are seconds. Observers read `snapshot` on the main thread.
final class LivePipeline: @unchecked Sendable {
    struct Stats: Equatable, Sendable {
        var decodedEnd = 0.0; var queued = 0; var lastASRms = 0.0; var lastMTms = 0.0; var behind = false
        /// EWMA of ASR milliseconds per final and of the real-time factor (compute seconds / audio seconds).
        var asrMsAvg = 0.0; var rtfAvg = 0.0; var finalsMeasured = 0; var asrMeasured = 0
        /// 291 per-stage counters (whole session; survive seeks and recognizer hot swaps).
        var chunks = 0, audioSec = 0.0, utterances = 0, vadShort = 0, asrErrors = 0, recognizedEmpty = 0, filtered = 0
        var merged = 0, inserted = 0, translated = 0, translateFailed = 0, displayed = 0, droppedLate = 0
        var discardedReset = 0, staleResults = 0, lateArrivals = 0, sourceLate = 0, computeLate = 0
        var sourceLagAvg = 0.0, computeMsAvg = 0.0
        /// 292 translation routing: table answers, skipped moans, LLM lines, Apple/NLLB lines.
        var mtTable = 0, mtSkip = 0, mtLLM = 0, mtClassic = 0
        var mtLine: String { "译 表\(mtTable) 略\(mtSkip) LLM\(mtLLM) 常规\(mtClassic)" }
        var stageLine: String {
            String(format: "分段 块%d 音频%.0fs 语句%d 过短%d · 识别空%d 过滤%d 合并%d 失败%d · 入库%d 翻译%d/失败%d · 显示%d 迟到%d(源%d/算%d) 过期丢弃%d · 重置丢弃%d 过时结果%d · 源滞后%.2fs 计算%.0fms",
                   chunks, audioSec, utterances, vadShort, recognizedEmpty, filtered, merged, asrErrors, inserted, translated,
                   translateFailed, displayed, lateArrivals, sourceLate, computeLate, droppedLate, discardedReset, staleResults,
                   sourceLagAvg, computeMsAvg)
        }
    }
    private let lock = NSLock()
    private var vad = LiveVAD()
    private var finals: [(u: LiveUtterance, wall: Double, playhead: Double)] = []   // queued finals
    private(set) var store = LiveSegmentStore()
    private var lastPartialWall = 0.0
    private var playhead = 0.0
    private var generation = 0
    private var stats = Stats()
    private var records: [Int: LiveLatencyRecord] = [:]
    private var lastPrompt: (end: Double, text: String)?
    private var _mode: LiveSubtitleMode = .bilingual
    private var shownIDs = Set<Int>()
    /// 292: title glossary (actress names from metadata) for the translators.
    private var _glossary: [LiveGlossaryEntry] = []
    var glossary: [LiveGlossaryEntry] { get { locked { _glossary } } set { locked { _glossary = newValue } } }
    var mode: LiveSubtitleMode { get { locked { _mode } } set { locked { _mode = newValue } } }
    var now: () -> Double = { Date().timeIntervalSinceReferenceDate }
    var onChange: (() -> Void)?

    init(store: LiveSegmentStore = LiveSegmentStore()) { self.store = store }

    func locked<T>(_ f: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return f() }
    var snapshotStore: LiveSegmentStore { locked { store } }
    var snapshotStats: Stats { locked { stats } }
    var latency: [LiveLatencyRecord] { locked { records.values.sorted { $0.start < $1.start } } }
    func setPlayhead(_ t: Double) { locked { playhead = t } }
    var currentGeneration: Int { locked { generation } }

    /// Seek / new item: drop queued audio and the VAD state; keep final segments (they are timeline-true).
    func reset(at t: Double) {
        locked {
            generation += 1
            stats.discardedReset += finals.count
            for f in finals { store.uncover(f.u.start, f.u.end) }       // dropped before transcription
            if let open = vad.openStart { store.uncover(open, vad.position) }
            finals = []; vad.reset(at: t); store.partial = nil; stats.decodedEnd = t; records[-1] = nil
            playhead = t; lastPrompt = nil
        }
        onChange?()
    }
    /// Covered-range skip for the reader: returns where decoding should resume, or nil to decode `t`.
    func resumePoint(after t: Double) -> Double? { locked { store.coveredEnd(at: t) } }

    func feed(_ pcm: [Float], start: Double, generation g: Int) {
        lock.lock()
        guard g == generation else { lock.unlock(); return }
        let done = vad.feed(pcm, start: start)
        let end = start + Double(pcm.count) / Double(LiveVAD.rate)
        stats.decodedEnd = end
        stats.chunks += 1; stats.audioSec += Double(pcm.count) / Double(LiveVAD.rate)
        stats.utterances += done.count; stats.vadShort = vad.rejectedShort
        for u in done { finals.append((u, now(), playhead)); store.cover(u.start, u.end) }
        if vad.openStart == nil { store.cover(start, end) }
        stats.queued = finals.count
        lock.unlock()
    }
    func finishStream(generation g: Int) {
        lock.lock(); defer { lock.unlock() }
        guard g == generation, let u = vad.finish() else { return }
        stats.utterances += 1
        finals.append((u, now(), playhead)); store.cover(u.start, u.end)
    }

    /// One unit of work. Returns false when idle.
    func work(asr: LiveSpeechRecognizer, mt: LiveTranslating?) async -> Bool {
        let picked: (g: Int, u: LiveUtterance?, queuedAt: Double, readyAt: Double, prompt: String?) = locked {
            let g = generation
            let job = LiveScheduler.next(finals: finals.map { $0.u.start }, ends: finals.map { $0.u.end }, openStart: vad.openStart,
                                         openLength: vad.openLength, playhead: playhead, sinceLastPartial: now() - lastPartialWall,
                                         allowPartial: stats.asrMeasured == 0 || stats.asrMsAvg < 1000)
            var utterance: LiveUtterance?, queuedAt = now(), readyAt = playhead
            switch job {
            case .final(let k): let f = finals.remove(at: k); utterance = f.u; queuedAt = f.wall; readyAt = f.playhead
            case .partial: utterance = vad.openUtterance(); lastPartialWall = now()
            case .idle: break
            }
            let prompt = utterance.flatMap { u in lastPrompt.flatMap { u.start - $0.end < 6 ? $0.text : nil } }
            stats.queued = finals.count
            stats.behind = vad.openStart.map { $0 <= playhead } ?? false
            return (g, utterance, queuedAt, readyAt, prompt)
        }
        let g = picked.g
        guard let u = picked.u else {
            // Pending translations (e.g. the mode switched to 中文 after lines were recognised).
            if let mt, mode.needsChinese, let seg = locked({ store.needsChinese().first }) { await translate(seg, mt: mt, generation: g); return true }
            return false
        }
        let t0 = now()
        guard let raw = try? await asr.transcribe(u.samples, prompt: u.final ? picked.prompt : nil) else {
            // 291: a failed final is no longer silently "covered" — reopen its range so a rewatch / retry decodes it.
            locked { if u.final { stats.asrErrors += 1; if g == generation { store.uncover(u.start, u.end) } } }
            return true
        }
        let asrMs = (now() - t0) * 1000
        let inserted: LiveSegment? = locked {
            guard g == generation else { if u.final { stats.staleResults += 1 }; return nil }
            stats.lastASRms = asrMs
            stats.asrMsAvg += (stats.asrMeasured == 0 ? 1.0 : 0.3) * (asrMs - stats.asrMsAvg)
            stats.asrMeasured += 1
            if u.final {
                let dur = max(0.3, u.end - u.start)
                stats.rtfAvg += (stats.finalsMeasured == 0 ? 1.0 : 0.3) * (asrMs / 1000 / dur - stats.rtfAvg)
                stats.finalsMeasured += 1
                let cleaned = LiveText.clean(raw)
                if cleaned.isEmpty { stats.recognizedEmpty += 1 } else if LiveText.isNoise(cleaned) { stats.filtered += 1 }
                let s = store.insert(start: u.start, end: u.end, ja: raw, tier: asr.tier.rawValue, arrival: playhead)
                if let s {
                    lastPrompt = (u.end, s.ja)
                    stats.inserted += 1
                    let r = LiveLatencyRecord(segment: s.id, start: s.start, speechEnd: u.speechEnd, audioReady: picked.readyAt,
                                              jaReady: playhead, zhReady: nil, firstPartial: records[-1]?.firstPartial,
                                              asrMs: asrMs, mtMs: nil, queueMs: (t0 - picked.queuedAt) * 1000, split: u.split)
                    records[s.id] = r
                    if records.count > 300, let k = records.keys.filter({ $0 >= 0 }).min() { records[k] = nil }   // 291: bounded ledger (sorted on main 10×/s)
                    let w = stats.inserted == 1 ? 1.0 : 0.2
                    stats.sourceLagAvg += w * (r.sourceLag - stats.sourceLagAvg)
                    stats.computeMsAvg += w * (r.computeMs - stats.computeMsAvg)
                    if r.jaLatency > 2.0 {
                        stats.lateArrivals += 1
                        if r.computeLate { stats.computeLate += 1 } else { stats.sourceLate += 1 }
                    }
                    if playhead - s.end > LiveSegmentStore.lateLimit { stats.droppedLate += 1 }
                } else if !cleaned.isEmpty, !LiveText.isNoise(cleaned) { stats.merged += 1 }
                records[-1] = nil
                return s
            }
            let ja = LiveText.clean(raw)
            if !ja.isEmpty, !LiveText.isNoise(ja) {
                store.partial = LiveSegment(id: 0, start: u.start, end: u.end, ja: ja, zh: nil, final: false, tier: asr.tier.rawValue)
                if records[-1] == nil {
                    records[-1] = LiveLatencyRecord(segment: -1, start: u.start, speechEnd: u.end, audioReady: playhead, jaReady: playhead,
                                                    zhReady: nil, firstPartial: playhead, asrMs: asrMs, mtMs: nil, queueMs: 0)
                }
            }
            return nil
        }
        onChange?()
        if let s = inserted, let mt, mode.needsChinese { await translate(s, mt: mt, generation: g) }
        return true
    }

    private func translate(_ s: LiveSegment, mt: LiveTranslating, generation g: Int) async {
        let t0 = now()
        // 292: tables / moan filter / sentence split / glossary / post-fixes; LLM (when routed) gets the context.
        let context: LiveMTContext = locked {
            LiveMTContext(history: store.history(before: s), glossary: _glossary, budget: max(0, s.start - playhead))
        }
        let plan = LiveMTPrep.plan(s.ja)
        var failed = false, contextual = false
        let zh: String
        do {
            let r = try await LiveMTRunner.runDetailed(s.ja, mt: mt, context: context)
            zh = LiveText.chinesePunctuation(r.zh); contextual = r.contextual
        } catch { zh = ""; failed = true }
        let engine: String
        switch plan {
        case .skip: engine = "skip"
        case .direct: engine = "table"
        case .translate: engine = contextual ? "llm" : "mt"
        }
        let ms = (now() - t0) * 1000
        locked {
            store.setChinese(id: s.id, failed ? "（翻译失败）" : zh, engine: engine)
            switch engine { case "skip": stats.mtSkip += 1; case "table": stats.mtTable += 1; case "llm": stats.mtLLM += 1; default: stats.mtClassic += 1 }
            if failed { stats.translateFailed += 1 } else { stats.translated += 1 }
            stats.lastMTms = ms
            if var r = records[s.id] { r.zhReady = playhead; r.mtMs = ms; records[s.id] = r }
        }
        onChange?()
    }

    func caption(at t: Double) -> LiveCaption {
        locked {
            if _mode != .off, let s = store.currentSegment(at: t), shownIDs.insert(s.id).inserted { stats.displayed += 1 }
            return store.caption(at: t, mode: _mode)
        }
    }
    /// 291: performance verdict for the auto-switch — compute-bound only (RTF or a growing queue whose wait is
    /// the problem), never "the line was late" when the audio itself arrived late.
    func computeBound(recent n: Int = 5) -> (bound: Bool, why: String) {
        locked {
            let recs = records.values.filter { $0.segment >= 0 }.sorted { $0.start < $1.start }.suffix(n)
            let slow = recs.filter(\.computeLate).count
            let bound = stats.finalsMeasured >= 3 && (stats.rtfAvg > 0.7 || (recs.count >= n && slow >= 3 && finals.count >= 3))
            return (bound, String(format: "RTF %.2f 计算迟到 %d/%d 队列 %d 源滞后 %.2fs", stats.rtfAvg, slow, recs.count, finals.count, stats.sourceLagAvg))
        }
    }
}

