import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

var failures = 0
func check(_ c: @autoclosure () -> Bool, _ m: String) { if !c() { failures += 1; print("FAIL", m) } }
let args = CommandLine.arguments
let dir = URL(fileURLWithPath: args.count > 1 ? args[1] : ".")

// ---- VAD: 3 bursts of "speech" (modulated noise) separated by silence, plus a 9 s monologue.
func signal(_ spans: [(Double, Double)], total: Double, seed: UInt64 = 7) -> [Float] {
    var x = [Float](repeating: 0, count: Int(total * 16000)); var r = seed
    func rnd() -> Float { r = r &* 6364136223846793005 &+ 1442695040888963407; return Float(Int64(bitPattern: r >> 11) % 2000) / 1000 - 1 }
    for i in x.indices { x[i] = rnd() * 0.0005 }                       // -66 dBFS room noise
    for (a, b) in spans { for i in Int(a * 16000) ..< min(x.count, Int(b * 16000)) {
        let t = Double(i) / 16000; x[i] += Float(sin(2 * .pi * 180 * t) * (0.55 + 0.45 * sin(2 * .pi * 4 * t))) * 0.3 + rnd() * 0.02 } }
    return x
}
let spans = [(1.0, 2.4), (3.2, 4.0), (5.5, 14.5)]
let pcm = signal(spans, total: 16)
let vad = LiveVAD()
var utts: [LiveUtterance] = []
var t = 0.0
for chunk in stride(from: 0, to: pcm.count, by: 4000) {              // 250 ms decoder chunks
    let part = Array(pcm[chunk ..< min(pcm.count, chunk + 4000)])
    utts += vad.feed(part, start: t); t += Double(part.count) / 16000
}
if let u = vad.finish() { utts.append(u) }
check(utts.count >= 4, "VAD utterances \(utts.map { (($0.start * 100).rounded() / 100, ($0.end * 100).rounded() / 100) })")
check(abs(utts[0].start - 0.8) < 0.15 && abs(utts[0].speechEnd - 2.4) < 0.08, "first utterance bounds + pre-roll \(utts[0].start) \(utts[0].speechEnd)")
check(utts[0].end - utts[0].speechEnd < 0.2, "short tail after speech")
check(abs(utts[1].start - 3.0) < 0.15, "second utterance")
check(utts.dropFirst(2).allSatisfy { $0.end - $0.start <= 5.05 }, "max-length split keeps ASR windows ≤ 5 s")
let mono = utts.dropFirst(2)
check(abs(mono.first!.start - 5.3) < 0.15 && abs(mono.last!.speechEnd - 14.5) < 0.1, "split utterances cover the monologue")
for k in mono.indices.dropLast() { check(abs(utts[k].end - utts[k + 1].start) < 0.03, "split is contiguous \(utts[k].end) \(utts[k + 1].start)") }
// End-of-speech detection latency (VAD side): utterance is emitted once `endSilence` of quiet has been seen.
check(vad.endSilence <= 0.35, "VAD hangover ≤ 350 ms")

// ---- text hygiene
check(LiveText.collapseRepeats("ありがとうありがとうありがとうありがとう") == "ありがとうありがとう", "collapse repeats")
check(LiveText.collapseRepeats("はい") == "はい" && LiveText.collapseRepeats("あああああああ") == "ああ", "collapse short")
check(LiveText.isNoise("ご視聴ありがとうございました。") && LiveText.isNoise("♪〜") && !LiveText.isNoise("ありがとう"), "hallucination / noise filter")
check(LiveText.clean("(拍手) 本当に？ <|ja|>") == "本当に？", "clean brackets + special tokens: \(LiveText.clean("(拍手) 本当に？ <|ja|>"))")
check(LiveText.chinesePunctuation("待一点,你去哪儿?") == "待一点，你去哪儿？", "zh punctuation")
check(LiveText.chinesePunctuation("现在 3.5 点, 好!") == "现在3.5点，好！", "zh punctuation numbers/spaces: \(LiveText.chinesePunctuation("现在 3.5 点, 好!"))")
check(LiveText.similarity("明日の朝、駅で", "明日の朝駅で") > 0.8 && LiveText.similarity("こんにちは", "さようなら") < 0.2, "similarity")

