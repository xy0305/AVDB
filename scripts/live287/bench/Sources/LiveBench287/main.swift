// Build 287 bench (CI Mac): per-tier Whisper ASR timing + CER, NLLB Core ML timing + parity with the PyTorch
// reference, Apple Translation availability, and end-to-end live latency over a real HLS (look-ahead vs paced,
// plus seek) using the shipping reader / pipeline code. Usage:
//   LiveBench287 <modelsRoot> <workDir> <hlsURL>
import CoreML
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
let modelsRoot = URL(fileURLWithPath: args[1])
let work = URL(fileURLWithPath: args[2])
let hls = URL(string: args[3])!
setenv("AVDB_LIVE_MODELS", modelsRoot.path, 1)

struct Line: Decodable { let ja: String; let zh: String; let start: Double; let end: Double; let raw: String }
let lines = try JSONDecoder().decode([Line].self, from: Data(contentsOf: work.appendingPathComponent("timeline.json")))
struct Ref: Decodable { let ja: String; let zh: String }
let refs = try JSONDecoder().decode([Ref].self, from: Data(contentsOf: modelsRoot.appendingPathComponent("nllb/nllb287_reference.json")))

var report: [String: Any] = [:]
func now() -> Double { Date().timeIntervalSinceReferenceDate }
func normJA(_ s: String) -> [Character] {
    Array(s.precomposedStringWithCompatibilityMapping.filter { !$0.isPunctuation && !$0.isWhitespace && !"。、？！?!「」…".contains($0) })
}
func cer(_ hyp: String, _ ref: String) -> Double {
    let h = normJA(hyp), r = normJA(ref)
    if r.isEmpty { return h.isEmpty ? 0 : 1 }
    if h.isEmpty { return 1 }
    var prev = Array(0 ... h.count)
    for i in 1 ... r.count {
        var cur = [i] + [Int](repeating: 0, count: h.count)
        for j in 1 ... h.count { cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1)) }
        prev = cur
    }
    return Double(prev[h.count]) / Double(r.count)
}
func pcm(_ name: String) throws -> [Float] {
    let d = try Data(contentsOf: work.appendingPathComponent(name))
    return d.withUnsafeBytes { raw in raw.bindMemory(to: Int16.self).map { Float($0) / 32768 } }
}
func fmt(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "-" }

// MARK: 2. NLLB
var nllb: NLLBCoreMLTranslator?
do {
    let t0 = now()
    let m = try NLLBCoreMLTranslator(root: modelsRoot)
    let load = now() - t0
    nllb = m
    _ = try m.translateSync(refs[0].ja)
    var rows: [[String: Any]] = [], total = 0.0, match = 0
    for r in refs {
        let t1 = now()
        let zh = try m.translateSync(r.ja)
        let ms = (now() - t1) * 1000
        let same = zh == LiveText.chinesePunctuation(r.zh)
        if same { match += 1 }
        total += ms
        rows.append(["ja": r.ja, "zh": zh, "torch_zh": r.zh, "parity": same, "ms": ms])
        print(String(format: "NLLB %5.0f ms  %@  %@ (torch %@)", ms, same ? "=" : "≠", zh, r.zh))
    }
    report["nllb"] = ["load_s": load, "avg_ms": total / Double(refs.count), "parity": "\(match)/\(refs.count)", "lines": rows]
    print(String(format: "NLLB load %.1fs  avg %.0f ms/line  parity %d/%d", load, total / Double(refs.count), match, refs.count))
} catch { print("NLLB failed: \(error)"); report["nllb"] = ["error": "\(error)"] }

// MARK: 3. Apple Translation
let apple = await AppleTranslation.status()
var appleReport: [String: Any] = ["status": apple.rawValue]
if apple == .installed, #available(macOS 26.0, *) {
    let a = AppleDirectTranslator()
    var ms: [Double] = []
    for r in refs.prefix(5) {
        let t0 = now()
        if let zh = try? await a.translate(r.ja) { ms.append((now() - t0) * 1000); print("Apple \(zh)") }
    }
    appleReport["ms"] = ms
}
report["apple_translation"] = appleReport
print("Apple Translation ja→zh-Hans: \(apple.rawValue)")

