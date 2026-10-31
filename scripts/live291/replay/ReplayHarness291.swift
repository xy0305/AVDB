// Build 291 replay harness: the shipping LiveSubtitleCore (290 or 291 revision) + the real SenseVoice recognizer
// (sherpa-onnx C API), driven by a discrete-event emulation of LiveSubtitleEngine on a virtual clock (playback 1×).
// Recognition really runs; its measured compute time × `factor` advances the virtual clock (device RTF scaling).
import Foundation

let A = CommandLine.arguments
func arg(_ k: String, _ d: String) -> String { if let i = A.firstIndex(of: "--" + k), i + 1 < A.count { return A[i + 1] }; return d }
let wavPath = arg("wav", ""), outPath = arg("out", "out.json"), version = arg("version", "291")
let scenario = arg("scenario", "device")              // device = user's 290 diagnostics conditions; clean = none
let factor = Double(arg("factor", "1"))!, lead = Double(arg("lead", "8"))!
let duration = Double(arg("duration", "600"))!
let v291 = version == "291"

func loadWav(_ p: String) -> [Float] {
    let d = try! Data(contentsOf: URL(fileURLWithPath: p))
    var off = 12
    while off + 8 < d.count {
        let id = String(decoding: d[off ..< off + 4], as: UTF8.self)
        let size = Int(d[off + 4]) | Int(d[off + 5]) << 8 | Int(d[off + 6]) << 16 | Int(d[off + 7]) << 24
        if id == "data" {
            let body = d[(off + 8) ..< min(d.count, off + 8 + size)]
            return body.withUnsafeBytes { raw in raw.bindMemory(to: Int16.self).map { Float($0) / 32768 } }
        }
        off += 8 + size
    }
    return []
}
let audio = loadWav(wavPath)
let audioEnd = min(duration, Double(audio.count) / 16000)

// Deterministic event schedule (same for both versions).
struct RNG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }
var rng = RNG(s: 291)
var flaps: [Double] = []          // thermal fair↔serious flips (user log: start target=… every ~20–60 s)
var hangs: [(Double, Double)] = [] // main-thread hangs (user log: 21 hitches, worst 8351 ms)
if scenario == "device" {
    var t = 15.0
    while t < audioEnd { t += 20 + 40 * rng.next(); flaps.append(t) }
    hangs.append((62, 8.35))                                     // the "~1 min" report
    var h = 20.0
    while h < audioEnd { h += 45 + 60 * rng.next(); if abs(h - 62) > 12 { hangs.append((h, 1.0 + 2.5 * rng.next())) } }
}
let openLatency = scenario == "device" ? 2.5 : 1.0               // new HLS session (2nd connection) before first audio
let seekLatency = scenario == "device" ? 1.0 : 0.5
let readerSpeed = 4.0                                            // × realtime download+decode when allowed to run
// Source throughput dips (2nd HLS connection competing with the player's own prefetch on a busy link): the reader
// gets only `dipSpeed`× realtime inside these windows. Same schedule for both versions.
var dips: [(Double, Double)] = []
if scenario == "device" { dips.append((50, 30)); var d = 150.0; while d < audioEnd { dips.append((d, 15)); d += 100 } }
let dipSpeed = Double(arg("dip", "0.6"))!

// MARK: world
final class World: @unchecked Sendable {
    var t = 0.0
    var pipeline = LivePipeline()
    var pipelines: [LivePipeline] = []
    var enginePlayhead = 0.0, lastTickWall = 0.0, nextTick = 0.0
    var readerCarry = 0.0
    var readerPos = 0.0, readerOpenUntil = openLatency, finished = false, readerGen = 0
    var saved = LiveSegmentStore(), lastSaved = 0
    var display: [(Double, String)] = []           // (t, ja) sampled every tick (UI visible text)
    var fed: [(Double, Double)] = []               // decoded audio ranges
    var mirror = LiveVAD()
    var utts: [String: (Double, Double)] = [:]
    var uttLog: [(Double, Double, Int)] = []      // (start, end, pipelineIndex)
    var asrLog: [[String: Any]] = []
    var events: [String] = []
    var restarts = 0, catchUps = 0, perfSwitch = false
    var nextFlap = 0, nextGuard = 5.0
    var lateRecs: [Double] = []

