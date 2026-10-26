import Foundation

@main struct TangxinRegression261 {
    static func reject(_ body: () throws -> Void) { do { try body(); fatalError("Expected rejection") } catch {} }
    static func main() async throws {
        try await TangxinNetworkRegression263.run()
        let root = TangxinPolicy.featured
        // Live-confirmed 307 spellings must be normalized BEFORE transport.
        for path in ["/featured/2", "/a/neutral", "/tag/original", "/tag/original/2"] {
            let raw = URL(string:"https://tangxinvlog.app" + path)!
            let canonical = TangxinPolicy.canonicalPage(raw)!
            precondition(canonical.absoluteString == raw.absoluteString + "/")
            precondition(TangxinPolicy.canonicalPage(canonical) == canonical)
            let normalizationClient = TangxinClient(transport:OnlineTransport(resolver:{ _ in ["93.184.216.34"] },loader:{ request in
                precondition(request.url == canonical, "Noncanonical URL would hit real HTTP 307")
                return Data("<div class='grid'></div>".utf8)
            }))
            _ = try await normalizationClient.list(raw)
        }
        for raw in ["http://tangxinvlog.app/featured/2", "https://evil.org/featured/2", "https://127.0.0.1/featured/2", "https://tangxinvlog.app:8443/featured/2", "https://tangxinvlog.app/featured/2?q=1", "https://tangxinvlog.app/featured/2#fragment", "https://tangxinvlog.app/tag/%2F/2"] {
            precondition(TangxinPolicy.canonicalPage(URL(string:raw)!) == nil)
        }
        // Production delegate rejects every redirect destination, including slash-only.
        // No task is resumed and no real network request occurs in this test.
        let redirectTransport = OnlineTransport()
        let session = URLSession(configuration:.ephemeral)
        let task = session.dataTask(with:root)
        for status in [301,302,303,307,308] {
            for target in ["https://tangxinvlog.app/featured/2/", "https://other.example.org/", "http://tangxinvlog.app/", "https://127.0.0.1/"] {
                let response = HTTPURLResponse(url:root,statusCode:status,httpVersion:"HTTP/1.1",headerFields:["Location":target])!
                var completed = false
                redirectTransport.urlSession(session,task:task,willPerformHTTPRedirection:response,newRequest:URLRequest(url:URL(string:target)!)) { redirected in
                    precondition(redirected == nil,"Redirect must remain fail-closed")
                    completed = true
                }
                precondition(completed)
            }
        }
        session.invalidateAndCancel()
        // Parsing must use the actual directory request URL, not the slashless input.
        let relativeClient = TangxinClient(transport:OnlineTransport(loader:{ request in
            precondition(request.url!.absoluteString == "https://tangxinvlog.app/featured/")
            return Data("<div class='grid'></div><a rel='next' href='2'>Next</a>".utf8)
        }))
        let relativePage = try await relativeClient.list(URL(string:"https://tangxinvlog.app/featured")!)
        precondition(relativePage.next?.absoluteString == "https://tangxinvlog.app/featured/2/")
        let slashDuplicates = TangxinParser.detailTags("<a href='/tag/original'>原创</a><a href='/tag/original/'>原创</a>",at:root)
        precondition(slashDuplicates.links.count == 1 && slashDuplicates.links[0].url.absoluteString.hasSuffix("/"))
        let first = try TangxinParser.list(TangxinFixtures261.first,at:root)
        precondition(first.videos.count == 1 && first.next?.path == "/featured/2")
        precondition(first.videos[0].author?.name == "黑料昵称")
        precondition(first.videos[0].url.host == root.host)
        let detail = try TangxinParser.detail(TangxinFixtures261.detail,at:first.videos[0].url)
        precondition(detail.video.author?.name == "黑料昵称")
        precondition(detail.tags == ["原创"] && detail.summary.contains("合成"))
        precondition(detail.tagLinks.first?.url.lastPathComponent == "original")
        let encodedTag = "/tag/%E5%8E%9F%E5%88%9B/"
        let parsedTags = TangxinParser.detailTags("<a href='\(encodedTag)'>原创</a><a href='\(encodedTag)'>原创</a><a href='https://evil.org/tag/x/'>外部</a><a class='tag'>只有文字</a><a href='/tag/hidden-camera/'>偷拍</a><a href='/tag/%E6%9C%AA%E6%88%90%E5%B9%B4/'>测试</a><a href='/tag/black/'>黑料</a>",at:first.videos[0].url)
        precondition(parsedTags.links.count == 2 && parsedTags.links[0].name == "原创")
        precondition(parsedTags.links[0].url.absoluteString.contains("%E5%8E%9F"))
        precondition(parsedTags.names.contains("只有文字") && !parsedTags.links.contains { $0.name == "只有文字" })
        let tagRoot = parsedTags.links[0].url
        precondition(TangxinPolicy.next(tagRoot.appendingPathComponent("2"),from:tagRoot))
        precondition(!TangxinPolicy.next(URL(string:"https://tangxinvlog.app/tag/other/2")!,from:tagRoot))
        for raw in ["http://tangxinvlog.app/tag/a/", "https://127.0.0.1/tag/a/", "https://tangxinvlog.app/tag/a/?q=x", "https://tangxinvlog.app/tag/a/b/", "https://tangxinvlog.app/tag/%2F/"] { precondition(!TangxinPolicy.page(URL(string:raw)!)) }
        precondition(detail.stream.host == TangxinPolicy.cdn)
        let author = try TangxinParser.list(TangxinFixtures261.authorPage,at:first.videos[0].author!.url)
        precondition(author.videos.count == 1 && author.next == nil)
        for word in ["未成年","偷拍","私密流出","迷奸","泄露","17岁","高中生","未满18"] {
            let page = try TangxinParser.list("<div class=\"grid\">"+TangxinFixtures261.card("bad",title:word)+"</div>",at:root)
            precondition(page.videos.isEmpty)
            reject { _ = try TangxinParser.detail(TangxinFixtures261.detail.replacingOccurrences(of:"成人自愿演示作品",with:word),at:first.videos[0].url) }
        }
        precondition(TangxinPolicy.permitted("普通黑料昵称 成人自愿原创"))
        for raw in ["http://tangxinvlog.app/featured/","https://127.0.0.1/featured/","https://tangxinvlog.app.evil.org/featured/","https://user:pass@tangxinvlog.app/featured/","https://tangxinvlog.app:8443/featured/","https://tangxinvlog.app/featured/?url=foo"] { precondition(!TangxinPolicy.page(URL(string:raw)!)) }
        for raw in ["https://t.5gcdn.xyz.evil.org/videos/n/index.m3u8","https://10.0.0.1/videos/n/index.m3u8","http://t.5gcdn.xyz/videos/n/index.m3u8"] { precondition(!TangxinPolicy.stream(URL(string:raw)!)) }
        precondition(!TangxinPolicy.next(URL(string:"https://tangxinvlog.app/a/Other/2")!,from:first.videos[0].author!.url))
        precondition(!TangxinPolicy.next(root,from:root))
        precondition(!TangxinPolicy.next(URL(string:"https://tangxinvlog.app/featured/3")!,from:root))
        let evilNext = TangxinFixtures261.first.replacingOccurrences(of:"/featured/2",with:"https://elsewhere.org/featured/2")
        let safeNext = try TangxinParser.list(evilNext,at:root)
        precondition(safeNext.next == nil)
        reject { _ = try TangxinParser.detail(TangxinFixtures261.detail.replacingOccurrences(of:"https://t.5gcdn.xyz/videos/neutral1/index.m3u8",with:""),at:first.videos[0].url) }
        let changed = try TangxinParser.list("<html>Challenge required</html>",at:root)
        precondition(changed.state == .structureChanged && changed.report.cards == 0)
        let safe = TangxinFixtures261.card("safe")
        let unsafe = TangxinFixtures261.card("blocked",title:"未成年")
        let nextLink = "<a rel='next' href='/featured/2'>Next</a>"
        let allBlocked = try TangxinParser.list("<div class='grid'>" + unsafe + "</div>" + nextLink,at:root)
        precondition(allBlocked.state == .filtered && allBlocked.next != nil && allBlocked.report.blocked == 1)
        let empty = try TangxinParser.list("<div class='grid additional'></div>" + nextLink,at:root)
        precondition(empty.state == .sourceEmpty && empty.report.blocked == 0 && empty.next != nil)
        let malformed = try TangxinParser.list("<div class='grid'><article class='card'><a class='cover-link' href='/v/missing/'></a></article></div>" + nextLink,at:root)
        precondition(malformed.state == .structureChanged && malformed.report.malformed == 1 && malformed.next != nil)
        let mixed = try TangxinParser.list("<nav><a href='/tag/risk/'>偷拍</a></nav><div class='grid'>" + safe + unsafe + "</div>" + nextLink,at:root)
        precondition(mixed.videos.count == 1 && mixed.report.blocked == 1 && mixed.state == .content && mixed.next != nil)
        let headingCard = "<article class='card'><a class='cover-link' href='/v/heading/'><img alt=''></a><h3 class='title'><a href='/v/heading/'>成人自愿合成标题</a></h3><a class='nickname' href='/a/test/'>黑料昵称</a></article>"
        let headingPage = try TangxinParser.list(headingCard,at:root)
        precondition(headingPage.videos.count == 1)
        let conflicting = headingCard.replacingOccurrences(of:"alt=''",with:"alt='成人自愿合成标题'").replacingOccurrences(of:">成人自愿合成标题<",with:">偷拍<")
        let conflictingPage = try TangxinParser.list(conflicting,at:root)
        precondition(conflictingPage.state == .filtered)
        // Optional live HTML captured with a read-only production-header request. Counts only.
        if let path = ProcessInfo.processInfo.environment["TANGXIN_LIVE_HTML"] {
            let live = try TangxinParser.list(String(contentsOfFile:path,encoding:.utf8),at:root)
            print("LIVE262 state=\(live.state.rawValue) cards=\(live.report.cards) extracted=\(live.report.extracted) blocked=\(live.report.blocked) malformed=\(live.report.malformed) duplicates=\(live.report.duplicates) displayed=\(live.videos.count) next=\(live.next != nil)")
        }
        let client = TangxinFixtures261.client()
        let liveDetail = try await client.detail(first.videos[0].url)
        let plan = try await client.playback(liveDetail)
        precondition(plan.headers["Referer"] == "https://tangxinvlog.app/" && plan.headers["Cookie"] == nil)
        precondition(plan.headers.count == 2)
        let escaped = TangxinFixtures261.playlist.replacingOccurrences(of:"segment.ts",with:"https://127.0.0.1/a.ts")
        reject { _ = try OnlineManifest.parse(Data(escaped.utf8),at:plan.url,root:plan.url) }
        let privateDNS = TangxinClient(transport:OnlineTransport(resolver:{ _ in ["127.0.0.1"] },loader:{ _ in fatalError("Private DNS must fail before loader") }))
        do { _ = try await privateDNS.list(root); fatalError("DNS rejection required") } catch {}
        print("PASS261 production Swift parser/detail/author/pagination/filter/URL/Referer/AES/private-DNS; synthetic, zero network")
    }
}
