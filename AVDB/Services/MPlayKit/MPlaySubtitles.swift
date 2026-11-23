//
//  MPlaySubtitles.swift
//  AVDB
//
//  Build 353 (full restoration): the subtitle settings / style /
//  translation surface of the original Player, item by item.
//
//  Landed for real (mpv properties or our own layer):
//   * SubtitleSettings application — track selection (sid /
//     secondary-sid), visibility, fonts directory.
//   * subtitles(primary:secondary:), setSubtitleDelay(_:secondary:)
//     (sub-delay / secondary-sub-delay are both real mpv properties).
//   * style(_:secondary:) — sub-font-size / sub-color / sub-back-color
//     / sub-bold for the primary track; mpv has no secondary style
//     properties, so secondary styling is recorded, not applied
//     (documented in Build353-MPlayKit.md).
//   * setSubtitleHDR — brightness gain on the independent subtitle
//     layer (premultiplied-bitmap re-exposure, MPlaySubtitleLayer).
//   * setSubtitleVerticalOffset — sub-pos.
//   * Translation pipeline for FILE-based subtitle tracks (the
//     AVDB case: downloaded online subtitles): cues are translated
//     through an injected provider, written as a new file and added
//     as a track.  No provider ships with AVDB (no translation
//     backend or credential exists in the app), so without one the
//     entry points return MPV_ERROR_NOT_IMPLEMENTED (-18) — the API
//     and the file pipeline are real, the translation service is
//     not bundled.  Embedded (non-file) tracks cannot be translated
//     this way and also return -18, with the reason logged.
//   * chineseConversion (simplified/traditional): the flag lives in
//     SubtitleSettings and the converter below is applied to live
//     subtitle snapshots; the table is a compact common-character
//     set, NOT a full OpenCC dictionary — coverage is partial by
//     construction and documented as such.
//

import Foundation

/// Style override for one subtitle track (the original's customStyle
/// element shape).
struct MPlaySubtitleStyle {
    var fontSize: Double?
    var textColor: String?       // "#RRGGBB" or "#AARRGGBB"
    var backgroundColor: String?
    var bold: Bool?

    init(fontSize: Double? = nil, textColor: String? = nil,
         backgroundColor: String? = nil, bold: Bool? = nil) {
        self.fontSize = fontSize
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.bold = bold
    }
}

/// The original's SubtitleSettings field set, verbatim names.
struct SubtitleSettings {
    var primary: Int64 = -1          // track id; -1 = none
    var secondary: Int64 = -1
    var secondaryActive: Bool = false
    var visible: Bool = true
    var fontProvider: String = ""    // recorded; mpv uses CoreText on iOS
    var fontsDirectory: String? = nil
    var aspect: Double = 0           // recorded; no mpv equivalent
    var chineseConversion: Int = 0   // 0 off, 1 simplified->traditional, 2 reverse
    var customStyle: MPlaySubtitleStyle? = nil
    var removeBreaks: Bool = false   // applied on the snapshot path
    var secondarySpacing: Double = 0 // applied as secondary-sub-pos offset
}

// MARK: - Simplified/traditional conversion (compact table)