    func key(_ s: [Float]) -> String { "\(s.count)-\(s.prefix(32).reduce(0) { $0 + Double($1) })" }
    func hung(_ x: Double) -> Bool { hangs.contains { x >= $0.0 && x < $0.0 + $0.1 } }
    func newPipeline(store: LiveSegmentStore) {
        let p = LivePipeline(store: store); p.mode = .japanese; p.now = { [unowned self] in self.t }
        pipeline = p; pipelines.append(p)
    }
    var pace: Double { v291 ? enginePlayhead + min(30, t - lastTickWall) : enginePlayhead }

    func advance(by dt: Double) { let end = t + dt; while t < end - 1e-9 { step(min(0.02, end - t)) } }
    func step(_ h: Double) {
        t += h
        if nextFlap < flaps.count, t >= flaps[nextFlap] {
            nextFlap += 1
            if v291 { events.append(String(format: "%.1f thermal flip → no-op (SenseVoice stays)", t)) }
            else { restart(String(format: "thermal flip %.1f", t)) }
        }
        if !hung(t), t >= nextTick { tick(); nextTick = t + 0.1 }
        readerStep(h)
    }
    func tick() {
        enginePlayhead = t; lastTickWall = t
        pipeline.setPlayhead(t)
        let c = pipeline.caption(at: t)
        display.append((t, c.ja ?? ""))
        let st = pipeline.snapshotStore
        if st.segments.count >= lastSaved + 8 { saved = st; lastSaved = st.segments.count }
        if v291, pipeline.snapshotStats.decodedEnd < t - 6, t - (Double(catchUps) > 0 ? lastCatch : -99) > 10, t > 5 {
            lastCatch = t; catchUps += 1; events.append(String(format: "%.1f reader catch-up from %.1f", t, pipeline.snapshotStats.decodedEnd))
            seek(t)
        }
        if t >= nextGuard { nextGuard += 5; checkPerformance() }
    }
    var lastCatch = -99.0
    func checkPerformance() {
        guard !perfSwitch else { return }
        #if V291
        let v = pipeline.computeBound()
        if v.bound { perfSwitch = true; events.append(String(format: "%.1f compute-bound → hot swap (%@)", t, v.why)) }
        return
        #else
        
        let st = pipeline.snapshotStats
        let recent = pipeline.latency.filter { $0.segment >= 0 }.suffix(5)
        let late = recent.filter { $0.jaLatency > 2.0 }.count
        if st.finalsMeasured >= 3, st.rtfAvg > 0.7 || (recent.count >= 5 && late >= 3) {
            perfSwitch = true
            events.append(String(format: "%.1f 290 lateness switch: RTF %.2f late %d/5 → apple (restart)", t, st.rtfAvg, late))
            restart("perf switch")
        }
        #endif
    }
    /// 290 LiveSubtitleEngine.start(): stopRunning, new pipeline from the last saved cache, reader reopened at the playhead.
    func restart(_ why: String) {
        restarts += 1
        newPipeline(store: saved)
        let now = enginePlayhead
        let from = pipeline.resumePoint(after: now) ?? now
        pipeline.reset(at: from); pipeline.setPlayhead(now)
        mirror.reset(at: from)
        readerPos = from; readerOpenUntil = t + openLatency
        events.append(String(format: "%.1f restart (%@) reader from %.1f", t, why, from))
    }
    func seek(_ at: Double) {
        let from0 = v291 ? max(0, at - 0.5) : at
        let from = pipeline.resumePoint(after: from0) ?? from0
        pipeline.reset(at: from); pipeline.setPlayhead(at); mirror.reset(at: from)
        readerPos = from; readerOpenUntil = t + seekLatency
    }
    func readerStep(_ h: Double) {
        guard t >= readerOpenUntil, !finished else { return }
        let inDip = dips.contains { t >= $0.0 && t < $0.0 + $0.1 }
        readerCarry += h * (inDip ? dipSpeed : readerSpeed)
        var budget = readerCarry
        while budget > 0, readerPos < pace + lead {
            if readerPos >= audioEnd { pipeline.finishStream(generation: pipeline.currentGeneration); finished = true; return }
            let i0 = Int(readerPos * 16000), i1 = min(audio.count, i0 + 4000)
            let chunk = Array(audio[i0 ..< i1])
            for u in mirror.feed(chunk, start: readerPos) { utts[key(u.samples)] = (u.start, u.end); uttLog.append((u.start, u.end, pipelines.count - 1)) }
            pipeline.feed(chunk, start: readerPos, generation: pipeline.currentGeneration)
            fed.append((readerPos, readerPos + Double(chunk.count) / 16000))
            readerPos += Double(chunk.count) / 16000; budget -= 0.25; readerCarry -= 0.25
        }
        if readerPos >= pace + lead { readerCarry = min(readerCarry, 0) }
        if ProcessInfo.processInfo.environment["DBG"] != nil, Int(t * 50) % 250 == 0 { print(String(format: "t %.1f pos %.1f pace %.1f dip %d", t, readerPos, pace, inDip ? 1 : 0)) }
    }
}
let world = World()
world.newPipeline(store: LiveSegmentStore())
if v291 { world.pipeline.reset(at: 0) }

