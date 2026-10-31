import Foundation
// mtprep <lines.json> <glossary.json> <nllb_cache.json> <out.json> [misses.json]
// lines.json: [String]; nllb cache: {src: zh}. Pass 1 writes the cache misses; pass 2 (full cache) writes out.
final class CacheMT: LiveTranslating, @unchecked Sendable {
    let name = "cache"; var cache: [String: String]; var misses = Set<String>()
    init(_ c: [String: String]) { cache = c }
    func translate(_ japanese: String) async throws -> String {
        if let z = cache[japanese] { return z }
        misses.insert(japanese); return ""
    }
}
let a = CommandLine.arguments
func load<T: Decodable>(_ p: String, _ t: T.Type) -> T { try! JSONDecoder().decode(T.self, from: Data(contentsOf: URL(fileURLWithPath: p))) }
let lines = load(a[1], [String].self)
let names = load(a[2], [[String]].self)
let glossary = LiveMTPrep.glossary(names: names.map { ($0[0], $0.count > 1 ? $0[1] : nil) })
let cache = (try? Data(contentsOf: URL(fileURLWithPath: a[3]))).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
let mt = CacheMT(cache)
var out: [String: [String: String]] = [:]
let sem = DispatchSemaphore(value: 0)
Task {
    for l in Set(lines) {
        let plan = LiveMTPrep.plan(l)
        let kind: String
        switch plan { case .skip: kind = "skip"; case .direct: kind = "direct"; case .translate(let p): kind = p.contains { if case .fixed = $0 { return true }; return false } ? "mixed" : "mt" }
        let z = try await LiveMTRunner.run(l, mt: mt, context: LiveMTContext(history: [], glossary: glossary))
        out[l] = ["zh": z, "kind": kind]
    }
    sem.signal()
}
sem.wait()
try! JSONEncoder().encode(out).write(to: URL(fileURLWithPath: a[4]))
if a.count > 5 { try! JSONEncoder().encode(Array(mt.misses)).write(to: URL(fileURLWithPath: a[5])) }
print("lines", out.count, "misses", mt.misses.count)
