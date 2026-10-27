import Foundation

// Each adapter owns its public protocol; a failure never falls through to another source.
enum JableAdapter {
    // Build 270: explicit online host is fs1.app (documented Jable.TV mirror).
    // jable.tv remains CF-challenged for anonymous URLSession; this is not a silent
    // response-link rewrite — search/detail URLs are issued on the declared host only.
    static let site = URL(string: "https://fs1.app")!
    static func searchItems(_ code: String) -> [URLQueryItem] {
        [URLQueryItem(name:"mode",value:"async"),URLQueryItem(name:"function",value:"get_block"),URLQueryItem(name:"block_id",value:"list_videos_videos_list_search_result"),URLQueryItem(name:"q",value:code)]
    }
    static func search(_ code:String) -> URL {
        var c=URLComponents(string:"https://fs1.app/search/"+code+"/")!;c.queryItems=searchItems(code);return c.url!
    }
    static func lines(_ data:Data, page:URL, number:String, versions:Bool) throws -> [OnlineLine] {
        let text=try OnlineAdditional.html(data); try OnlineAdapters.rejectChallenge(text)
        let dom=try JRHTML.tree(text);var seen=Set<URL>()
        return dom.all { $0.tag == "a" }.compactMap { node in
            guard let raw=node.attrs["href"], let url=URL(string:raw,relativeTo:page)?.absoluteURL,
                  OnlinePolicy.metadata(url,source:.jable), url.path.hasPrefix("/videos/"),
                  let slug=url.path.split(separator:"/").last,
                  let version=OnlineIdentity.version(String(slug),number:number,allowVersions:versions),seen.insert(url).inserted else { return nil }
            return OnlineLine(source:.jable,recordID:String(slug),code:String(slug).uppercased(),version:version,lineKey:"primary",detailURL:url)
        }.prefix(5).map { $0 }
    }
}
enum MissAVAdapter {
    // Build 269: explicit online host is missav.fans (same verified apex as ranking default).
    // missav.ws remains CF-challenged for anonymous URLSession; this is not a silent
    // response-link rewrite — search/detail URLs are issued on the declared host only.
    static let site = URL(string: "https://missav.fans")!
    static func search(_ code:String) -> URL { URL(string:"https://missav.fans/en/search/"+code)! }
    static func lines(_ data:Data,page:URL,number:String,versions:Bool) throws -> [OnlineLine] {
        let text=try OnlineAdditional.html(data);try OnlineAdapters.rejectChallenge(text)
        let dom=try JRHTML.tree(text);var seen=Set<URL>()
        return dom.all { $0.tag == "a" }.compactMap { node in
            guard let raw=node.attrs["href"], let url=URL(string:raw,relativeTo:page)?.absoluteURL,
                  OnlinePolicy.metadata(url,source:.missav),!url.path.contains("/search/"),
                  let slug=url.path.split(separator:"/").last,
                  let version=OnlineIdentity.version(String(slug),number:number,allowVersions:versions),seen.insert(url).inserted else { return nil }
            return OnlineLine(source:.missav,recordID:String(slug),code:String(slug).uppercased(),version:version,lineKey:"primary",detailURL:url)
        }.prefix(5).map { $0 }
    }
}
enum MemoJavAdapter {
    static func page(_ code:String) -> URL { URL(string:"https://memojav.org/video/"+code)! }
    static func line(_ data:Data,page:URL,number:String) throws -> OnlineLine {
        try OnlineAdapters.rejectChallenge(OnlineAdditional.html(data))
        let text=try OnlineAdditional.exactDetail(data,page:page,code:number,source:.memojav)
        _=try OnlineAdditional.memoID(text,number:number)
        return OnlineLine(source:.memojav,recordID:number,code:number,version:"原始版本",lineKey:"primary",detailURL:page)
    }
}
enum OneTwoThreeAVAdapter {
    static func search(_ code:String) -> URL {
        var c=URLComponents(string:"https://123av.com/en/search")!;c.queryItems=[URLQueryItem(name:"keyword",value:code)];return c.url!
    }
    static func lines(_ data:Data,page:URL,number:String) throws -> [OnlineLine] {
        let text=try OnlineAdditional.html(data);try OnlineAdapters.rejectChallenge(text)
        let dom=try JRHTML.tree(text);var seen=Set<URL>()
        return dom.all { $0.tag == "a" }.compactMap { node in
            guard let raw=node.attrs["href"],let url=URL(string:raw,relativeTo:page)?.absoluteURL,
                  OnlinePolicy.metadata(url,source:.av123),url.path.hasPrefix("/en/v/"),
                  let slug=url.path.split(separator:"/").last,OnlineIdentity.key(String(slug)) == OnlineIdentity.key(number),seen.insert(url).inserted else { return nil }
            return OnlineLine(source:.av123,recordID:String(slug),code:String(slug).uppercased(),version:"原始版本",lineKey:"primary",detailURL:url)
        }.prefix(5).map { $0 }
    }
    static func embeds(_ data:Data,page:URL,number:String) throws -> [URL] {
        let text=try OnlineAdditional.html(data);try OnlineAdapters.rejectChallenge(text)
        let dom=try JRHTML.tree(text)
        guard OnlinePolicy.metadata(page,source:.av123), OnlineIdentity.key(page.lastPathComponent) == OnlineIdentity.key(number),
              dom.all({ $0.tag == "h1" }).contains(where: { OnlineIdentity.heading($0.text,number:number) }) else { throw OnlineFailure.noMatch }
        let configs=dom.all { $0.attrs["x-data"]?.hasPrefix("player(JSON.parse(") == true }.compactMap { $0.attrs["x-data"] }
        guard configs.count == 1,let config=configs.first,
              let slug=JRHTML.matches(#"\),\s*\d+,\s*'([a-z0-9-]+)'"#,config).first?[1],slug == page.lastPathComponent,
              let raw=JRHTML.matches(#"^player\(JSON\.parse\('((?:\\.|[^'\\])*)'\)"#,config).first?[1],raw.count <= 16384,
              let outer=("\""+raw+"\"").data(using:.utf8),
              let decoded=try? JSONSerialization.jsonObject(with:outer,options:.fragmentsAllowed) as? String,
              let inner=decoded.data(using:.utf8),let rows=try? JSONSerialization.jsonObject(with:inner) as? [[String:Any]],!rows.isEmpty,rows.count <= 8 else { throw OnlineFailure.incomplete }
        return try rows.map { row in
            guard let raw=row["url"] as? String,let url=URL(string:raw),OnlinePolicy.embed(url),url.path.hasPrefix("/e/") else { throw OnlineFailure.incomplete }
            return url
        }
    }
    static func stream(_ data:Data) throws -> URL {
        guard let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any],obj["status"] as? String == "ok",
              let media=obj["media"] as? [String:Any],let raw=media["stream"] as? String,
              let url=URL(string:raw),OnlinePolicy.discoveredMedia(url,source:.av123) else { throw OnlineFailure.incomplete }
        return url
    }
}

enum JavDayAdapter {
    // Path search avoids the query-form CF interstitial observed on /search/?wd=
    static func search(_ code: String) -> URL {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encoded = code.addingPercentEncoding(withAllowedCharacters: allowed) ?? code
        return URL(string: "https://javday.app/search/wd/" + encoded + "/")!
    }
    static func lines(_ data: Data, page: URL, number: String, versions: Bool) throws -> [OnlineLine] {
        let text = try OnlineAdditional.html(data); try OnlineAdapters.rejectChallenge(text)
        let dom = try JRHTML.tree(text); var seen = Set<URL>()
        return dom.all { $0.tag == "a" }.compactMap { node in
            guard let raw = node.attrs["href"], let url = URL(string: raw, relativeTo: page)?.absoluteURL,
                  OnlinePolicy.metadata(url, source: .javday), OnlinePolicy.javdaySlug(url) != nil,
                  let slug = OnlinePolicy.javdaySlug(url),
                  let version = OnlineIdentity.version(slug, number: number, allowVersions: versions),
                  seen.insert(url).inserted else { return nil }
            return OnlineLine(source: .javday, recordID: slug, code: slug.uppercased(), version: version, lineKey: "primary", detailURL: url)
        }.prefix(5).map { $0 }
    }
}
enum OnlineAdapters {
    static func rejectChallenge(_ text:String) throws {
        if MissAVHTML.isChallenge(text) { throw OnlineFailure.blocked }
    }
}
extension OnlineProvider {
    func discover(_ source:OnlineSource,number:String,versions:Bool) async throws -> [OnlineLine] {
        guard let code=OnlineIdentity.key(number) else { throw OnlineFailure.noMatch }
        switch source {
        case .jable:
            let page=JableAdapter.search(code);return try JableAdapter.lines(try await transport.fetch(page,cap:2*1024*1024,headers:OnlinePolicy.headers(referrer:JableAdapter.site)),page:page,number:code,versions:versions)
        case .missav:
            let page=MissAVAdapter.search(code);return try MissAVAdapter.lines(try await transport.fetch(page,cap:2*1024*1024,headers:OnlinePolicy.headers(referrer:MissAVAdapter.site)),page:page,number:code,versions:versions)
        case .av123:
            let page=OneTwoThreeAVAdapter.search(code)
            return try OneTwoThreeAVAdapter.lines(try await transport.fetch(page,cap:2*1024*1024),page:page,number:code)
        case .memojav:
            let page=MemoJavAdapter.page(code);return [try MemoJavAdapter.line(try await transport.fetch(page,cap:2*1024*1024),page:page,number:code)]
        case .javday:
            let page=JavDayAdapter.search(code)
            let headers=OnlinePolicy.headers(referrer:URL(string:"https://javday.app/")!, source:.javday)
            return try JavDayAdapter.lines(try await transport.fetch(page,cap:2*1024*1024,headers:headers),page:page,number:code,versions:versions)
        }
    }
    func resolve(_ line:OnlineLine,number:String,versions:Bool) async throws -> OnlinePlaybackPlan {
        let result = try await resolveMedia(line, number:number, versions:versions)
        return try await validatedPlan(media:result.media,referrer:result.referrer,line:line,number:number,pageIssued:true)
    }
    func resolveMedia(_ line:OnlineLine,number:String,versions:Bool) async throws -> (media:URL,referrer:URL) {
        try Task.checkCancellation()
        let slug = line.detailURL.map(OnlinePolicy.pathSlug) ?? ""
        guard OnlineIdentity.version(line.code,number:number,allowVersions:versions) != nil,
              let detail=line.detailURL,OnlinePolicy.metadata(detail,source:line.source),slug == line.recordID,
              slug.uppercased() == line.code.uppercased() else { throw OnlineFailure.noMatch }
        let data=try await transport.fetch(detail,cap:2*1024*1024,headers:OnlinePolicy.headers(referrer:detail, source:line.source))
        try OnlineAdapters.rejectChallenge(OnlineAdditional.html(data))
        let media:URL;let referrer:URL
        switch line.source {
        case .jable:
            let text=try OnlineAdditional.exactDetail(data,page:detail,code:number,source:.jable)
            media=try OnlineAdditional.jableMedia(text);referrer=detail
        case .missav:
            let text=try OnlineAdditional.exactDetail(data,page:detail,code:number,source:.missav)
            media=try OnlineAdditional.missavMedia(text);referrer=detail
        case .javday:
            let text=try OnlineAdditional.exactDetail(data,page:detail,code:number,source:.javday)
            media=try OnlineAdditional.javdayMedia(text, page:detail);referrer=detail
        case .av123:
            let embeds=try OneTwoThreeAVAdapter.embeds(data,page:detail,number:number)
            // One primary episode only; do not try alternate episode on failure.
            guard embeds.count == 1,let embed=embeds.first else { throw OnlineFailure.incomplete }
            _=try await transport.fetch(embed,cap:2*1024*1024,headers:OnlinePolicy.headers(referrer:detail))
            var c=URLComponents(url:embed,resolvingAgainstBaseURL:false)!;c.path="/stream"
            c.queryItems=(c.queryItems ?? [])+[URLQueryItem(name:"id",value:embed.lastPathComponent)]
            guard let url=c.url,OnlinePolicy.embed(url) else { throw OnlineFailure.unsafe }
            media=try OneTwoThreeAVAdapter.stream(try await transport.fetch(url,cap:128*1024,headers:OnlinePolicy.headers(referrer:embed)));referrer=embed
        case .memojav:
            let text=try OnlineAdditional.exactDetail(data,page:detail,code:number,source:.memojav)
            let id=try OnlineAdditional.memoID(text,number:number)
            referrer=URL(string:"https://memojav.org/embed/"+id)!
            let embed=try OnlineAdditional.html(try await transport.fetch(referrer,cap:2*1024*1024))
            try OnlineAdapters.rejectChallenge(embed)
            guard let declared=JRHTML.matches(#"\bid\s*:\s*['\"]([^'\"]+)['\"]"#,embed).first?[1],OnlineIdentity.key(declared) == OnlineIdentity.key(number) else { throw OnlineFailure.noMatch }
            var c=URLComponents(string:"https://memojav.org/hls/get_video_info.php")!
            c.queryItems=[URLQueryItem(name:"id",value:id)]+OnlineAdditional.memoProof(milliseconds:Int64(Date().timeIntervalSince1970*1000))
            media=try OnlineAdditional.memoMedia(try await transport.fetch(c.url!,cap:128*1024,headers:OnlinePolicy.headers(referrer:referrer)))
        }
        return (media,referrer)
    }
}