final class SimASR: LiveSpeechRecognizer, @unchecked Sendable {
    let tier: LiveASRTier = .senseVoice
    let inner: SenseVoiceRecognizer
    init(_ i: SenseVoiceRecognizer) { inner = i }
    func transcribe(_ samples: [Float], prompt: String?) async throws -> String {
        let t0 = Date()
        let r = try await inner.transcribe(samples, prompt: prompt)
        let c = Date().timeIntervalSince(t0)
        let u = world.utts[world.key(samples)]
        world.asrLog.append(["t": world.t, "start": u?.0 ?? -1, "end": u?.1 ?? -1, "dur": Double(samples.count) / 16000, "computeS": c * factor,
                             "raw": r, "final": u != nil, "pipe": world.pipelines.count - 1])
        world.advance(by: c * factor)
        return r
    }
}
final class SimMT: LiveTranslating, @unchecked Sendable {
    let name = "sim"
    func translate(_ japanese: String) async throws -> String { world.advance(by: 0.3); return "zh" }
}
let sv = try! SenseVoiceRecognizer(folder: URL(fileURLWithPath: arg("model", "")), threads: 2)
let asr = SimASR(sv)
let sem = DispatchSemaphore(value: 0)
Task {
    while world.t < audioEnd + 3 {
        if await !world.pipeline.work(asr: asr, mt: nil) { world.advance(by: 0.04) }
    }
    sem.signal()
}
sem.wait()

// Output
var segs: [[String: Any]] = []
for (pi, p) in world.pipelines.enumerated() {
    for s in p.snapshotStore.segments {
        segs.append(["pipe": pi, "id": s.id, "start": s.start, "end": s.end, "ja": s.ja])
    }
}
var disp: [[String: Any]] = []
var cur: (Double, String)? = nil
for (t, ja) in world.display {
    if cur?.1 != ja { if let c = cur, !c.1.isEmpty { disp.append(["start": c.0, "end": t, "ja": c.1]) }; cur = (t, ja) }
}
if let c = cur, !c.1.isEmpty { disp.append(["start": c.0, "end": world.t, "ja": c.1]) }
var lat: [[String: Any]] = []
for r in world.pipeline.latency where r.segment >= 0 {
    lat.append(["start": r.start, "speechEnd": r.speechEnd, "audioReady": r.audioReady, "jaReady": r.jaReady, "asrMs": r.asrMs, "queueMs": r.queueMs])
}
var o: [String: Any] = ["version": version, "scenario": scenario, "factor": factor, "lead": lead, "restarts": world.restarts, "catchUps": world.catchUps,
                        "events": world.events, "segments": segs, "display": disp, "asr": world.asrLog, "latency": lat,
                        "utterances": world.uttLog.map { ["start": $0.0, "end": $0.1, "pipe": $0.2] },
                        "fed": world.fed.map { [$0.0, $0.1] }, "hangs": hangs.map { [$0.0, $0.1] }, "dips": dips.map { [$0.0, $0.1] }, "flaps": flaps]
#if V291
o["stageLine"] = world.pipeline.snapshotStats.stageLine
#endif
let data = try! JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted])
try! data.write(to: URL(fileURLWithPath: outPath))
print("done", version, scenario, "restarts", world.restarts, "segments", segs.count, "display", disp.count)
