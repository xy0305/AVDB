import Foundation

@main struct JavBusActorsRegression251 {
    @MainActor static func main() async throws {
        let page = URL(string: "https://www.javbus.com/DSOD-070")!
        // Entirely neutral synthetic HTML, no adult media fixture or download.
        func html(_ number: String = "DSOD-070") -> String {
            """
            <div class="movie"><div class="info"><p><span class="header">識別碼:</span><span>\(number)</span></p></div></div>
            <a class="avatar-box" href="/star/neutralA"><div class="photo-frame"><img src="/pics/actress/neutralA_a.jpg" title="中性演員甲"></div><span>中性演員甲</span></a>
            <a class="avatar-box" href="/star/neutralB"><img src="/pics/actress/neutralB_a.jpg" title="中性演員乙"><span>中性演員乙</span></a>
            """
        }
        var checks = 0
        func expect(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        func parse(_ text: String, _ number: String = "DSOD-070", _ final: URL? = nil) throws -> [JavBusActorParser.Entry] {
            try JavBusActorParser.entries(html: text, number: number, finalURL: final ?? page)
        }
        let entries = try parse(html())
        expect(entries.count == 2, "two independent actors")
        expect(JavBusActorParser.select(entries, names: ["中性演員甲"])?.contains("neutralA_a.jpg") == true, "first exact actor")
        expect(JavBusActorParser.select(entries, names: ["中性演員乙"])?.contains("neutralB_a.jpg") == true, "second actor never first image")
        expect(JavBusActorParser.select(entries, names: ["合法别名", "中性演員乙"])?.contains("neutralB") == true, "supplied exact alias")
        expect(JavBusActorParser.select(entries, names: ["中性演員"]) == nil, "substring is not a name")
        expect(JavBusActorParser.select(entries, names: ["未匹配"]) == nil, "missing name")
        expect(try parse(html("DSOD-071")).isEmpty, "number mismatch")
        expect(try parse(html(), "DSOD-70").isEmpty, "no numeric padding guess")
        expect(try parse(html(), "DSOD-070", URL(string: "https://www.javbus.com/DSOD-071")!).isEmpty, "redirected page mismatch")
        expect(try parse(html()+"<div class='movie'></div>").isEmpty, "ambiguous movie structure")
        expect(try parse(html()+"<div>cf-chl-test</div>").isEmpty, "WAF never success")
        for bad in ["/pics/actress/nowprinting_a.jpg", "http://www.javbus.com/pics/actress/a_a.jpg", "https://evil.invalid/pics/actress/a_a.jpg", "/pics/actress/a_a.jpg?token=x", "https://u:p@www.javbus.com/pics/actress/a_a.jpg", "/pics/actress/../a_a.jpg", "/pics/actress/%61_a.jpg", "/pics/actress/unknown_a.jpg"] {
            let filtered = try parse(html().replacingOccurrences(of: "/pics/actress/neutralA_a.jpg", with: bad))
            expect(JavBusActorParser.select(filtered, names: ["中性演員甲"]) == nil, "unsafe/placeholder URL")
        }
        expect(JavBusActorParser.select(try parse(html().replacingOccurrences(of: "title=\"中性演員甲\"", with: "title=\"其他人\"")), names: ["中性演員甲"]) == nil, "inconsistent title")
        let collision = entries + [.init(name: "中性演員甲", actorURL: "https://www.javbus.com/star/other", imageURL: entries[1].imageURL)]
        expect(JavBusActorParser.select(collision, names: ["中性演員甲"]) == nil, "same name two IDs ambiguous")
        func actor(_ id: String, _ name: String, _ avatar: String? = nil) throws -> Actor {
            var data = ["id":id,"name":name]; data["avatar_url"] = avatar
            return try JSONDecoder().decode(Actor.self, from: JSONSerialization.data(withJSONObject: data))
        }
        let a = try actor("A", "中性演員甲"), b = try actor("B", "中性演員乙")
        let existing = try actor("owned", "中性演員甲", "https://example.invalid/owned.png")
        var calls = 0
        let fetch: JavBusActorService.Fetch = { _ in calls += 1; return .init(entries: entries, status: 200) }
        JavBusActorService.reset()
        let owned = try await JavBusActorService.lookup(actor: existing, numbers: ["DSOD-070"], fetch: fetch)
        expect(owned == nil && calls == 0, "AVDB never replaced")
        let first = try await JavBusActorService.lookup(actor: a, numbers: ["DSOD-070"], fetch: fetch)
        let second = try await JavBusActorService.lookup(actor: b, numbers: ["DSOD-070"], fetch: fetch)
        expect(first == entries[0].imageURL && second == entries[1].imageURL && calls == 1, "shared page cache selects per-actor")
        JavBusActorService.reset(); calls = 0
        let forbidden: JavBusActorService.Fetch = { _ in calls += 1; return .init(entries: entries, status: 403) }
        let deny = try await JavBusActorService.lookup(actor: a, numbers: ["DSOD-070"], fetch: forbidden)
        let denyAgain = try await JavBusActorService.lookup(actor: a, numbers: ["DSOD-070"], fetch: fetch)
        expect(deny == nil && denyAgain == nil && calls == 1, "403 negative cache even if body looks valid")
        JavBusActorService.reset(); calls = 0
        do {
            _ = try await JavBusActorService.lookup(actor: a, numbers: ["DSOD-070"], fetch: { _ in throw CancellationError() })
            preconditionFailure("cancellation must throw")
        } catch is CancellationError { checks += 1 }
        let retry = try await JavBusActorService.lookup(actor: a, numbers: ["DSOD-070"], fetch: fetch)
        expect(retry != nil && calls == 1, "cancel is never cached")
        APIClient.shared.token = "fixture-account-b"
        _ = try await JavBusActorService.lookup(actor: a, numbers: ["DSOD-070"], fetch: fetch)
        expect(calls == 2, "account-isolated cache")
        JavBusActorService.reset(); calls = 0
        _ = try await JavBusActorService.lookup(actor: a, numbers: ["DSOD-071", "DSOD-072", "DSOD-073"], fetch: { _ in calls += 1; return .init(entries: [], status: 200) })
        expect(calls == 2, "at most two known works")
        JavBusActorService.remember(actorID: "A", numbers: ["DSOD-070", "DSOD-071", "DSOD-072"])
        expect(JavBusActorService.knownNumbers(actorID: "A") == ["DSOD-070", "DSOD-071"], "bounded already-fetched work registry")
        JavBusActorService.reset(); calls = 0
        let cancelledTask = Task { @MainActor in
            try await JavBusActorService.lookup(actor: a, numbers: ["DSOD-070"], fetch: { _ in
                calls += 1; try await Task.sleep(nanoseconds: 2_000_000_000); return .init(entries: entries, status: 200)
            })
        }
        try await Task.sleep(nanoseconds: 30_000_000); cancelledTask.cancel()
        do { _ = try await cancelledTask.value; preconditionFailure("task should cancel") }
        catch is CancellationError { checks += 1 }
        let recovered = try await JavBusActorService.lookup(actor: a, numbers: ["DSOD-070"], fetch: fetch)
        expect(recovered != nil && calls == 2, "cancelled URL work releases permit and no cache")
        JavBusActorService.reset(); calls = 0
        let slow: JavBusActorService.Fetch = { _ in
            calls += 1; try await Task.sleep(nanoseconds: 50_000_000); return .init(entries: entries, status: 200)
        }
        async let one = JavBusActorService.lookup(actor: a, numbers: ["DSOD-070"], fetch: slow)
        async let two = JavBusActorService.lookup(actor: b, numbers: ["DSOD-070"], fetch: slow)
        let shared = try await (one, two)
        expect(shared.0 != nil && shared.1 != nil && calls == 1, "concurrent shared page coalesced")
        print("PASS JavBus actors251: \(checks) neutral production Swift assertions")
        if CommandLine.arguments.contains("--live") {
            do {
                let live = try await JavBusActorService.request("DSOD-070")
                let object: [String: Any] = ["number":"DSOD-070", "transport":"native URLSession (no cookies)", "status":live.status,
                    "entries":live.entries.map { ["name":$0.name,"actorURL":$0.actorURL,"imageURL":$0.imageURL] }]
                let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys,.prettyPrinted])
                try data.write(to: URL(fileURLWithPath: "javbus-native251.json"))
                print(String(decoding: data, as: UTF8.self))
            } catch {
                let data = try JSONSerialization.data(withJSONObject: ["number":"DSOD-070","transport":"native URLSession (no cookies)","error":String(describing:error),"success":false],options:[.sortedKeys,.prettyPrinted])
                try data.write(to: URL(fileURLWithPath: "javbus-native251.json"))
                print("Native JavBus HTTP failed; diagnostic saved (not a successful lookup)")
            }
        }
    }
}
