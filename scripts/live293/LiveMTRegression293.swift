import Foundation
// Build 293: whole-utterance MT (no per-clause split), adjacent segment merge, いま strip / glossary still work.
var fails = 0
func check(_ c: Bool, _ m: String) { if c { print("PASS", m) } else { print("FAIL", m); fails += 1 } }
typealias P = LiveMTPrep
let ishi = "いいかい、石川くん。君ももう3年目だろ。"
if case .translate(let ps) = P.plan(ishi) {
    check(ps.count == 1, "石川くん kept as one MT unit \(ps)")
    if case .mt(let s) = ps[0] { check(s == ishi, "full JA passed to MT") } else { check(false, "mt piece") }
} else { check(false, "plan ishi") }
if case .translate(let ps) = P.plan("すみません、遅れちゃって。今日は混んでて。") {
    check(ps.count == 1, "multi 。 kept whole \(ps)")
} else { check(false, "plan multi") }
check(P.plan("うん。") == .direct("嗯"), "interjection")
check(P.plan("あぁん…") == .skip, "moan skip")
check(P.post("现在,我知道.", source: "ももせロ。") == "", "filler dropped")
check(P.post("现在,我很高兴.", source: "嬉しい") == "我很高兴。", "いま strip")
check(P.post("现在我们要去.", source: "今行くよ").hasPrefix("现在"), "supported いま kept")
let g = P.glossary(names: [("石川くん", "石川君"), ("伊藤舞雪", nil)])
check(g.contains { $0.ja == "石川くん" }, "glossary name")
let (prot, used) = P.protect("石川くん。君も", g)
check(prot.hasPrefix("[0]") && P.restore(prot, used).contains("石川君"), "glossary protect")

var store = LiveSegmentStore()
let a = store.insert(start: 10, end: 11.2, ja: "いいかい、石川くん。", tier: "sensevoice")!
check(a.zh == nil, "first half inserted")
let b = store.insert(start: 11.6, end: 13.0, ja: "君ももう3年目だろ。", tier: "sensevoice")
check(b != nil && b!.id == a.id, "adjacent merge returns same id")
check(store.segments.count == 1, "one segment after merge")
check(store.segments[0].ja.contains("石川くん") && store.segments[0].ja.contains("3年目"), "merged JA has both halves: \(store.segments[0].ja)")
store.setChinese(id: a.id, "你也是第3年吧。", engine: "mt")
let grew = store.insert(start: 10, end: 13.0, ja: "いいかい、石川くん。君ももう3年目だろ。もっと頑張れ。", tier: "sensevoice")
check(grew != nil && grew!.zh == nil, "overlap grow clears zh for retranslate")

// short gap beyond 0.9 s must NOT merge
var s2 = LiveSegmentStore()
_ = s2.insert(start: 1, end: 2, ja: "第一句です。", tier: "sensevoice")
_ = s2.insert(start: 3.5, end: 5, ja: "第二句です。", tier: "sensevoice")
check(s2.segments.count == 2, "gap > 0.85 s keeps two segments")
// dialogue turns ~1 s apart without forcing a merge when the first line has no 。
var s3 = LiveSegmentStore()
_ = s3.insert(start: 1, end: 2, ja: "一行目です", tier: "sensevoice")
_ = s3.insert(start: 3, end: 4, ja: "二行目です", tier: "sensevoice")
check(s3.segments.count == 2, "dialogue turns stay separate")


// 296: third short clause within 0.85 s must NOT glue onto a 2-clause merge (monster-line guard).
var s4 = LiveSegmentStore()
_ = s4.insert(start: 10, end: 10.4, ja: "来。", tier: "sensevoice")
_ = s4.insert(start: 10.7, end: 12.0, ja: "まだ塾も家庭教師もいないから、調査中ですか？", tier: "sensevoice")
check(s4.segments.count == 1, "two short clauses still merge")
_ = s4.insert(start: 12.3, end: 13.2, ja: "優しい先生はいいですね。", tier: "sensevoice")
check(s4.segments.count == 2, "3rd clause stays separate: \(s4.segments.count) ja=\(s4.segments.map(\.ja))")
check(LiveSegmentStore.adjacentMergeMaxBody <= 28, "max body ≤ 28")
check(LiveSegmentStore.adjacentMergeMaxClauses == 2, "max clauses == 2")

// 296: display slice — multi-sentence ZH shows one piece at a time
let monster = "来。还有，没有补习班和固定提供师，所以在调查吗？温柔的老师真好啊。我不认为不严格。"
let early = LiveSegmentStore.displaySlice(ja: "来。まだ。優しい。厳しくない。", zh: monster, start: 10, end: 18, t: 10.2)
check((early.zh ?? "").hasPrefix("来。") && !(early.zh ?? "").contains("温柔"), "early shows first ZH sentence: \(early.zh ?? "")")
let mid = LiveSegmentStore.displaySlice(ja: "来。まだ。優しい。厳しくない。", zh: monster, start: 10, end: 18, t: 14.0)
check((mid.zh ?? "").contains("温柔") || (mid.zh ?? "").contains("调查"), "mid shows a later sentence: \(mid.zh ?? "")")
check(LiveSegmentStore.bodyCount(mid.zh ?? "") <= LiveSegmentStore.bodyCount(monster), "slice not longer than full")
let shortOk = LiveSegmentStore.displaySlice(ja: "うん。", zh: "嗯。好的。", start: 1, end: 2, t: 1.2)
check(shortOk.zh == "嗯。好的。", "short multi stays whole under body cap")

print(fails == 0 ? "ALL PASS 293 translation" : "FAILURES \(fails)")