/// A compact common-character conversion table (~140 pairs).  This
/// is deliberately NOT a full dictionary: it covers the characters
/// that dominate subtitle text, and the docs state the partial
/// coverage plainly.
enum MPlayChineseConversion {
    private static let simplifiedToTraditional: [Character: Character] = {
        let simplified = "国这来个们为发时过进远运还进过这说对没还让给当从将应开关闭问问题间闻门们里长门风马鱼鸟龙马车东乐书买卖读话语说请谢谁边这过还进远运达迟"
        let traditional = "國這來個們為發時過進遠運還進過這說對沒還讓給當從將應開關閉問問題間聞門們裡長門風馬魚鳥龍馬車東樂書買賣讀話語說請謝誰邊這過還進遠運達遲"
        var table: [Character: Character] = [:]
        for (s, t) in zip(simplified, traditional) { table[s] = t }
        // Additional high-frequency pairs, written explicitly to
        // keep the two strings above auditable.
        let extra: [(Character, Character)] = [
            ("爱", "愛"), ("听", "聽"), ("见", "見"), ("观", "觀"),
            ("觉", "覺"), ("认", "認"), ("识", "識"), ("记", "記"),
            ("讲", "講"), ("论", "論"), ("设", "設"), ("计", "計"),
            ("让", "讓"), ("训", "訓"), ("议", "議"), ("译", "譯"),
            ("选", "選"), ("连", "連"), ("断", "斷"), ("续", "續"),
            ("点", "點"), ("线", "線"), ("红", "紅"), ("绿", "綠"),
            ("蓝", "藍"), ("黄", "黃"), ("银", "銀"), ("钱", "錢"),
            ("铁", "鐵"), ("钢", "鋼"), ("电", "電"), ("脑", "腦"),
            ("机", "機"), ("场", "場"), ("图", "圖"), ("画", "畫"),
            ("声", "聲"), ("乐", "樂"), ("气", "氣"), ("热", "熱"),
            ("冷", "冷"), ("开", "開"), ("关", "關"), ("门", "門"),
            ("问", "問"), ("间", "間"), ("闻", "聞"), ("阳", "陽"),
            ("阴", "陰"), ("云", "雲"), ("雨", "雨"), ("雪", "雪"),
            ("风", "風"), ("龙", "龍"), ("马", "馬"), ("鱼", "魚"),
            ("鸟", "鳥"), ("车", "車"), ("东", "東"), ("西", "西"),
            ("南", "南"), ("北", "北"), ("长", "長"), ("万", "萬"),
            ("与", "與"), ("专", "專"), ("业", "業"), ("丛", "叢"),
            ("个", "個"), ("么", "麼"), ("为", "為"), ("产", "產"),
            ("亲", "親"), ("从", "從"), ("仅", "僅"), ("仓", "倉"),
        ]
        for (s, t) in extra { table[s] = t }
        return table
    }()

    private static let traditionalToSimplified: [Character: Character] = {
        var table: [Character: Character] = [:]
        for (s, t) in simplifiedToTraditional { table[t] = s }
        return table
    }()

    /// direction: 1 = simplified→traditional, 2 = traditional→
    /// simplified, anything else = identity.
    static func convert(_ text: String, direction: Int) -> String {
        let table: [Character: Character]
        switch direction {
        case 1: table = simplifiedToTraditional
        case 2: table = traditionalToSimplified
        default: return text
        }
        return String(text.map { table[$0] ?? $0 })
    }
}

// MARK: - Translation provider + engine

/// A translation backend the host may inject.  AVDB ships none;
/// the engine's entry points report -18 until one is set.
protocol MPlaySubtitleTranslating: AnyObject {
    func translate(_ text: String, from sourceLanguage: String,
                   to targetLanguage: String) async -> String?
}

struct MPlayLiveSubtitleSnapshot {
    var original: String
    var translated: String?
    var track: Int64
}

/// Translates file-based subtitle tracks cue by cue.  Holds the
/// translation-target bookkeeping behind translationTrack /
/// clearTranslation.
final class MPlaySubtitleTranslationEngine {
    static let shared = MPlaySubtitleTranslationEngine()

    /// Injected by the host; nil in AVDB today (no backend).
    var provider: MPlaySubtitleTranslating?

    private let lock = NSLock()
    private var targets: [Int64: (sourceTrack: Int64, file: URL)] = [:]
    private var nextTargetID: Int64 = -1000

    /// Parses an SRT file into (index, timing line, text) triples.
    /// WebVTT / ASS are not parsed here (documented scope).
    static func parseSRT(_ content: String)
        -> [(timing: String, text: String)] {
        var cues: [(String, String)] = []
        let blocks = content.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") })
            else { continue }
            let timing = lines[timingIndex]
            let text = lines[(timingIndex + 1)...].joined(separator: "\n")
            cues.append((timing, text))
        }
        return cues
    }

    static func renderSRT(_ cues: [(timing: String, text: String)]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(cue.timing)\n\(cue.text)"
        }.joined(separator: "\n\n") + "\n"
    }

    /// Translates a subtitle FILE through the provider and writes
    /// the result next to it; returns the new file URL.
    func translateFile(_ file: URL, from sourceLanguage: String,
                       to targetLanguage: String) async -> URL? {
        guard let provider else { return nil }
        guard let content = try? String(contentsOf: file, encoding: .utf8)
        else { return nil }
        let cues = Self.parseSRT(content)
        guard !cues.isEmpty else { return nil }
        var translated: [(timing: String, text: String)] = []
        translated.reserveCapacity(cues.count)
        for cue in cues {
            let result = await provider.translate(
                cue.text, from: sourceLanguage, to: targetLanguage)
            translated.append((cue.timing, result ?? cue.text))
        }
        let output = file.deletingPathExtension()
            .appendingPathExtension("\(targetLanguage).srt")
        do {
            try Self.renderSRT(translated).write(
                to: output, atomically: true, encoding: .utf8)
            return output
        } catch {
            MPlayDiagnostics.log("subtitle translation write failed: \(error)")
            return nil
        }
    }

    func registerTarget(sourceTrack: Int64, file: URL) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        nextTargetID -= 1
        targets[nextTargetID] = (sourceTrack, file)
        return nextTargetID
    }

    func clearTarget(sourceTrack: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let keys = targets.filter { $0.value.sourceTrack == sourceTrack }.map(\.key)
        for key in keys { targets.removeValue(forKey: key) }
        return !keys.isEmpty
    }
}

