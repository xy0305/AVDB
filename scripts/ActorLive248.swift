struct RawActor: Decodable {
    let id: String
    let keys: [String]
    let aliases: [String]
    struct Key: CodingKey { var stringValue: String; var intValue: Int? { nil }; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil } }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        keys = c.allKeys.map(\.stringValue).sorted()
        let idKey = Key(stringValue: "id")!
        id = (try? c.decode(String.self, forKey: idKey)) ?? (try? c.decode(Int.self, forKey: idKey)).map(String.init) ?? ""
        aliases = ["aliases", "other_names", "alias"].flatMap { field -> [String] in
            let key = Key(stringValue: field)!
            return (try? c.decode([String].self, forKey: key)) ?? (try? c.decode(String.self, forKey: key)).map { [$0] } ?? []
        }
    }
}
struct RawActors: Decodable { let actors: [RawActor]? }
@main struct ActorLive248 {
    @MainActor static func main() async throws {
        let index = try JSONDecoder().decode(ActorAliasIndex.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let catalog = ActorAliasCatalog(index: index)
        let snapshot = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))) as! [String: Any]
        let people = (snapshot["grok"] as! [String: Any])["people"] as! [[String: Any]]
        var reports: [[String: Any]] = []
        for source in ["波多野结衣", "JULIA", "麻美由真", "桥本有菜"] {
            let person = people.first { ($0["nameZh"] as? String) == source }!
            let sourceName = person["nameJa"] as! String
            let sourceAliases = sourceName == source ? [] : [source]
            let identity = ExternalActorIdentity.resolve(sourceName: sourceName, aliases: sourceAliases, catalog: catalog)
            var report: [String: Any] = ["source": source, "actualSourceName": sourceName, "actualSourceAliases": sourceAliases, "canonical": identity.canonical ?? "", "queries": identity.queries, "policy247_rejects_before_network": identity.queries.count > 4]
            var policyRequests: [[String: Any]] = []
            do {
                let actor = try await JavVerseActorResolver.resolveActor(name: sourceName, aliases: sourceAliases, catalog: catalog) { q, page in
                    let rows = try await JavDBSDK.shared.searchActors(keyword: q, page: page)
                    policyRequests.append(["query": q, "page": page, "ids": rows.map(\.id), "count": rows.count]); return rows
                }
                report["actualPolicyMatch"] = actor?.id ?? "nil"
            } catch let error as JavVerseFailure { report["actualPolicyError"] = error.localizedDescription }
            catch { report["actualPolicyErrorType"] = String(describing: type(of: error)) }
            report["actualPolicyRequests"] = policyRequests
            var requests: [[String: Any]] = []
            do {
                let match = try await ExternalActorResolver.resolve(identity: identity, search: { q, page in
                    let rows = try await JavDBSDK.shared.searchActors(keyword: q, page: page)
                    requests.append(["query": q, "page": page, "ids": rows.map(\.id), "count": rows.count])
                    return rows
                })
                report["resolverMatch"] = match?.actor.id ?? "nil"
            } catch { report["resolverErrorType"] = String(describing: type(of: error)) }
            report["resolverRequests"] = requests
            var probes: [[String: Any]] = []
            for q in identity.queries.prefix(12) {
                for page in 1...3 {
                    var probe: [String: Any] = ["query": q, "page": page]
                    do {
                        let rows = try await JavDBSDK.shared.searchActors(keyword: q, page: page)
                        probe["actors"] = rows.map { a -> [String: Any] in
                            ["id": a.id, "name": a.name ?? "", "other_name": a.otherName ?? "", "name_zht": a.nameZht ?? "", "keyword": a.keyword ?? "", "photo_present": !(a.avatarURL ?? "").isEmpty || !(a.coverURL ?? "").isEmpty, "exact_match": ExternalActorResolver.match(identity, actor: a)]
                        }
                        let raw: JavDBResponse<RawActors> = try await APIClient.shared.get("/api/v2/search", query: ["q": q, "page": String(page), "type": "actor", "limit": "20"])
                        probe["raw_metadata"] = (raw.data?.actors ?? []).map { ["id": $0.id, "fields": $0.keys, "unparsed_aliases": $0.aliases] as [String: Any] }
                        probes.append(probe)
                        if rows.count < 20 { break }
                    } catch {
                        probe["errorType"] = String(describing: type(of: error)); probes.append(probe); break
                    }
                }
            }
            report["allAliasProbes"] = probes; reports.append(report)
        }
        struct Detail: Decodable { let actor: Actor? }
        struct Work: Decodable { let id: String?; let number: String?; let actors: [Actor]? }
        struct Works: Decodable { let movies: [Work]? }
        var details: [[String: Any]] = []
        for id in ["R2Vg", "mdRn", "1KBW", "YXKx", "ex3z", "RJM8"] {
            var item: [String: Any] = ["requestedID": id]
            do {
                let d: JavDBResponse<Detail> = try await APIClient.shared.get("/api/v1/actors/\(id)", query: ["from_rankings": "false"])
                if let a = d.data?.actor {
                    item["actor"] = ["id": a.id, "name": a.name ?? "", "other_name": a.otherName ?? "", "name_zht": a.nameZht ?? "", "type": a.type ?? -1, "gender": a.gender ?? -1, "birthday": a.birthday ?? "", "height": a.height ?? -1, "twitter_id": a.twitterID ?? "", "instagram_id": a.instagramID ?? "", "videos_count": a.videosCount ?? -1, "photo_present": !(a.avatarURL ?? "").isEmpty || !(a.coverURL ?? "").isEmpty] as [String: Any]
                    let w: JavDBResponse<Works> = try await APIClient.shared.get("/api/v1/movies/tags", query: ["filter_by": "\(a.type ?? 0):a:\(id):", "page": "1", "limit": "5", "sort_by": "release", "order_by": "desc"])
                    item["works"] = (w.data?.movies ?? []).map { ["id": $0.id ?? "", "number": $0.number ?? "", "actor_ids": ($0.actors ?? []).map(\.id)] as [String: Any] }
                }
            } catch { item["errorType"] = String(describing: type(of: error)) }
            details.append(item)
        }
        let data = try JSONSerialization.data(withJSONObject: ["transport": "unmodified production APIClient + signature + searchActors declaration", "adultImagesDownloaded": false, "reports": reports, "details": details], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "actor-live248.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