// ---- store: dedupe, ordering, caption hold, modes
var st = LiveSegmentStore()
let a = st.insert(start: 1.0, end: 2.5, ja: "今日は暑いですね。", tier: "turbo")
check(a != nil, "insert")
check(st.insert(start: 1.1, end: 2.6, ja: "今日は暑いですね", tier: "turbo") == nil && st.segments.count == 1, "overlapping re-transcription deduped")
check(st.insert(start: 2.7, end: 3.0, ja: "今日は暑いですね。", tier: "turbo") == nil, "consecutive repeat dropped")
check(st.insert(start: 5, end: 6, ja: "ご視聴ありがとうございました", tier: "turbo") == nil, "hallucination dropped")
let b = st.insert(start: 3.5, end: 4.2, ja: "大丈夫？", tier: "turbo")!
check(st.segments.map(\.id) == [a!.id, b.id], "ordered")
check(st.caption(at: 3.0, mode: .chinese) == LiveCaption(ja: "今日は暑いですね。", zh: nil, partial: false, pendingChinese: true), "中文 mode shows Japanese while the translation is pending")
st.setChinese(id: a!.id, "今天真热啊。")
check(st.caption(at: 1.2, mode: .bilingual) == LiveCaption(ja: "今日は暑いですね。", zh: "今天真热啊。", partial: false, pendingChinese: false), "bilingual")
check(st.caption(at: 3.2, mode: .chinese).zh == "今天真热啊。", "hold 0.8 s after end")
check(st.caption(at: 3.6, mode: .japanese).ja == "大丈夫？", "next line replaces the hold")
check(st.caption(at: 4.4, mode: .japanese).ja == "大丈夫？", "short line held ≥ 1.2 s")
check(st.caption(at: 9, mode: .japanese).isEmpty && st.caption(at: 1.2, mode: .off).isEmpty, "gaps / off")
st.partial = LiveSegment(id: 0, start: 10, end: 11, ja: "もう一度", zh: nil, final: false, tier: "turbo")
check(st.caption(at: 10.5, mode: .bilingual).partial, "partial shown")
st.cover(0, 4); st.cover(3.9, 8); st.cover(20, 30)
check(st.covered.count == 2 && st.coveredEnd(at: 2) == 8 && st.coveredEnd(at: 10) == nil, "coverage merge")
st.uncover(5, 6)
check(st.coveredEnd(at: 2) == 5 && st.coveredEnd(at: 7) == 8, "uncover splits")

// ---- cache round trip + key stability
let cacheDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("live287-\(getpid())")
let cache = LiveSubtitleCache(directory: cacheDir)
let key = LiveSubtitleCache.key(video: "IPX-706#115", tier: .turbo)
check(key == LiveSubtitleCache.key(video: "IPX-706#115", tier: .turbo) && key != LiveSubtitleCache.key(video: "IPX-706#115", tier: .small), "cache key")
cache.save(st, key: key)
let back = cache.load(key)
check(back?.segments == st.segments && back?.covered == st.covered && back?.partial == nil, "cache round trip (no partial persisted)")
cache.maxFiles = 2
for i in 0 ..< 4 { cache.save(st, key: "k\(i)"); usleep(20_000) }
check(cache.load("k0") == nil && cache.load("k3") != nil, "LRU trim")
cache.clear(); check(cache.totalBytes() == 0, "clear")

// ---- guard + tier
check(LiveSubtitleGuard.verdict(preferred: .senseVoice, thermal: 0, lowPower: false, battery: 0.8, charging: false) == .run(.senseVoice), "nominal SenseVoice")
check(LiveSubtitleGuard.verdict(preferred: .senseVoice, thermal: 2, lowPower: false, battery: 0.8, charging: false).tier == .apple, "serious → Apple")
check(LiveSubtitleGuard.verdict(preferred: .turbo, thermal: 3, lowPower: false, battery: 0.8, charging: true).tier == .apple, "critical → Apple")
check(LiveSubtitleGuard.verdict(preferred: .small, thermal: 0, lowPower: true, battery: 0.8, charging: false).tier == .apple, "low power → Apple")
check(LiveSubtitleGuard.verdict(preferred: .senseVoice, thermal: 0, lowPower: false, battery: 0.05, charging: false).tier == nil, "battery < 10 % → pause")
check(LiveSubtitleGuard.verdict(preferred: .turbo, thermal: 0, lowPower: false, battery: 0.05, charging: true) == .run(.turbo), "charging ignores battery")
check(LiveSubtitleGuard.verdict(preferred: .apple, thermal: 3, lowPower: true, battery: 0.5, charging: false) == .run(.apple), "Apple stays Apple")
check(LiveTierPreference.current == .senseVoice || UserDefaults.standard.string(forKey: LiveTierPreference.defaultsKey) != nil, "SenseVoice default")
check(LiveSubtitleGuard.throttledLead(20, thermal: 0) == 20 && LiveSubtitleGuard.throttledLead(20, thermal: 1) == 15 && LiveSubtitleGuard.throttledLead(20, thermal: 2) == 8, "thermal lead throttle")

