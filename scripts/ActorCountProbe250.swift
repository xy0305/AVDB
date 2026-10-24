import Foundation

func text(_ actor: Actor) -> [String: Any] {
    ["id": actor.id, "name": actor.name ?? "", "other_name": actor.otherName ?? "", "name_zht": actor.nameZht ?? "",
     "type": actor.type ?? -1, "videos_count": actor.videosCount ?? -1, "videos_count_nil": actor.videosCount == nil,
     "photo_present": !(actor.avatarURL ?? "").isEmpty || !(actor.coverURL ?? "").isEmpty]
}

@main struct ActorCountProbe250 {
    @MainActor static func main() async throws {
        let snapshot = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        let index = try JSONDecoder().decode(ActorAliasIndex.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        let catalog = ActorAliasCatalog(index: index)
        let people = (snapshot["grok"] as! [String: Any])["people"] as! [[String: Any]]
        var reports: [[String: Any]] = []
        for source in ["美谷朱里", "吉泽明步"] {
            let person = people.first { ($0["nameZh"] as? String) == source }!
            let sourceName = person["nameJa"] as! String
            let aliases = sourceName == source ? [] : [source]
            let identity = ExternalActorIdentity.resolve(sourceName: sourceName, aliases: aliases, catalog: catalog)
            var calls: [[String: Any]] = []
            let search: ExternalActorResolver.Search = { query, page in
                let rows = try await JavDBSDK.shared.searchActors(keyword: query, page: page, limit: 20)
                calls.append(["query": query, "page": page, "count": rows.count, "actors": rows.map(text)])
                return rows
            }
            var item: [String: Any] = ["source": source, "sourceName": sourceName, "queries": identity.queries, "calls": calls]
            do {
                let outcome = try await ExternalActorResolver.inspect(identity: identity, search: search)
                item["calls"] = calls
                switch outcome {
                case .matched(let match):
                    item["resolution"] = "matched"
                    item["selectedID"] = match.actor.id
                    item["selectedVideos"] = match.actor.videosCount ?? -1
                    item["byVideoCount"] = match.byVideoCount ?? -1
                    item["selectedName"] = match.actor.name ?? ""
                case .ambiguous(let actors):
                    item["resolution"] = "ambiguous"
                    item["candidates"] = actors.map(text)
                case .incomplete(let actors, let queries):
                    item["resolution"] = "incomplete"
                    item["candidates"] = actors.map(text)
                    item["unfinished"] = queries
                case .notFound:
                    item["resolution"] = "notFound"
                }
            } catch {
                item["calls"] = calls
                item["errorType"] = String(describing: type(of: error))
                item["error"] = error.localizedDescription
            }
            reports.append(item)
        }
        let payload: [String: Any] = ["adultImagesDownloaded": false, "textOnly": true, "productionSearchActorsUnmodified": true, "reports": reports]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "actor-count-probe250.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
