// Build 291 regression: late-but-valid lines display, lateness split (source vs compute), per-stage counters,
// VAD under background music, the max-length-split crash, stale Whisper preference, guard policy.
import Foundation
var failures = 0
func check(_ c: @autoclosure () -> Bool, _ m: String) { if !c() { failures += 1; print("FAIL", m) } else { print("PASS", m) } }

// 1. Late line is shown from its arrival (clamped), not dropped; on time lines unchanged; > lateLimit = not shown live.
var st = LiveSegmentStore()
st.insert(start: 10, end: 12, ja: "遅れて届いた行", tier: "sensevoice", arrival: 14.5)
check(st.caption(at: 11, mode: .japanese).ja == "遅れて届いた行", "on-time window still works (rewatch)")
check(st.caption(at: 14.6, mode: .japanese).ja == "遅れて届いた行", "late line shown at arrival")
check(st.caption(at: 14.5 + LiveSegmentStore.lateHold(st.segments[0]) + 0.05, mode: .japanese).ja == nil, "late hold ends")
st.insert(start: 30, end: 31, ja: "古すぎる行", tier: "sensevoice", arrival: 31 + LiveSegmentStore.lateLimit + 1)
check(st.caption(at: 31 + LiveSegmentStore.lateLimit + 1.2, mode: .japanese).ja == nil, "> lateLimit stale lines are not shown live")
// A fresh on-time line replaces a late one.
var st2 = LiveSegmentStore()
st2.insert(start: 5, end: 6, ja: "前の行", tier: "sensevoice", arrival: 7.5)
st2.insert(start: 8, end: 9, ja: "次の行", tier: "sensevoice", arrival: 7.9)
check(st2.caption(at: 8.1, mode: .japanese).ja == "次の行", "newer line wins over late hold")
// Real repeats are kept for SenseVoice (Whisper still deduped).
var st3 = LiveSegmentStore()
st3.insert(start: 1, end: 2, ja: "気持ちいい", tier: "sensevoice"); st3.insert(start: 2.3, end: 3.2, ja: "気持ちいい", tier: "sensevoice")
check(st3.segments.count == 2, "SenseVoice repeated short line kept")
var st4 = LiveSegmentStore()
st4.insert(start: 1, end: 2, ja: "気持ちいい", tier: "small"); st4.insert(start: 2.3, end: 3.2, ja: "気持ちいい", tier: "small")
check(st4.segments.count == 1, "Whisper repeat still deduped")

// 2. Lateness split.
let src = LiveLatencyRecord(segment: 1, start: 10, speechEnd: 12, audioReady: 15, jaReady: 15.1, zhReady: nil, firstPartial: nil, asrMs: 60, mtMs: nil, queueMs: 10)
check(src.jaLatency > 2 && !src.computeLate && src.sourceLag == 3, "audio arrived late → source-late, not compute-late")
let cmp = LiveLatencyRecord(segment: 2, start: 10, speechEnd: 12, audioReady: 11, jaReady: 14.5, zhReady: nil, firstPartial: nil, asrMs: 1800, mtMs: nil, queueMs: 900)
check(cmp.computeLate, "slow recognition → compute-late")

// 3. Pipeline: fast recognizer + late source audio → lines inserted with arrival, counters, NOT compute-bound.
final class FastASR: LiveSpeechRecognizer, @unchecked Sendable {
    let tier: LiveASRTier = .senseVoice
    var n = 0
    func transcribe(_ s: [Float], prompt: String?) async throws -> String { n += 1; return n % 4 == 0 ? "" : "テスト\(n)です" }
}
func tone(_ sec: Double, amp: Float) -> [Float] { (0 ..< Int(sec * 16000)).map { i in Float(sin(Double(i) * 0.07)) * amp } }
func silence(_ sec: Double, amp: Float = 0.0003) -> [Float] { (0 ..< Int(sec * 16000)).map { i in Float(sin(Double(i) * 1.3)) * amp } }
let p = LivePipeline(); p.mode = .japanese
var clock = 0.0; p.now = { clock }
var audio: [Float] = []
for _ in 0 ..< 8 { audio += silence(0.8); audio += tone(1.2, amp: 0.2) }
p.reset(at: 0)
let asr = FastASR()
let sem = DispatchSemaphore(value: 0)
Task {
    var t = 0.0
    for c in stride(from: 0, to: audio.count, by: 4000) {
        let part = Array(audio[c ..< min(audio.count, c + 4000)])
        p.setPlayhead(t + 4)                 // reader 4 s BEHIND the playhead (slow source)
        p.feed(part, start: t, generation: p.currentGeneration); t += Double(part.count) / 16000
        clock += 0.25
        while await p.work(asr: asr, mt: nil) {}
        _ = p.caption(at: t + 4)
    }
    sem.signal()
}
sem.wait()
let s = p.snapshotStats
check(s.chunks > 0 && s.utterances >= 7, "counters: chunks \(s.chunks) utterances \(s.utterances)")
check(s.recognizedEmpty >= 1 && s.inserted >= 4, "counters: empty \(s.recognizedEmpty) inserted \(s.inserted)")
check(s.lateArrivals >= 4 && s.sourceLate == s.lateArrivals && s.computeLate == 0, "late lines classified as source-late \(s.stageLine)")
check(!p.computeBound().bound, "fast recognizer with late audio is NOT compute-bound (290 switched to Apple here) \(p.computeBound().why)")
check(s.displayed >= 3, "late lines were displayed \(s.displayed)")
check(p.snapshotStore.segments.allSatisfy { $0.arrival != nil }, "arrival recorded")

