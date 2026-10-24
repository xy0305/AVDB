import Foundation

@main struct AvatarIdentity252 {
 @MainActor static func main() async throws {
  var rows: [[String:Any]] = []
  for name in ["池田萬裡奈", "池田マリナ"] {
   do {
    let actors = try await JavDBSDK.shared.searchActors(keyword:name,page:1,limit:20)
    for actor in actors {
     var row: [String:Any] = ["query":name,"id":actor.id,"name":actor.name ?? "","otherName":actor.otherName ?? "","keyword":actor.keyword ?? "","nameZht":actor.nameZht ?? "","avatarURL":actor.avatarURL ?? "","coverURL":actor.coverURL ?? "","videosCount":actor.videosCount ?? -1]
     let works: JavDBResponse<Works252> = try await APIClient.shared.get("/api/v1/movies/tags",query:["filter_by":"\(actor.type ?? 0):a:\(actor.id):","page":"1","limit":"6","sort_by":"release","order_by":"desc"])
     let detail: JavDBResponse<Detail252> = try await APIClient.shared.get("/api/v1/actors/\(actor.id)",query:["from_rankings":"false"])
     if let a = detail.data?.actor {
      row["detailID"] = a.id; row["detailVideosCount"] = a.videosCount ?? -1
      row["detailAvatarURL"] = a.avatarURL ?? ""; row["detailCoverURL"] = a.coverURL ?? ""
      row["detailName"] = a.name ?? ""; row["detailOtherName"] = a.otherName ?? ""
     }
     row["numbers"] = (works.data?.movies ?? []).compactMap(\.number)
     rows.append(row)
    }
   } catch { rows.append(["query":name,"error":error.localizedDescription]) }
  }
  let data=try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]);try data.write(to:URL(fileURLWithPath:"avatar-identity252.json"));print(String(decoding:data,as:UTF8.self))
 }
}
struct Detail252:Decodable { let actor:Actor? }
struct Work252:Decodable { let number:String? }
struct Works252:Decodable { let movies:[Work252]? }
