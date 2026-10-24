import Foundation
@main struct ActorResolverRegression248 {
    @MainActor static func main() async throws {
        var passed = [String]()
        func check(_ condition: Bool, _ label: String) { precondition(condition, label); passed.append(label) }
        func actor(_ id: String, _ name: String, other: String = "") throws -> Actor {
            let data = try JSONSerialization.data(withJSONObject: ["id": id, "name": name, "other_name": other])
            return try JSONDecoder().decode(Actor.self, from: data)
        }
        let index = try JSONDecoder().decode(ActorAliasIndex.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let catalog = ActorAliasCatalog(index: index)
        let bridge = ExternalActorIdentity.resolve(sourceName: "桥本有菜", aliases: ["橋本ありな"], catalog: catalog)
        check(bridge.queries.count == 7 && bridge.queries.prefix(2) == ["桥本有菜", "橋本ありな"], "seven aliases canonical/source priority; no sort")
        check(ActorNameNormalizer.orderedUnique([" JULIA ", "julia", "京香じゅりあ"]) == ["JULIA", "京香じゅりあ"], "NFKC dedupe preserves first query")
        check(ActorNameNormalizer.key("波多野結衣") != ActorNameNormalizer.key("波多結衣"), "never delete 野")
        for alias in index.conflicts { check(catalog.lookup([alias.alias]) == nil, "conflict remains unassigned: " + alias.alias) }
        let real = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [[String: Any]]
        let snapshot = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))) as! [String: Any]
        let people = (snapshot["grok"] as! [String: Any])["people"] as! [[String: Any]]
        for report in real {
            let source = report["source"] as! String
            let sourceName = people.first { ($0["nameZh"] as? String) == source }!["nameJa"] as! String
            let sourceAliases = sourceName == source ? [] : [source]
            let probes = report["probes"] as! [[String: Any]]
            var calls = [(String, Int)]()
            let search: ExternalActorResolver.Search = { q, page in
                calls.append((q, page))
                guard let found = probes.first(where: { ($0["query"] as? String) == q && ($0["page"] as? Int) == page }) else { throw NSError(domain: "missing recorded request", code: 1) }
                return try JSONDecoder().decode([Actor].self, from: JSONSerialization.data(withJSONObject: found["actors"]!))
            }
            let identity = ExternalActorIdentity.resolve(sourceName: sourceName, aliases: sourceAliases, catalog: catalog)
            let outcome = try await ExternalActorResolver.inspect(identity: identity, search: search)
            if source == "波多野结衣" || source == "JULIA" {
                if case .ambiguous(let candidates) = outcome { check(candidates.count == 2, source + " replay retains two real IDs") }
                else { preconditionFailure("real multi-ID must not auto-select") }
            } else {
                if case .matched(let match) = outcome { check(match.actor.id == (source == "桥本有菜" ? "RJM8" : "ex3z"), source + " replay exact real ID") }
                else { preconditionFailure("unique mapped actor rejected") }
                let policy = try await JavVerseActorResolver.resolve(name: sourceName, aliases: sourceAliases, catalog: catalog, search: search)
                check(policy != nil, source + " policy does not reject alias count")
            }
            check(calls.first?.0 == identity.canonical, source + " canonical first actual call")
        }
        let identity = ExternalActorIdentity(sourceName: "Neutral", canonical: "Neutral", display: "Neutral", mapID: nil, queries: ["Neutral", "Second"])
        let exact = try actor("valid", "Neutral"); let other = try actor("other", "Neutral")
        let unique = try await ExternalActorResolver.inspect(identity: identity, search: { _, _ in [exact, exact] })
        if case .matched(let m) = unique { check(m.actor.id == "valid", "same ID repeated is deduplicated") } else { preconditionFailure() }
        let ambiguous = try await ExternalActorResolver.inspect(identity: identity, search: { _, _ in [exact, other] })
        if case .ambiguous(let c) = ambiguous { check(c.count == 2, "distinct IDs never selected by ordering") } else { preconditionFailure() }
        let filler = try actor("filler", "Unrelated")
        var incompleteCalls = [(String, Int)]()
        let incomplete = try await ExternalActorResolver.inspect(identity: identity, search: { q, page in
            incompleteCalls.append((q, page)); return q == "Neutral" ? Array(repeating: filler, count: 20) : [exact]
        })
        if case .matched(let match) = incomplete { check(match.actor.id == "valid", "exact canonical success survives one incomplete alias") } else { preconditionFailure() }
        check(incompleteCalls.map { $0.0 } == ["Neutral", "Neutral", "Neutral", "Second"], "exact result stops remaining broad aliases")
        let cappedIdentity = ExternalActorIdentity(sourceName: "Neutral", canonical: nil, display: "Neutral", mapID: nil, queries: (0..<13).map { "Alias\($0)" })
        var cappedCalls = 0
        let capped = try await ExternalActorResolver.inspect(identity: cappedIdentity, search: { _, _ in cappedCalls += 1; return [] })
        if case .incomplete(_, let q) = capped { check(cappedCalls == 12 && q == ["Alias12"], "12 total query cap reports incomplete") } else { preconditionFailure() }
        let absent = try await ExternalActorResolver.inspect(identity: identity, search: { _, _ in [filler] })
        if case .notFound = absent { check(true, "only exhaustive zero exact matches is notFound") } else { preconditionFailure() }
        let padded = try actor(" valid ", "Neutral")
        let invalid = try await ExternalActorResolver.inspect(identity: identity, search: { _, _ in [padded] })
        if case .notFound = invalid { check(true, "malformed ID conservatively rejected") } else { preconditionFailure() }
        enum Expected: Error { case network }
        do { _ = try await ExternalActorResolver.inspect(identity: identity, search: { _, _ in throw Expected.network }); preconditionFailure() }
        catch Expected.network { check(true, "request error propagates; never notFound") }
        do { _ = try await ExternalActorResolver.inspect(identity: identity, search: { _, _ in throw CancellationError() }); preconditionFailure() }
        catch is CancellationError { check(true, "cancellation propagates") }
        let mitani = ExternalActorIdentity.resolve(sourceName: "美谷朱里", aliases: [], catalog: catalog)
        let akane = try actor("gyRE", "美谷朱里", other: "美谷あかり,谷坂かな,吉見いりあ,仁科璃々,三上江里,美谷朱音")
        let secondary = try actor("PQJKe", "美谷朱里")
        let akari = try actor("other-akari", "美谷あかり")
        var mitaniCalls = [String]()
        let mitaniResult = try await ExternalActorResolver.inspect(identity: mitani, search: { query, _ in
            mitaniCalls.append(query)
            return query == "美谷朱里" ? [akane, secondary] : [akari]
        })
        if case .ambiguous(let choices) = mitaniResult {
            precondition(Set(choices.map(\.id)) == ["PQJKe", "gyRE"], "same canonical name stays ambiguous ids=\(choices.map(\.id)) calls=\(mitaniCalls)")
        } else if case .matched(let match) = mitaniResult {
            preconditionFailure("美谷朱里 auto-selected \(match.actor.id) calls=\(mitaniCalls)")
        } else if case .incomplete(let choices, let queries) = mitaniResult {
            preconditionFailure("美谷朱里 incomplete ids=\(choices.map(\.id)) queries=\(queries) calls=\(mitaniCalls)")
            check(mitaniCalls == mitani.queries, "unprioritized source name cannot skip mapped aliases")
            check(ExternalActorResolver.Failure.ambiguous(choices).localizedDescription.contains("美谷朱里 [PQJKe]") && ExternalActorResolver.Failure.ambiguous(choices).localizedDescription.contains("美谷朱里 [gyRE]"), "candidate copy uses each ID name")
        } else { preconditionFailure("美谷朱里 must not merge") }
        let akiho = ExternalActorIdentity.resolve(sourceName: "吉沢明歩", aliases: ["吉泽明步"], catalog: catalog)
        let censored = try actor("0yVv", "吉沢明歩", other: "吉澤明步")
        let uncensored = try actor("AdNn", "吉沢明歩")
        let akihoResult = try await ExternalActorResolver.inspect(identity: akiho, search: { _, _ in [censored, uncensored] })
        if case .ambiguous(let choices) = akihoResult { check(Set(choices.map(\.id)) == ["0yVv", "AdNn"], "吉沢明歩 records stay separate") } else { preconditionFailure("吉沢明歩 must not merge") }
        let jessica = ExternalActorIdentity.resolve(sourceName: "希崎ジェシカ", aliases: ["希崎杰西卡"], catalog: catalog)
        let jessicaActor = try actor("dxne", "希崎潔西卡")
        let jessicaResult = try await ExternalActorResolver.inspect(identity: jessica, search: { _, _ in [jessicaActor] })
        if case .matched(let match) = jessicaResult { check(match.actor.id == "dxne", "希崎 unique traditional name matches") } else { preconditionFailure("希崎 rejected") }
        let status: [String: Any] = ["passed": passed.count, "assertions": passed, "live": false, "productionCandidatePatchApplied": true, "adultImagesDownloaded": false]
        let data = try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "actor-regression248.json")); print(String(decoding: data, as: UTF8.self))
    }
}