// ---- scheduler
check(LiveScheduler.next(finals: [5, 3], openStart: nil, openLength: 0, playhead: 0, sinceLastPartial: 9) == .final(1), "earliest final first")
check(LiveScheduler.next(finals: [], openStart: 10, openLength: 2, playhead: 2, sinceLastPartial: 9) == .idle, "no partials while the reader is ahead")
check(LiveScheduler.next(finals: [], openStart: 10, openLength: 1, playhead: 10.5, sinceLastPartial: 0.9) == .partial, "partials when the playhead is inside open speech")
check(LiveScheduler.next(finals: [], openStart: 10, openLength: 1, playhead: 10.5, sinceLastPartial: 0.3) == .idle, "partial hop 0.8 s")
check(LiveScheduler.next(finals: [1, 8], ends: [3, 10], openStart: nil, openLength: 0, playhead: 7, sinceLastPartial: 9) == .final(1), "on-screen line before backfill")
check(LiveScheduler.next(finals: [1], ends: [3], openStart: nil, openLength: 0, playhead: 7, sinceLastPartial: 9) == .final(0), "backfill when nothing is live")
check(LiveScheduler.next(finals: [], openStart: 10, openLength: 1, playhead: 10.5, sinceLastPartial: 0.9, allowPartial: false) == .idle, "no partials when ASR is slow")
check(LiveScheduler.readerShouldRun(decodedEnd: 25, playhead: 10, lead: 20, rate: 1) && !LiveScheduler.readerShouldRun(decodedEnd: 31, playhead: 10, lead: 20, rate: 1), "reader lead")
check(LiveScheduler.readerShouldRun(decodedEnd: 45, playhead: 10, lead: 20, rate: 2), "rate scales lead")

// ---- NLLB tokenizer parity with HF (trimmed compact ids) + greedy loop
let vocabData = try! Data(contentsOf: dir.appendingPathComponent("nllb287_vocab.json"))
let tok = try! NLLBTokenizer(json: vocabData)
struct Ref: Decodable { let ja: String; let src: [Int]; let seq: [Int]; let zh: String }
let refs = try! JSONDecoder().decode([Ref].self, from: Data(contentsOf: dir.appendingPathComponent("nllb287_reference.json")))
for r in refs {
    let ids = tok.encode(r.ja)
    let hf = r.src.prefix { $0 != tok.vocab.pad }
    check(ids == Array(hf), "tokenizer parity \(r.ja): \(ids) vs \(Array(hf))")
    // Greedy loop replay with a fake model that prefers the reference continuation.
    let refSeq = r.seq.filter { $0 != tok.vocab.unk }            // Swift never emits <unk> (masked)
    let out = NLLBGreedy.run(vocab: tok.vocab) { prefix, pos -> [Float] in
        var l = [Float](repeating: 0, count: tok.vocab.vocabSize)
        let next = pos + 1 < refSeq.count ? refSeq[pos + 1] : tok.vocab.eos
        l[next] = 10; return l
    }
    check(tok.decode(out) == r.zh.trimmingCharacters(in: .whitespaces), "greedy + detok \(tok.decode(out)) vs \(r.zh)")
}
let loop = NLLBGreedy.run(vocab: tok.vocab) { prefix, _ -> [Float] in
    var l = [Float](repeating: 0, count: tok.vocab.vocabSize); l[[100, 101, 102][(prefix.count - 2) % 3]] = 5; return l
}
check(loop.count < 20, "repetition guard stops a 3-gram loop (\(loop.count))")