// 4. VAD: speech over continuous background music is still detected after 60 s of music.
let vad = LiveVAD()
var x: [Float] = []
let music = (0 ..< 60 * 16000).map { i in Float(sin(Double(i) * 0.031) * 0.025) }     // ≈ -35 dBFS BGM
x += music
var speech: [Float] = []
for k in 0 ..< 3 * 16000 { speech.append(Float(sin(Double(k) * 0.031) * 0.025) + Float(sin(Double(k) * 0.11) * (0.5 + 0.5 * sin(Double(k) / 16000 * 25))) * 0.06) }
x += speech; x += music.prefix(16000 * 2)
var found: [LiveUtterance] = []
var tt = 0.0
for c in stride(from: 0, to: x.count, by: 4000) { let part = Array(x[c ..< min(x.count, c + 4000)]); found += vad.feed(part, start: tt); tt += Double(part.count) / 16000 }
check(found.contains { $0.end > 60.5 && $0.start < 63 }, "speech over -35 dB BGM detected after 60 s (floor ceiling) \(vad.floorDB)")

// 5. VAD max-length split followed by silence: no trap (290 crashed: prefix(negative) when the carried remainder
//    started > tail after the last voiced frame — voiced 4.6 s, then fading quiet so the cut lands late).
let v2 = LiveVAD()
var y: [Float] = silence(0.5)
y += tone(4.6, amp: 0.2)
for i in 0 ..< 3200 { let fade: Double = 1 - Double(i) / 3400; y.append(Float(sin(Double(i) * 1.3) * 0.0003 * fade)) }
y += silence(1.0, amp: 0.00001)
var tt2 = 0.0
var got2: [LiveUtterance] = []
for c in stride(from: 0, to: y.count, by: 320) { let part = Array(y[c ..< min(y.count, c + 320)]); got2 += v2.feed(part, start: tt2); tt2 += Double(part.count) / 16000 }
check(got2.allSatisfy { $0.end >= $0.start }, "split-then-silence did not crash \(got2.map { ($0.start, $0.end) })")

// 6. Stale Whisper preference never survives; Apple kept; fresh 291 choices kept.
let d = UserDefaults(suiteName: "live291-test-\(UUID().uuidString)")!
d.set("small", forKey: "live.subtitle.recognizer289")
check(LiveTierPreference.current(d) == .senseVoice, "legacy small → SenseVoice")
d.set("turbo", forKey: LiveTierPreference.defaultsKey)
check(LiveTierPreference.current(d) == .turbo, "a 291 pick is respected")
let d2 = UserDefaults(suiteName: "live291-test-\(UUID().uuidString)")!
d2.set("apple", forKey: "live.subtitle.recognizer289")
check(LiveTierPreference.current(d2) == .apple, "legacy apple kept")

// 7. Guard: heat no longer swaps SenseVoice (restart loop); critical → Apple; hot Whisper → SenseVoice.
check(LiveSubtitleGuard.verdict(preferred: .senseVoice, thermal: 2, lowPower: true, battery: 0.15, charging: false) == .run(.senseVoice), "serious/low power keep SenseVoice")
check(LiveSubtitleGuard.verdict(preferred: .senseVoice, thermal: 3, lowPower: false, battery: 0.8, charging: false).tier == .apple, "critical → Apple")
check(LiveSubtitleGuard.recoverSeconds >= 60, "hysteresis")

print(failures == 0 ? "ALL PASS 291 core" : "FAILURES \(failures)")
exit(failures == 0 ? 0 : 1)
