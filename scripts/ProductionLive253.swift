import Foundation
import ImageIO
import CryptoKit

@MainActor enum ProductionLive253 {
    static func run() async throws -> [String: Any] {
        JavBusActorService.reset()
        let actor = try JSONDecoder().decode(Actor.self, from: Data(#"{"id":"neutral-live253","name":"池田マリナ"}"#.utf8))
        let page = try await JavBusActorService.request("DSOD-070")
        precondition(page.status == 200, "production JavBus page must be 200")
        guard page.entries.contains(where: { ActorNameNormalizer.key($0.name) == ActorNameNormalizer.key(actor.name ?? "") }) else {
            try await structureDiagnostic()
            throw URLError(.cannotParseResponse)
        }
        guard let hit = try await JavBusActorService.lookupArtwork(actor: actor, numbers: ["DSOD-070"]),
              let data = try await JavBusActorService.imageData(hit.imageURL, sourceURL: hit.sourceURL),
              let src = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw URLError(.cannotDecodeContentData) }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("portrait253.jpg"))
        return ["onlineJavBusSuccess": true, "source": "modified production JavBusActorService", "gfriendsCounted": false,
                "pageStatus": page.status, "entries": page.entries.count, "actor": actor.name ?? "", "imageURL": hit.imageURL.absoluteString,
                "sourceURL": hit.sourceURL.absoluteString, "referer": JavBusActorRequests.request(hit.imageURL, sourceURL: hit.sourceURL)!.value(forHTTPHeaderField: "Referer")!,
                "bytes": data.count, "sha256": SHA256.hash(data: data).map { String(format:"%02x",$0) }.joined(),
                "width": image.width, "height": image.height, "os": ProcessInfo.processInfo.operatingSystemVersionString]
    }
    static func structureDiagnostic() async throws {
        let url = JavBusPoster.page(number:"DSOD-070")!
        let session = URLSession(configuration:JavBusActorRequests.configuration(),delegate:JavBusActorRedirects(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        let (bytes,response) = try await session.bytes(for:JavBusActorRequests.request(url)!)
        var data = Data()
        for try await b in bytes { guard data.count < 768*1024 else { break }; data.append(b) }
        let html = String(decoding:data,as:UTF8.self), tree = try JRHTML.tree(html)
        let movies = tree.all { $0.tag == "div" && $0.cls("movie") }
        let infos = movies.flatMap { $0.all { $0.tag == "div" && $0.cls("info") } }
        let result:[String:Any] = ["status":(response as? HTTPURLResponse)?.statusCode ?? 0,"movies":movies.count,"infos":infos.count,
            "headers":infos.flatMap { $0.all { $0.tag == "span" && $0.cls("header") }.map(\.text) },
            "numberSpans":infos.flatMap { $0.all { $0.tag == "p" }.prefix(2).map { $0.children.filter { $0.tag == "span" }.map(\.text) } },
            "markers":["cf-chl-","challenge-platform","captcha","just a moment","age verification","driver-verify"].filter { html.lowercased().contains($0) },
            "avatars":tree.all { $0.tag == "a" && $0.cls("avatar-box") }.map { node in ["href":node.attrs["href"] ?? "", "labels":node.all { $0.tag == "span" }.map(\.text).joined(separator:"|"), "images":node.all { $0.tag == "img" }.map { ($0.attrs["src"] ?? "") + " title=" + ($0.attrs["title"] ?? "") }.joined(separator:"|")] }]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:"evidence253/structure253.json"))
    }
    static func checks() async throws {
        let page = JavBusPoster.page(number: "DSOD-070")!, image = URL(string:"https://www.javbus.com/pics/actress/neutral_a.jpg")!
        let p = JavBusActorRequests.request(page)!, i = JavBusActorRequests.request(image, sourceURL:page)!
        precondition(p.value(forHTTPHeaderField:"Accept") == JavBusActorRequests.pageAccept)
        precondition(i.value(forHTTPHeaderField:"Accept") == JavBusActorRequests.imageAccept)
        for req in [p,i] {
            precondition(req.value(forHTTPHeaderField:"User-Agent") == JavBusActorRequests.userAgent)
            precondition(req.value(forHTTPHeaderField:"Accept-Language") == JavBusActorRequests.language)
            precondition(!req.httpShouldHandleCookies && req.value(forHTTPHeaderField:"Cookie") == nil && req.value(forHTTPHeaderField:"Authorization") == nil)
        }
        precondition(i.value(forHTTPHeaderField:"Referer") == page.absoluteString)
        precondition(JavBusActorRequests.request(image) == nil)
        let c = JavBusActorRequests.configuration()
        precondition(c.httpCookieStorage == nil && c.urlCredentialStorage == nil && c.urlCache == nil && !c.httpShouldSetCookies)
        for (from,source) in [(page,Optional<URL>.none),(image,Optional(page))] {
            let r = JavBusActorRequests.redirected(from:from,to:from,hops:0,sourceURL:source)!
            precondition(r.value(forHTTPHeaderField:"User-Agent") == JavBusActorRequests.userAgent)
            precondition(r.value(forHTTPHeaderField:"Accept-Language") == JavBusActorRequests.language)
            precondition(r.value(forHTTPHeaderField:"Referer") == source?.absoluteString)
            precondition(r.value(forHTTPHeaderField:"Accept") == (source == nil ? JavBusActorRequests.pageAccept : JavBusActorRequests.imageAccept))
            precondition(JavBusActorRequests.redirected(from:from,to:from,hops:3,sourceURL:source) == nil)
            for unsafe in ["https://www.javbus.com/doc/driver-verify","https://www.javbus.com/login","https://evil.invalid/DSOD-070","http://www.javbus.com/DSOD-070","https://127.0.0.1/DSOD-070","https://192.168.1.1/DSOD-070","https://www.javbus.com/DSOD-070?x=1"] {
                precondition(JavBusActorRequests.redirected(from:from,to:URL(string:unsafe)!,hops:0,sourceURL:source) == nil)
            }
        }
        precondition(JavBusActorService.currentScope.contains("public-headers253"))
        let rejected = try await JavBusActorService.imageData(image, sourceURL:page)
        precondition(rejected == nil, "unproven source cannot download")
        print("PASS253 new header/context/redirect/security/version checks; original 57 assertions run separately unchanged")
    }
}
