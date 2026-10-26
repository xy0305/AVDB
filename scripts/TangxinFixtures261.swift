import Foundation

// Entirely synthetic: no real titles, accounts, identities, thumbnails or media.
enum TangxinFixtures261 {
    static let author = "/a/%E9%BB%91%E6%96%99%E6%98%B5%E7%A7%B0/"
    static func card(_ id:String, title:String = "成人自愿演示作品", authorPath:String = author) -> String {
        "<article class='card'><a href='/v/\(id)/' class='cover-link'><img alt='\(title)' src='https://t.5gcdn.xyz/videos/\(id)/cover.jpg'></a><div class='byline'><a href='\(authorPath)' class='nickname'>@黑料昵称</a></div></article>"
    }
    static let first = "<h1>合成精选</h1><div class=\"grid\">" + card("neutral1") + card("neutral1") + "</div><nav><a href='/featured/2'>下一页 →</a></nav>"
    static let second = "<div class=\"grid\">" + card("neutral1") + card("neutral2") + "</div>"
    static let authorPage = "<h1>@黑料昵称</h1><div class=\"grid\">" + card("neutral1") + "</div>"
    static let detail = "<video poster='https://t.5gcdn.xyz/videos/neutral1/cover.jpg'></video><article class='info'><h1>成人自愿演示作品</h1><a class='nickname' href='" + author + "'>@黑料昵称</a><p class='desc'>明确合成测试，无真实人物</p><a href='/tag/original/'>原创</a></article><script type='application/json'>{\"src\":\"https://t.5gcdn.xyz/videos/neutral1/index.m3u8\"}</script><section>" + card("unrelated",authorPath:"/a/Other/") + "</section>"
    static let playlist = "#EXTM3U\n#EXT-X-TARGETDURATION:5\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\"\n#EXTINF:5,\nsegment.ts\n#EXT-X-ENDLIST\n"
    static func client() -> TangxinClient {
        let attempts = TangxinUIAttempts264()
        let resolver: (@Sendable (String) async throws -> [String])? = ProcessInfo.processInfo.arguments.contains("--network263") ? { _ in ["198.18.0.1"] } : nil
        return TangxinClient(transport:OnlineTransport(resolver:resolver,loader: { request in
            if ProcessInfo.processInfo.arguments.contains("--auto264"), let url = request.url,
               url.path.hasPrefix("/featured") || url.path.hasPrefix("/a/") || url.path.hasPrefix("/tag/") {
                let second = url.path.split(separator:"/").last == "2"
                let cards = second ? card("neutral1") + card("tail264") : (1...12).map { card("scroll\($0)") }.joined()
                let next = second ? "" : "<a rel='next' href='\(url.path.hasPrefix("/a/") ? author : (url.path.hasPrefix("/tag/") ? "/tag/original/" : "/featured/"))2'>Next</a>"
                return Data(("<div class='grid'>" + cards + "</div>" + next).utf8)
            }
            if ProcessInfo.processInfo.arguments.contains("--empty-states262") {
                let path = request.url!.path
                let next: (Int) -> String = { "<a rel='next' href='/featured/\($0)'>Next</a>" }
                let html: String
                if path == "/featured" || path == "/featured/" {
                    html = "<div class='grid'>" + card("blocked",title:"未成年") + "</div>" + next(2)
                } else if path == "/featured/2" {
                    html = "<div class='grid'></div>" + next(3)
                } else if path == "/featured/3" {
                    html = "<article class='card'></article>" + next(4)
                } else {
                    html = "<div class='grid'>" + card("neutral1") + card("blocked",title:"偷拍") + "</div>"
                }
                return Data(html.utf8)
            }
            guard let url = request.url, request.value(forHTTPHeaderField:"Referer") == TangxinPolicy.origin.absoluteString, request.value(forHTTPHeaderField:"Cookie") == nil else { throw TangxinError.unsafe }
            if url.path == "/featured" || url.path == "/featured/" { return Data(first.utf8) }
            if url.path == "/featured/2" {
                if ProcessInfo.processInfo.arguments.contains("--failure264"), await attempts.failFirst() { throw TangxinError.structure }
                return Data(second.utf8)
            }
            if url.path.hasPrefix("/a/") { return Data(authorPage.utf8) }
            if url.path == "/v/neutral1" || url.path == "/v/neutral1/" { return Data(detail.utf8) }
            if url.path.hasSuffix(".m3u8") { return Data(playlist.utf8) }
            if url.path.hasSuffix("key.bin") { return Data(repeating:0,count:16) }
            // No external IO, even for images. Neutral SF Symbol placeholders in UI.
            throw TangxinError.structure
        }))
    }
}

actor TangxinUIAttempts264 {
    private var count = 0
    func failFirst() -> Bool { count += 1; return count == 1 }
}