// MARK: 4. End-to-end over HLS
final class Clock: @unchecked Sendable {
    private let lock = NSLock(); private var origin = 0.0, base = 0.0
    func start(at t: Double) { lock.lock(); origin = Date().timeIntervalSinceReferenceDate; base = t; lock.unlock() }
    var time: Double { lock.lock(); defer { lock.unlock() }; return base + Date().timeIntervalSinceReferenceDate - origin }
}

func e2e(name: String, asr: LiveSpeechRecognizer, mt: LiveTranslating?, lead: Double, from: Double) async -> [String: Any] {
    let pipeline = LivePipeline()
    pipeline.mode = .bilingual
    let reader = LiveAudioReader()
    let clock = Clock()
    reader.onPCM = { pcm, start, g in pipeline.feed(pcm, start: start, generation: g) }
    reader.onEnd = { g in pipeline.finishStream(generation: g) }
    reader.onError = { print("reader error \($0)") }
    reader.shouldRun = { LiveScheduler.readerShouldRun(decodedEnd: pipeline.snapshotStats.decodedEnd, playhead: clock.time, lead: lead, rate: 1) }
    clock.start(at: from)
    pipeline.reset(at: from)
    pipeline.setPlayhead(from)
    reader.start(.init(url: hls, headers: ["User-Agent": "AVDB-live287-bench", "Referer": "http://127.0.0.1/"]), at: from, generation: pipeline.currentGeneration)
    let worker = Task.detached(priority: .userInitiated) {
        while !Task.isCancelled { if await !pipeline.work(asr: asr, mt: mt) { try? await Task.sleep(nanoseconds: 30_000_000) } }
    }
    let endAt = (lines.last?.end ?? 30) + 4
    var shown: [String: Double] = [:]          // first time each caption text was displayable at the playhead
    var firstAny: Double?
    while clock.time < endAt {
        let t = clock.time
        pipeline.setPlayhead(t)
        reader.poke()
        let c = pipeline.caption(at: t)
        if !c.isEmpty, firstAny == nil { firstAny = t }
        for key in [c.ja, c.zh].compactMap({ $0 }) where shown[key] == nil { shown[key] = t }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    worker.cancel(); reader.stop()
    let recs = pipeline.latency.filter { $0.segment >= 0 }
    let store = pipeline.snapshotStore
    var rows: [[String: Any]] = []
    print("— E2E \(name): lead \(lead)s from \(from)s, \(recs.count) lines")
    print("  start  spEnd  vadClose  jaReady  zhReady  jaLat  zhLat  asr_ms  mt_ms  queue_ms  inSync  text")
    for r in recs {
        let seg = store.segments.first { $0.id == r.segment }
        print(String(format: "  %5.2f  %5.2f  %8.2f  %7.2f  %7@  %5.2f  %5@  %6.0f  %5@  %8.0f  %@  %@ / %@", r.start, r.speechEnd, r.audioReady, r.jaReady,
                     fmt(r.zhReady), r.jaLatency, fmt(r.zhLatency), r.asrMs, r.mtMs.map { String(format: "%.0f", $0) } ?? "-", r.queueMs,
                     r.inSync ? "yes" : "no ", seg?.ja ?? "", seg?.zh ?? ""))
        rows.append(["start": r.start, "speechEnd": r.speechEnd, "vadClosedAtPlayhead": r.audioReady, "jaReady": r.jaReady, "zhReady": r.zhReady as Any,
                     "jaLatency": r.jaLatency, "zhLatency": r.zhLatency as Any, "asrMs": r.asrMs, "mtMs": r.mtMs as Any, "queueMs": r.queueMs,
                     "inSync": r.inSync, "split": r.split, "ja": seg?.ja ?? "", "zh": seg?.zh ?? ""])
    }
    let zh = recs.compactMap(\.zhLatency)
    let sorted = zh.sorted()
    let summary: [String: Any] = [
        "name": name, "lead": lead, "from": from, "lines": recs.count, "inSync": recs.filter(\.inSync).count,
        "zhLatency_mean": zh.isEmpty ? -1.0 : zh.reduce(0, +) / Double(zh.count),
        "zhLatency_p90": sorted.isEmpty ? -1.0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))],
        "jaLatency_mean": recs.isEmpty ? -1.0 : recs.map(\.jaLatency).reduce(0, +) / Double(recs.count),
        "firstCaptionAfterStart": (firstAny ?? -1.0) - from, "rows": rows,
        "asr_rtf": pipeline.snapshotStats.rtfAvg, "partials_allowed_at_end": pipeline.snapshotStats.asrMsAvg < 1000,
        "asr_ms_mean": recs.isEmpty ? -1.0 : recs.map(\.asrMs).reduce(0, +) / Double(recs.count),
        "mt_ms_mean": recs.compactMap(\.mtMs).isEmpty ? -1.0 : recs.compactMap(\.mtMs).reduce(0, +) / Double(recs.compactMap(\.mtMs).count),
        "queue_ms_mean": recs.isEmpty ? -1.0 : recs.map(\.queueMs).reduce(0, +) / Double(recs.count),
    ]
    print(String(format: "  ⇒ in sync %d/%d · zh latency mean %.2fs p90 %.2fs · ja mean %.2fs · first caption %.2fs after start",
                 recs.filter(\.inSync).count, recs.count, summary["zhLatency_mean"] as! Double, summary["zhLatency_p90"] as! Double,
                 summary["jaLatency_mean"] as! Double, (firstAny ?? -1.0) - from))
    return summary
}

