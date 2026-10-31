import Foundation
// Build 292 translation-layer regression (Linux / macOS): LiveMTPrep tables, moan skip, splitting, post fixes,
// glossary, LiveMTRunner routing, LiveTranslatorChain LLM gating (guard / budget / failures), 机翻 caption flag.
var fails = 0
func check(_ c: Bool, _ m: String) { if c { print("PASS", m) } else { print("FAIL", m); fails += 1 } }
typealias P = LiveMTPrep
check(P.plan("うん。") == .direct("嗯"), "interjection うん")
check(P.plan("はい？") == .direct("是？"), "interjection question")
check(P.plan("あぁん…") == .skip && P.plan("んっ、あぁっ") == .skip && P.plan("はぁはぁ") == .skip, "moans skipped")
check(P.plan("The.") == .skip, "ASCII slip skipped")
check(P.plan("いらっしゃいませ。") == .direct("欢迎光临"), "set phrase いらっしゃいませ")
check(P.plan("じゃあ、よろしくお願いしますよ。") == .direct("拜托了"), "set phrase with lead + tail")
check(P.plan("失礼します。") == .direct("打扰了"), "set phrase 失礼します")
if case .translate(let ps) = P.plan("そろそろ行くよ夜ご飯どうする？") { check(ps.count == 2, "final-particle split \(ps)") } else { check(false, "split plan") }
if case .translate(let ps) = P.plan("すみません、遅れちゃって。今日は混んでて。") { check(ps.count >= 2, "sentence split \(ps)") } else { check(false, "split plan 2") }
check(P.post("现在,我知道.", source: "ももせロ。") == "", "filler on garbled source dropped")
check(P.post("现在,我很高兴.", source: "嬉しい") == "我很高兴。", "unsupported leading 现在 stripped")
check(P.post("现在我们要去.", source: "今行くよ") .hasPrefix("现在"), "supported 现在 kept")
check(P.post("子,子,子,子,子,子", source: "箱根ね") == "子", "repetition loop cut")
check(P.post("我很害怕,我很害怕.", source: "怖い顔") == "我很害怕。", "duplicated clause cut")
let g = P.glossary(names: [("伊藤舞雪", nil), ("楓カレン", "枫可怜")])
check(g.contains { $0.ja == "伊藤" && $0.zh == "伊藤" } && g.contains { $0.ja == "楓カレン" && $0.zh == "枫可怜" }, "glossary from names")
let (prot, used) = P.protect("楓カレンちゃん", g)
check(prot == "[0]ちゃん" && P.restore("[0]酱", used) == "枫可怜酱", "glossary protect/restore")

final class MockMT: LiveTranslating, @unchecked Sendable {
    let name = "mock"; var calls: [String] = []
    func translate(_ japanese: String) async throws -> String { calls.append(japanese); return "译" + japanese }
}
final class MockLLM: LiveContextTranslating, @unchecked Sendable {
    let name = "llm"; var calls = 0; var fail = false; var lastHistory = 0
    func translate(_ japanese: String) async throws -> String { "x" }
    func contextTranslate(_ japanese: String, context: LiveMTContext) async throws -> String? {
        calls += 1; lastHistory = context.history.count
        if fail { throw LiveEngineError.notReady }
        return "LLM:" + japanese
    }
}
let sem = DispatchSemaphore(value: 0)
Task {
    let mt = MockMT()
    let r1 = try await LiveMTRunner.runDetailed("うん。", mt: mt, context: .init())
    check(r1.zh == "嗯" && mt.calls.isEmpty, "table answer makes no MT call")
    let r2 = try await LiveMTRunner.runDetailed("そろそろ行くよ夜ご飯どうする？", mt: mt, context: .init())
    check(mt.calls.count == 2 && !r2.contextual, "classic path translates each piece (\(mt.calls))")
    let llm = MockLLM()
    let chain = LiveTranslatorChain(primary: nil, fallback: mt, llm: llm)
    var ctx = LiveMTContext(history: [("前の行", "上一行")], glossary: [], budget: 6)
    let r3 = try await LiveMTRunner.runDetailed("今日は特別だよ。", mt: chain, context: ctx)
    check(r3.contextual && r3.zh.hasPrefix("LLM") && llm.lastHistory == 1, "LLM path with history")
    chain.setLLMAllowed(false, why: "设备发热")
    let r4 = try await LiveMTRunner.runDetailed("今日は特別だよ。", mt: chain, context: ctx)
    check(!r4.contextual && r4.zh.hasPrefix("译"), "guard → classic")
    chain.setLLMAllowed(true, why: "")
    ctx.budget = 0.2
    let r5 = try await LiveMTRunner.runDetailed("今日は特別だよ。", mt: chain, context: ctx)
    check(!r5.contextual, "line due too soon → classic")
    ctx.budget = 6; llm.fail = true
    for _ in 0 ..< 3 { _ = try await LiveMTRunner.runDetailed("今日は特別だよ。", mt: chain, context: ctx) }
    llm.fail = false; let before = llm.calls
    let r6 = try await LiveMTRunner.runDetailed("今日は特別だよ。", mt: chain, context: ctx)
    check(!r6.contextual && llm.calls == before && chain.llmStatus.contains("冷却"), "3 failures → cool-down (\(chain.llmStatus))")
    // pipeline caption flag + history
    var store = LiveSegmentStore()
    let a = store.insert(start: 1, end: 2, ja: "一行目です", tier: "sensevoice")!
    let b = store.insert(start: 3, end: 4, ja: "二行目です", tier: "sensevoice")!
    store.setChinese(id: a.id, "第一行", engine: "mt")
    store.setChinese(id: b.id, "第二行", engine: "llm")
    check(store.caption(at: 3.5, mode: .bilingual).machine && !store.caption(at: 1.5, mode: .bilingual).machine, "机翻 flag only on LLM lines")
    check(store.history(before: b).map(\.zh) == ["第一行"], "history(before:)")
    check(LiveSubtitleGuard.llmAllowed(thermal: 2, lowPower: false, battery: 1, charging: false).ok == false
          && LiveSubtitleGuard.llmAllowed(thermal: 0, lowPower: true, battery: 1, charging: false).ok == false
          && LiveSubtitleGuard.llmAllowed(thermal: 0, lowPower: false, battery: 0.15, charging: false).ok == false
          && LiveSubtitleGuard.llmAllowed(thermal: 1, lowPower: false, battery: 0.5, charging: false).ok, "LLM guard")
    check(LiveLLMModel.prompt("テスト", context: LiveMTContext(history: [("あ", "啊")], glossary: [.init(ja: "テスト", zh: "测试")])).contains("テスト->测试 #人名"),
          "Sakura glossary prompt")
    sem.signal()
}
sem.wait()
print(fails == 0 ? "ALL PASS 292 translation" : "FAILURES \(fails)")
exit(fails == 0 ? 0 : 1)