// ---- pipeline with fake ASR/MT and a simulated 1× clock: look-ahead vs. playhead-paced (live tap)
final class FakeASR: LiveSpeechRecognizer, @unchecked Sendable {
    let tier = LiveASRTier.turbo; let cost: Double; let clock: () -> Double; let advance: (Double) -> Void
    init(cost: Double, clock: @escaping () -> Double, advance: @escaping (Double) -> Void) { self.cost = cost; self.clock = clock; self.advance = advance }
    func transcribe(_ samples: [Float], prompt: String?) async throws -> String { advance(cost); return "テスト\(samples.count / 1600)" }
}
final class FakeMT: LiveTranslating, @unchecked Sendable {
    let name = "fake"; let advance: (Double) -> Void
    init(advance: @escaping (Double) -> Void) { self.advance = advance }
    func translate(_ japanese: String) async throws -> String { advance(0.15); return "测试" }
}
func simulate(lookahead: Bool) async -> [LiveLatencyRecord] {
    var wall = 0.0
    let p = LivePipeline(); p.mode = .bilingual; p.now = { wall }
    let asr = FakeASR(cost: 0.45, clock: { wall }, advance: { wall += $0 }), mt = FakeMT(advance: { wall += $0 })
    var decoded = 0.0
    let hop = 0.25
    while wall < 16.5 {
        let playhead = min(16, wall)
        p.setPlayhead(playhead)
        // Reader: ahead (decoder runs ~8× realtime) or paced to the playhead like an output tap.
        let target = lookahead ? min(16, playhead + 20) : playhead
        while decoded + hop <= target + 1e-9 {
            let s = Int(decoded * 16000), e = min(pcm.count, Int((decoded + hop) * 16000))
            if s >= e { break }
            p.feed(Array(pcm[s ..< e]), start: decoded, generation: p.currentGeneration); decoded += hop
            if lookahead { wall += hop / 8 }
        }
        if decoded >= 16 { p.finishStream(generation: p.currentGeneration) }
        p.setPlayhead(min(16, wall))
        if !(await p.work(asr: asr, mt: mt)) { wall += 0.05 }
    }
    return p.latency
}
let ahead = await simulate(lookahead: true), live = await simulate(lookahead: false)
check(ahead.count >= 4 && live.count >= 4, "pipeline produced lines (\(ahead.count), \(live.count))")
check(ahead.allSatisfy { ($0.zhLatency ?? 9) == 0 }, "look-ahead: Chinese ready before end of speech for every line \(ahead.map { $0.zhLatency ?? -1 })")
check(ahead.filter(\.inSync).count >= ahead.count - 1, "look-ahead: lines ready before they start (in sync)")
check(live.filter { !$0.split }.allSatisfy { ($0.zhLatency ?? 9) <= 1.2 }, "playhead-paced: end-of-speech → zh ≤ 1.2 s with 0.32 s VAD + 0.45 s ASR + 0.15 s MT \(live.map { $0.zhLatency ?? -1 })")
check(live.filter(\.split).allSatisfy { ($0.zhLatency ?? 9) <= 2.0 }, "playhead-paced: max-length split pieces ≤ 2.0 s behind the words (partials cover the gap)")
check(live.contains { $0.firstPartial != nil }, "playhead-paced: partials stream during long speech")
// Seek: reset drops queued audio but keeps finals and un-covers what was never transcribed.
let ps = LivePipeline(); ps.feed(Array(pcm[0 ..< 16000 * 3]), start: 0, generation: ps.currentGeneration)
ps.reset(at: 10)
check(ps.snapshotStore.coveredEnd(at: 1.5) == nil, "seek un-covers queued (never transcribed) audio")
check(ps.resumePoint(after: 0.2) != nil, "leading silence stays covered")

if failures == 0 { print("PASS live287 core: VAD (pre-roll, 320 ms hangover, ≤5 s split), dedupe/hallucination/repeats, caption hold + modes, coverage, cache LRU, guard tiers, scheduler/lead, NLLB tokenizer parity \(refs.count)/\(refs.count), greedy guard, pipeline look-ahead in-sync vs paced ≤1.2 s, seek") } else { exit(1) }