// MARK: - Player surface

extension MPlayPlayer {
    /// Applies a SubtitleSettings wholesale (the original's
    /// setSubtitleSettings(_:source:completion:) semantics; our core
    /// is single-source, so the source dimension collapses).
    func setSubtitleSettings(_ settings: SubtitleSettings) {
        setProp("sub-visibility", settings.visible ? "yes" : "no")
        if let dir = settings.fontsDirectory {
            setProp("sub-fonts-dir", dir)
        }
        selectTrack(kind: .subtitle, id: settings.primary)
        if settings.secondaryActive {
            selectTrack(kind: .subtitleSecondary, id: settings.secondary)
            if settings.secondarySpacing != 0 {
                // mpv positions the secondary track independently;
                // spacing shifts it up from the bottom default (98).
                let pos = min(150, max(0, 98 - settings.secondarySpacing))
                setProp("secondary-sub-pos", String(pos))
            }
        }
        if let style = settings.customStyle {
            _ = self.style(style, secondary: false)
        }
        currentSubtitleSettings = settings
    }

    /// The last settings applied via setSubtitleSettings (also the
    /// source of the chineseConversion / removeBreaks flags used on
    /// the snapshot path).
    var currentSubtitleSettings: SubtitleSettings {
        get { subtitleSettingsStorage }
        set { subtitleSettingsStorage = newValue }
    }

    /// Selects the primary + secondary subtitle tracks together
    /// (the original's subtitles(primary:secondary:)).
    func subtitles(primary: Int64, secondary: Int64) {
        selectTrack(kind: .subtitle, id: primary)
        selectTrack(kind: .subtitleSecondary, id: secondary)
    }

    /// sub-delay / secondary-sub-delay (both real mpv properties).
    func setSubtitleDelay(_ delay: Double, secondary: Bool) {
        setProp(secondary ? "secondary-sub-delay" : "sub-delay",
                String(delay))
    }

    /// HDR gain for subtitle bitmaps (the original's setSubtitleHDR):
    /// gain 1.5 at level 1.0 by default shape; the value is forwarded
    /// to the attached view's subtitle layer.
    func setSubtitleHDR(enabled: Bool, sourceHDR: Bool, level: Double) {
        let gain = enabled ? (sourceHDR ? 1 + 0.5 * max(0, level) : 1.0) : 1.0
        onSubtitleGainChange?(gain)
    }

    /// Subtitle layer opacity.  mpv has no global subtitle opacity
    /// property; the value is applied to the subtitle layer itself
    /// through the gain channel's sibling sink.
    func setSubtitleOpacity(_ opacity: Double) {
        onSubtitleOpacityChange?(min(1, max(0, opacity)))
    }

    /// Vertical offset as a fraction of the frame height, mapped
    /// onto sub-pos (100 = bottom default).
    func setSubtitleVerticalOffset(_ offset: Double) {
        let pos = min(150, max(0, 100 - offset * 100))
        setProp("sub-pos", String(pos))
    }

    /// Edge processing (faux-bold / outline enhancement) is an
    /// AVKit text-style concept; libass bitmaps have no equivalent
    /// switch.  Recorded and logged — no landing (see docs).
    func setSubtitleEdgeProcessingEnabled(_ enabled: Bool) {
        subtitleEdgeProcessingEnabled = enabled
        MPlayDiagnostics.log(
            "subtitle edge processing \(enabled) recorded; no libass equivalent")
    }

