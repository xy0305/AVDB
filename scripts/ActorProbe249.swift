import Foundation

struct DetailEnvelope: Decodable { let actor: Actor? }
struct WorkProbe: Decodable { let id: String?; let number: String?; let actors: [Actor]? }
struct WorksEnvelope: Decodable { let movies: [WorkProbe]? }
struct RawFields: Decodable {
    let keys: [String]
    struct Key: CodingKey { var stringValue: String; var intValue: Int? { nil }; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil } }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        keys = c.allKeys.map(\.stringValue).sorted()
    }
}
struct DetailRaw: Decodable { let actor: RawFields? }

func text(_ actor: Actor) -> [String: Any] {
    ["id": actor.id, "name": actor.name ?? "", "other_name": actor.otherName ?? "", "name_zht": actor.nameZht ?? "",
     "keyword": actor.keyword ?? "", "type": actor.type ?? -1, "gender": actor.gender ?? -1,
     "birthday": actor.birthday ?? "", "age": actor.age ?? -1, "height": actor.height ?? -1,
     "cup": actor.cup ?? "", "bust": actor.bust ?? "", "waist": actor.waist ?? "", "hips": actor.hips ?? "",
     "twitter_id": actor.twitterID ?? "", "instagram_id": actor.instagramID ?? "",
     "videos_count": actor.videosCount ?? -1, "birthplace": actor.birthplace ?? "",
     "photo_present": !(actor.avatarURL ?? "").isEmpty || !(actor.coverURL ?? "").isEmpty]
}

@main struct ActorProbe249 {
    @MainActor static func main() async throws {
        let snapshot = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        let people = (snapshot["grok"] as! [String: Any])["people"] as! [[String: Any]]
        var searches: [[String: Any]] = []
        for query in ["美谷朱里", "美谷朱音", "美谷あかり", "吉沢明歩", "吉泽明步", "吉澤明步", "希崎ジェシカ", "希崎潔西卡"] {
            var item: [String: Any] = ["query": query]
            do {
                let rows = try await JavDBSDK.shared.searchActors(keyword: query, page: 1, limit: 20)
                item["count"] = rows.count
                item["actors"] = rows.map(text)
            } catch {
                item["errorType"] = String(describing: type(of: error))
                item["error"] = error.localizedDescription
            }
            searches.append(item)
        }
        var details: [[String: Any]] = []
        for id in ["PQJKe", "gyRE", "0yVv", "AdNn"] {
            var item: [String: Any] = ["requestedID": id]
            do {
                let raw: JavDBResponse<DetailRaw> = try await APIClient.shared.get("/api/v1/actors/\(id)", query: ["from_rankings": "false"])
                let detail: JavDBResponse<DetailEnvelope> = try await APIClient.shared.get("/api/v1/actors/\(id)", query: ["from_rankings": "false"])
                item["responseKeys"] = raw.data?.actor?.keys ?? []
                guard let actor = detail.data?.actor, actor.id == id else { item["missing"] = true; details.append(item); continue }
                item["actor"] = text(actor)
                let kind = String(actor.type ?? 0)
                let works: JavDBResponse<WorksEnvelope> = try await APIClient.shared.get("/api/v1/movies/tags", query: ["filter_by": "\(kind):a:\(id):", "page": "1", "limit": "8", "sort_by": "release", "order_by": "desc"])
                item["works"] = (works.data?.movies ?? []).map { movie -> [String: Any] in
                    ["id": movie.id ?? "", "number": movie.number ?? "", "actor_ids": (movie.actors ?? []).map(\.id), "actor_names": (movie.actors ?? []).map { $0.name ?? "" }]
                }
            } catch {
                item["errorType"] = String(describing: type(of: error))
                item["error"] = error.localizedDescription
            }
            details.append(item)
        }
        var identities: [[String: Any]] = []
        for source in ["美谷朱里", "吉泽明步", "希崎杰西卡"] {
            let person = people.first { ($0["nameZh"] as? String) == source }!
            identities.append(["source": source, "nameJa": person["nameJa"] as? String ?? "", "nameZh": person["nameZh"] as? String ?? "", "actressId": person["actressId"] as? Int ?? -1])
        }
        let payload: [String: Any] = ["transport": "unmodified production APIClient + signature + searchActors", "adultImagesDownloaded": false, "textOnly": true, "grok": identities, "searches": searches, "details": details]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "actor-probe249.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
