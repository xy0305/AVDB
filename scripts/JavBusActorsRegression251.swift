import Foundation
import CryptoKit
import ImageIO

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
        expect(calls == 3, "bounded known works")
        JavBusActorService.remember(actorID: "A", numbers: ["DSOD-070", "DSOD-071", "DSOD-072"])
        expect(JavBusActorService.knownNumbers(actorID: "A") == ["DSOD-070", "DSOD-071", "DSOD-072"], "bounded already-fetched work registry")
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
        JavBusActorService.reset(); calls = 0
        let invalidExisting = try await JavBusActorService.lookup(actor: existing, numbers: ["DSOD-070"], existingFailed: true, fetch: fetch)
        expect(invalidExisting != nil && calls == 1, "failed AVDB image permits lookup; valid existing default preserved")
        JavBusActorService.reset(); calls = 0
        _ = try await JavBusActorService.lookup(actor: a, numbers: ["DSOD-071","DSOD-072","DSOD-073","DSOD-074","DSOD-075","DSOD-076","DSOD-077"], fetch: { _ in calls += 1; return .init(entries: [],status:200) })
        expect(calls == 6, "six is hard maximum, no full filmography")
        JavBusActorService.reset(); calls = 0
        _ = try await JavBusActorService.lookup(actor: a, numbers: ["DSOD-071","DSOD-072"], fetch: { _ in calls += 1; if calls == 1 { throw URLError(.timedOut) }; return .init(entries:entries,status:200) })
        expect(calls == 2, "transport error on first candidate does not discard later candidate")
        JavBusActorService.reset(); calls = 0
        _ = try await JavBusActorService.lookup(actor: a, numbers: ["DSOD-071","DSOD-072"], fetch: { _ in calls += 1; return .init(entries:[],status:302) })
        expect(calls == 1, "challenge stops work sweep")
        expect(ActorAvatarRedirectPolicy.permits(from:page,to:page,hops:0), "safe exact-resource HTTPS redirect")
        expect(!ActorAvatarRedirectPolicy.permits(from:page,to:page,hops:3), "three-hop bound")
        for unsafe in ["http://www.javbus.com/DSOD-070","https://127.0.0.1/DSOD-070","https://www.javbus.com.evil/DSOD-070","https://www.javbus.com/doc/driver-verify","https://www.javbus.com/DSOD-070?token=x","https://u:p@www.javbus.com/DSOD-070","https://www.javbus.com/DSOD-071","https://www.javbus.com:443/DSOD-070","https://www.javbus.com/%44SOD-070"] {
            expect(!ActorAvatarRedirectPolicy.permits(from:page,to:URL(string:unsafe)!,hops:0),"unsafe redirect rejected")
        }
        expect(!ActorPortraitBytes.valid(Data("<html>challenge</html>".utf8)), "HTML not image")
        expect(ActorPortraitBytes.valid(Data([255,216,255,0])), "JPEG signature")
        let rows = ["中性演員甲.jpg":"neutral.jpg?t=123"]
        expect(GfriendsPortraits.select(rows,names:["中性演員甲"])?.path.hasSuffix("/neutral.jpg") == true,"exact indexed portrait")
        expect(GfriendsPortraits.select(rows,names:["中性演員"]) == nil,"portrait substring rejected")
        expect(GfriendsPortraits.select(["中性演員甲.jpg":"../evil.jpg?t=123"],names:["中性演員甲"]) == nil,"index path traversal rejected")
        expect(GfriendsPortraits.select(rows.merging(["別名.jpg":"other.jpg?t=123"]) { a,_ in a },names:["中性演員甲","別名"]) == nil,"two different alias images ambiguous")
        let chinese = try actor("alias-test", "池田萬裡奈")
        expect(JavBusActorService.names(chinese).contains("池田マリナ"), "real bundled verified Chinese/Japanese alias")
        JavBusActorService.reset()
        JavBusActorService.remember(actorID:"A",numbers:["DSOD-071"])
        JavBusActorService.remember(actorID:"A",numbers:["DSOD-071","DSOD-070"])
        expect(JavBusActorService.knownNumbers(actorID:"A").count == 2,"already loaded work update changes revision inputs")
        JavBusActorService.reset(); calls = 0
        let noBudget = try await JavBusActorService.lookup(actor:a,numbers:["DSOD-070"],budget:0,fetch:fetch)
        expect(noBudget == nil && calls == 0,"zero budget starts no request")
        let holding: JavBusActorService.Fetch = { _ in calls += 1; try await Task.sleep(nanoseconds:200_000_000); return .init(entries:entries,status:200) }
        async let slotA = JavBusActorService.lookup(actor:a,numbers:["DSOD-071"],fetch:holding)
        async let slotB = JavBusActorService.lookup(actor:b,numbers:["DSOD-072"],fetch:holding)
        try await Task.sleep(nanoseconds:30_000_000)
        let queued = try await JavBusActorService.lookup(actor:a,numbers:["DSOD-073"],budget:0.01,fetch:fetch)
        expect(queued == nil && calls == 2,"queue budget does not start third request")
        _ = try await (slotA,slotB)
        print("PASS JavBus actors252: \(checks) neutral production Swift assertions")
        if CommandLine.arguments.contains("--live") {
            var object:[String:Any] = ["transport":"production native URLSession no cookies", "onlineSuccess":false]
            do {
                let live = try await JavBusActorService.request("DSOD-070")
                object["javbusStatus"] = live.status
                object["javbusEntries"] = live.entries.map { ["name":$0.name,"actorURL":$0.actorURL,"imageURL":$0.imageURL] }
                let identity = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"avatar-identity252.json"))) as! [[String:Any]]
                guard let row = identity.first, let id = row["id"] as? String, let name = row["name"] as? String, let numbers = row["numbers"] as? [String] else { throw URLError(.cannotParseResponse) }
                let real = try actor(id,name)
                object["actorID"] = id; object["name"] = name; object["names"] = JavBusActorService.names(real); object["numbers"] = numbers
                object["javbusLookup"] = try await JavBusActorService.lookup(actor:real,numbers:numbers) ?? ""
                if let hit = try await GfriendsPortraits.lookup(names:JavBusActorService.names(real)), let src = CGImageSourceCreateWithData(hit.data as CFData,nil), let image = CGImageSourceCreateImageAtIndex(src,0,nil) {
                    object["onlineSuccess"] = true;object["source"] = "Gfriends public 6-Tpowers agency portrait index";object["imageURL"] = hit.url; object["imageBytes"] = hit.data.count;object["imageSHA256"] = SHA256.hash(data:hit.data).map { String(format:"%02x",$0) }.joined();object["width"] = image.width;object["height"] = image.height
                    try hit.data.write(to:URL(fileURLWithPath:"native-portrait252.jpg"))
                }
            } catch { object["error"] = error.localizedDescription }
            object["gfriendsDiagnostics"] = GfriendsPortraits.diagnostics
            let data=try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]);try data.write(to:URL(fileURLWithPath:"javbus-native252.json"));print(String(decoding:data,as:UTF8.self))
        }
    }
}