    /// Applies a style override.  Primary-track properties are real;
    /// mpv exposes no secondary-sub font/color properties, so the
    /// secondary call is recorded only (documented).
    @discardableResult
    func style(_ style: MPlaySubtitleStyle, secondary: Bool) -> Int32 {
        if secondary {
            MPlayDiagnostics.log("secondary subtitle style recorded; mpv has no secondary style properties")
            return 0
        }
        if let size = style.fontSize { setProp("sub-font-size", String(size)) }
        if let color = style.textColor { setProp("sub-color", color) }
        if let back = style.backgroundColor { setProp("sub-back-color", back) }
        if let bold = style.bold { setProp("sub-bold", bold ? "yes" : "no") }
        return 0
    }

    // MARK: Translation

    /// The original's translateSubtitles(_:source:track:).  Landed
    /// for external-file tracks through the injected provider;
    /// -18 without a provider or for embedded tracks.
    func translateSubtitles(
        options: [String: String], track: Int64
    ) async -> Int32 {
        let engine = MPlaySubtitleTranslationEngine.shared
        guard engine.provider != nil else { return -18 }
        guard let file = externalSubtitleFile(track: track) else {
            MPlayDiagnostics.log(
                "translateSubtitles: track \(track) is not an external file; unsupported")
            return -18
        }
        let target = options["targetLanguage"] ?? options["language"] ?? "zh"
        let source = options["sourceLanguage"] ?? "auto"
        guard let output = await engine.translateFile(
            file, from: source, to: target) else { return -19 }
        addSubtitle(url: output.path, select: true)
        return 0
    }

    /// Creates a translation target for a track (the original's
    /// translationTrack(source:input:title:language:secondary:
    /// original:)): translates the track's file now and registers
    /// the result; returns the engine-local target id, or -1 when
    /// translation is unavailable.
    func translationTrack(
        input: Int64, title: String, language: String,
        secondary: Bool, original: Bool
    ) async -> Int64 {
        let engine = MPlaySubtitleTranslationEngine.shared
        guard engine.provider != nil,
              let file = externalSubtitleFile(track: input),
              let output = await engine.translateFile(
                file, from: "auto", to: language) else { return -1 }
        addSubtitle(url: output.path, title: title, select: !secondary)
        return engine.registerTarget(sourceTrack: input, file: output)
    }

    /// Snapshot of the currently displayed subtitle text, translated
    /// when a provider exists, with chineseConversion / removeBreaks
    /// from the current settings applied on the snapshot path.
    func liveSubtitles(track: Int64) async -> MPlayLiveSubtitleSnapshot? {
        guard let text = stringProperty("sub-text"), !text.isEmpty
        else { return nil }
        var original = text
        if currentSubtitleSettings.removeBreaks {
            original = original.replacingOccurrences(of: "\n", with: " ")
        }
        if currentSubtitleSettings.chineseConversion != 0 {
            original = MPlayChineseConversion.convert(
                original,
                direction: currentSubtitleSettings.chineseConversion)
        }
        var translated: String?
        if let provider = MPlaySubtitleTranslationEngine.shared.provider {
            translated = await provider.translate(original, from: "auto", to: "zh")
        }
        return MPlayLiveSubtitleSnapshot(
            original: original, translated: translated, track: track)
    }

    /// Drops translation targets created for a track.
    @discardableResult
    func clearTranslation(track: Int64) async -> Int32 {
        MPlaySubtitleTranslationEngine.shared.clearTarget(sourceTrack: track)
            ? 0 : -3
    }

    /// The on-disk file behind an external subtitle track, via the
    /// track-list external-filename sub-property; nil for embedded
    /// tracks.
    func externalSubtitleFile(track: Int64) -> URL? {
        let json = mediaJSON()
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let tracks = root["tracks"] as? [[String: Any]] else {
            return nil
        }
        for entry in tracks {
            guard (entry["kind"] as? String) == "subtitle",
                  (entry["id"] as? NSNumber)?.int64Value == track,
                  (entry["external"] as? Bool) == true,
                  let filename = entry["externalFilename"] as? String,
                  !filename.isEmpty
            else { continue }
            return URL(fileURLWithPath: filename)
        }
        return nil
    }
}
