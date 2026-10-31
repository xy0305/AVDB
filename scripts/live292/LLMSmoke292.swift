import Foundation
import llama
ggml_backend_load_all()
let path = CommandLine.arguments[1]
let t = try LiveLLMTranslator.load(path: path)
print("load", t.loadSeconds)
let sem = DispatchSemaphore(value: 0)
Task {
    var hist: [(ja: String, zh: String)] = []
    let g = LiveMTPrep.glossary(names: [("伊藤舞雪", "伊藤舞雪")])
    for ja in ["伊藤先生、今回の学校慣れました？", "生徒のみんなもすごくいい子だし。", "じゃあ、よろしくお願いしますよ。", "そろそろ行くよ。夜ご飯どうする？", "おちんちん舐めて気持ちよくしてあげる"] {
        let t0 = Date()
        let r = try await LiveMTRunner.runDetailed(ja, mt: t, context: LiveMTContext(history: hist, glossary: g, budget: 20))
        print(String(format: "%.2fs", Date().timeIntervalSince(t0)), ja, "→", r.zh, r.contextual)
        hist.append((ja, r.zh))
    }
    sem.signal()
}
sem.wait()