var e2eReport: [[String: Any]] = []
let mid = lines[lines.count / 2].start - 0.5
// MARK: 1. ASR per tier
var asrReport: [[String: Any]] = []
for tier in [LiveASRTier.small, .turbo] {
    guard FileManager.default.fileExists(atPath: modelsRoot.appendingPathComponent(tier.folder).path) else { print("ASR \(tier): model missing"); continue }
    do {
        let r = try await LiveWhisperRecognizer.load(tier)
        _ = try await r.transcribe(try pcm(lines[0].raw), prompt: nil)          // warm-up
        var rows: [[String: Any]] = [], total = 0.0, cerSum = 0.0, audio = 0.0
        for l in lines {
            let s = try pcm(l.raw)
            let t0 = now()
            let text = LiveText.clean(try await r.transcribe(s, prompt: nil))
            let ms = (now() - t0) * 1000
            let c = cer(text, l.ja)
            total += ms; cerSum += c; audio += Double(s.count) / 16000
            rows.append(["ref": l.ja, "hyp": text, "ms": ms, "cer": c, "audio_s": Double(s.count) / 16000])
            print(String(format: "ASR %@  %6.0f ms  CER %.2f  %@ | %@", tier.title, ms, c, text, l.ja))
        }
        let avg = total / Double(lines.count)
        asrReport.append(["tier": tier.rawValue, "folder": tier.folder, "load_s": r.loadSeconds, "avg_ms": avg,
                          "rtf": total / 1000 / audio, "mean_cer": cerSum / Double(lines.count), "lines": rows])
        print(String(format: "ASR %@ load %.1fs  avg %.0f ms/line  RTF %.3f  mean CER %.3f", tier.title, r.loadSeconds, avg, total / 1000 / audio, cerSum / Double(lines.count)))
        // One tier resident at a time (as on device): end-to-end runs with this tier, then it is released.
        e2eReport.append(await e2e(name: "\(tier.rawValue)-lookahead", asr: r, mt: nllb, lead: 20, from: 0))
        e2eReport.append(await e2e(name: "\(tier.rawValue)-paced", asr: r, mt: nllb, lead: 0.25, from: 0))
        e2eReport.append(await e2e(name: "\(tier.rawValue)-seek-mid", asr: r, mt: nllb, lead: 20, from: mid))
    } catch { print("ASR \(tier) failed: \(error)"); asrReport.append(["tier": tier.rawValue, "error": "\(error)"]) }
}
report["asr"] = asrReport

report["e2e"] = e2eReport
report["host"] = ProcessInfo.processInfo.hostName
report["note"] = "GitHub macOS runner = virtualised Apple M1: Core ML runs CPU-only (no ANE/GPU). iPhone Neural Engine timings are NOT measured here."
let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try json.write(to: work.appendingPathComponent("bench287.json"))
print("wrote bench287.json")
