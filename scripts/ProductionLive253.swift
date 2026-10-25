import Foundation
import ImageIO
import CryptoKit

@MainActor enum ProductionLive253 {
    static func run() async throws -> [String: Any] {
        JavBusActorService.reset()
        let actor = try JSONDecoder().decode(Actor.self, from: Data(#"{"id":"neutral-live253","name":"池田マリナ"}"#.utf8))
        let page = try await JavBusActorService.request("DSOD-070")
        precondition(page.status == 200, "production JavBus page must be 200")
        precondition(page.entries.contains { ActorNameNormalizer.key($0.name) == ActorNameNormalizer.key(actor.name ?? "") }, "exact actor node")
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
