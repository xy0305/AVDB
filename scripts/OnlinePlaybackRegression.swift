import Foundation

actor OnlineRequests {
    var requests: [URLRequest] = []
    func add(_ r: URLRequest) { requests.append(r) }
    func count() -> Int { requests.count }
    func all() -> [URLRequest] { requests }
}
@main struct OnlinePlaybackRegression {
    static var assertions = 0
    static func check(_ value: Bool, _ message: String) {
        assertions += 1; precondition(value, message)
    }
    static func fails(_ expected: OnlineFailure, _ action: () throws -> Void) {
        do { try action(); preconditionFailure("expected \(expected)") }
        catch { check(OnlineFailure.classify(error) == expected, "wrong failure: \(error)") }
    }
    @MainActor static func settle(_ model: OnlinePlaybackModel) async throws {
        for _ in 0..<100 {
            if !model.states.values.contains(.querying), model.resolving == nil { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("model did not settle")
    }
    static func fixture(_ request: URLRequest) throws -> Data {
        try OnlineNeutralFixture.response(request.url!)
    }
    @MainActor static func main() async throws {
        check(OnlineSource.allCases.count == 6, "six provider registry")
        check(OnlineSource.thirdPartyAVDB.label == "第三方AVDB", "source is not user app")
        check(OnlineIdentity.key("ssis_001") == "SSIS-001", "normalization")
        for bad in ["SSIS-0010", "SSIS-01", "1SSIS-001", "SSIS-001-extra"] {
            check(OnlineIdentity.version(bad, number:"SSIS-001",allowVersions:false) == nil, "exact full ID")
        }
        check(OnlineIdentity.version("SSIS-001-ENGLISH-SUBTITLE",number:"SSIS-001",allowVersions:false) == nil,"versions opt-in")
        check(OnlineIdentity.version("SSIS-001-ENGLISH-SUBTITLE",number:"SSIS-001",allowVersions:true) == "ENGLISH-SUBTITLE","version retained")
        check(!OnlineIdentity.heading("SSIS-0010",number:"SSIS-001"),"heading boundary")
        for url in ["http://2608.xbv2608.com/a.m3u8","https://127.0.0.1/a.m3u8","https://10.0.0.1/a.m3u8","https://u:p@2608.xbv2608.com/a.m3u8","https://2608.xbv2608.com.evil.test/a.m3u8","https://localhost/a.m3u8"] {
            check(!OnlinePolicy.media(URL(string:url)!),"unsafe origin rejected")
        }
        let root = URL(string:"https://2608.xbv2608.com/neutral/demo/index.m3u8?opaque=a%2Fb")!
        check(root.absoluteString.contains("a%2Fb"),"opaque query preserved")
        check(OnlinePolicy.bound(URL(string:"https://2608.xbv2608.com/other/a.ts")!,to:root),"same-origin sibling path is legitimate HLS")
        let leaf = Data("#EXTM3U\n#EXTINF:4,\na.ts\n#EXT-X-ENDLIST\n".utf8)
        check(try OnlineManifest.parse(leaf,at:root,root:root).variants.isEmpty,"leaf manifest")
        let master = Data("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nchild.m3u8\n".utf8)
        check(try OnlineManifest.parse(master,at:root,root:root).variants.count == 1,"master variant")
        for key in ["#EXT-X-KEY:METHOD=AES-128,URI=\"key\"", "#EXT-X-SESSION-KEY:METHOD=AES-128,URI=\"key\""] {
            check(try OnlineManifest.parse(Data(("#EXTM3U\n"+key+"\n#EXTINF:4,\na.ts").utf8),at:root,root:root).keys.count == 1,"ordinary AES-128 is not DRM")
        }
        check(try OnlineManifest.parse(Data("#EXTM3U\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:4,\na.ts".utf8),at:root,root:root).keys.isEmpty,"METHOD NONE is unencrypted")
        check(try OnlineManifest.parse(Data("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"../key\",IV=0X1\n#EXTINF:4,\na.ts".utf8),at:root,root:root).keys.count == 1,"standard short IV and parent key URI supported")
        check(try OnlineManifest.parse(Data("#EXTM3U\n#EXT-X-SESSION-DATA:DATA-ID=\"neutral\",VALUE=\"metadata,not DRM\"\n#EXTINF:4,\na.ts".utf8),at:root,root:root).keys.isEmpty,"session metadata is not DRM")
        for key in ["METHOD=SAMPLE-AES,URI=\"key\"", "METHOD=SAMPLE-AES-CTR,URI=\"key\"", "METHOD=AES-128,KEYFORMAT=\"com.apple.streamingkeydelivery\",URI=\"skd://asset\"", "METHOD=AES-128,KEYFORMAT=\"urn:uuid:edef8ba9\",URI=\"key\""] {
            fails(.drm) { _ = try OnlineManifest.parse(Data(("#EXTM3U\n#EXT-X-KEY:"+key+"\n#EXTINF:4,\na.ts").utf8),at:root,root:root) }
        }
        fails(.parse) { _ = try OnlineManifest.parse(Data("<html>#EXTM3U</html>".utf8),at:root,root:root) }
        fails(.unsafe) { _ = try OnlineManifest.parse(Data("#EXTM3U\n#EXTINF:4,\nhttps://127.0.0.1/a.ts".utf8),at:root,root:root) }
        check(try OnlineManifest.parse(Data("#EXTM3U\n#EXTINF:4,\n../a.ts".utf8),at:root,root:root).variants.isEmpty,"canonical same-origin parent path allowed")
        let page = try fixture(URLRequest(url:OnlineProvider.page("DEMO-123")))
        check(try OnlineProvider.javmenu(page,number:"DEMO-123").count == 1,"real DOM selector")
        let issuedPage = Data("<link rel='canonical' href='https://javmenu.com/zh/DEMO-123'><h1>DEMO-123 Neutral</h1><a data-m3u8='//issued-cdn.example.net/neutral/index.m3u8?opaque=a%2Fb'>1</a>".utf8)
        let issuedMenu = try OnlineProvider.javmenu(issuedPage, number:"DEMO-123")
        check(issuedMenu.count == 1 && issuedMenu[0].host == "issued-cdn.example.net" && issuedMenu[0].absoluteString.contains("a%2Fb"),"protocol-relative page-issued host outside stale CDN allowlist")
        fails(.noMatch) { _ = try OnlineProvider.javmenu(Data("<link rel='canonical' href='https://javmenu.com/zh/DEMO-123'><h1>DEMO-1230</h1><a data-m3u8='https://issued-cdn.example.net/a.m3u8'>1</a>".utf8), number:"DEMO-123") }
        let bad = String(data:page,encoding:.utf8)!.replacingOccurrences(of:"<h1>DEMO-123",with:"<h1>DEMO-1230")
        fails(.noMatch) { _ = try OnlineProvider.javmenu(Data(bad.utf8),number:"DEMO-123") }
        fails(.blocked) { _ = try OnlineProvider.javmenu(Data("<html>Just a moment cf-chl-</html>".utf8),number:"DEMO-123") }
        let scriptOnly = Data("<link rel='canonical' href='https://javmenu.com/zh/DEMO-123'><h1>DEMO-123</h1><script>var fake=\"<a data-m3u8='https://2608.xbv2608.com/a.m3u8'>\"</script>".utf8)
        check(try OnlineProvider.javmenu(scriptOnly,number:"DEMO-123").isEmpty,"no script fake anchor")
        fails(.parse) { _ = try OnlineProvider.config(Data("window.PLAYER_CONFIG = makeSomething();".utf8)) }
        let log = OnlineRequests()
        let provider = OnlineProvider(transport:OnlineTransport(loader:{ request in await log.add(request); return try fixture(request) }))
        let rows = try await provider.discover(.thirdPartyAVDB,number:"DEMO-123",versions:false)
        check(rows.count == 1 && rows[0].recordID == "1" && rows[0].lineKey == "Full","actual object server_data schema")
        let plan = try await provider.resolve(rows[0],number:"DEMO-123",versions:false)
        check(plan.url.host == "helvid.com","source-bound fixture host")
        check(plan.headers["Referer"] == "https://upload18.org/play/neutral/demo","scoped source referrer")
        check(plan.headers["Authorization"] == nil && plan.headers["Cookie"] == nil,"credential isolation")
        let requests = await log.all()
        check(!requests.contains(where: { $0.url?.path.hasSuffix(".ts") == true }),"no segment probe")
        check(requests.allSatisfy { $0.value(forHTTPHeaderField:"Authorization") == nil && $0.value(forHTTPHeaderField:"Cookie") == nil },"no account headers")
        let model = OnlinePlaybackModel(provider:provider)
        check(model.states.isEmpty && model.plan == nil,"manual only, no eager discovery or playback")
        let before = await log.count()
        model.query(.javmenu,number:"DEMO-123",versions:false); try await settle(model)
        if case .found(let lines) = model.state(.javmenu) { check(lines.count == 1,"found one route") } else { preconditionFailure("query state") }
        check(model.plan == nil,"no auto select")
        let after = await log.count(); check(after == before+1,"one bounded query")
        model.query(.javmenu,number:"DEMO-123",versions:false); try await settle(model)
        check(await log.count() == after,"two minute cache")
        model.reset(); model.query(.javmenu,number:"DEMO-123",versions:false); try await settle(model)
        check(await log.count() == after+1,"account/settings namespace invalidation")
        let failing = OnlineProvider(transport:OnlineTransport(loader:{ request in
            if request.url!.host == "avdbapi.com" { throw OnlineFailure.blocked }; return try fixture(request)
        }))
        let isolated = OnlinePlaybackModel(provider:failing)
        isolated.query(.thirdPartyAVDB,number:"DEMO-123",versions:false); isolated.query(.javmenu,number:"DEMO-123",versions:false)
        try await settle(isolated)
        check(isolated.state(.thirdPartyAVDB) == .failed(.blocked),"403 isolated source")
        if case .found = isolated.state(.javmenu) {} else { preconditionFailure("other source survives") }
        let slow = OnlineProvider(transport:OnlineTransport(loader:{ _ in try await Task.sleep(nanoseconds:2_000_000_000); return Data() }))
        let cancelled = OnlinePlaybackModel(provider:slow)
        cancelled.query(.javmenu,number:"DEMO-123",versions:false); cancelled.query(.thirdPartyAVDB,number:"DEMO-123",versions:false)
        cancelled.query(.av01,number:"DEMO-123",versions:false)
        check(cancelled.state(.av01) == .idle,"two-source concurrent ceiling")
        cancelled.cancel(.javmenu); check(cancelled.state(.javmenu) == .idle && cancelled.state(.thirdPartyAVDB) == .querying,"independent cancel")
        cancelled.reset(); try await Task.sleep(nanoseconds:30_000_000)
        check(cancelled.states.isEmpty && cancelled.plan == nil,"no stale result after close/reset")
        check(OnlineFailure.classify(NSError(domain:NSURLErrorDomain,code:-1202)) == .tls,"TLS state")
        check(OnlineFailure.classify(NSError(domain:NSURLErrorDomain,code:-1001)) == .timeout,"timeout state")
        check(OnlineFailure.classify(NSError(domain:NSURLErrorDomain,code:-1003)) == .resolver,"temporary DNS failure is not an unsafe-origin verdict")
        let av = Data("{\"videos\":[{\"id\":42439,\"dvd_id\":\"SSIS-001\"},{\"id\":1,\"dvd_id\":\"SSIS-0010\"}]}".utf8)
        check(try OnlineAdditional.av01Records(av,number:"SSIS-001").count == 1,"AV01 real id exact matching")
        let proof = OnlineAdditional.memoProof(milliseconds:1792686900000)
        check(proof.count == 2 && proof[0].name == "sig" && proof[1].name == "sts","normal public timestamp proof")
        check(proof[0].value == "NjkwMDAwMA" && proof[1].value == "6534508","public protocol deterministic vector")
        let protectedLog = OnlineRequests()
        let protectedProvider = OnlineProvider(transport:OnlineTransport(loader:{ request in
            await protectedLog.add(request)
            if request.url!.path.hasSuffix("index.m3u8") { return master }
            if request.url!.path.hasSuffix("child.m3u8") { return Data("#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"key\"\n#EXTINF:4,\na.ts".utf8) }
            return try fixture(request)
        }))
        do {
            _ = try await protectedProvider.resolve(OnlineLine(source:.javmenu,recordID:"DEMO-123",code:"DEMO-123",version:"原始版本",lineKey:"0",routeDigest:OnlineProvider.routeDigest(URL(string:"https://2608.xbv2608.com/neutral/demo/index.m3u8")!)),number:"DEMO-123",versions:false)
            preconditionFailure("protected child must not create a player plan")
        } catch { check(OnlineFailure.classify(error) == .drm,"master child DRM blocks entire plan") }
        let protectedRequests = await protectedLog.all()
        check(protectedRequests.contains(where: { $0.url!.path.hasSuffix("child.m3u8") }),"actual child manifest validation")
        check(!protectedRequests.contains(where: { $0.url!.path.hasSuffix("key") || $0.url!.path.hasSuffix(".ts") }),"never request keys or segments")
        check(try OnlineAdditional.memoMedia(Data("{\"success\":true,\"type\":\"hls\",\"url\":\"https%3A%2F%2Fvideo10.memojav.net%2Fstream%2FDEMO-123%2Fmaster.m3u8\"}".utf8)).host == "video10.memojav.net","normal once-encoded URL")
        // The user supplied the same script twice; these neutral fixtures exercise
        // its actual async search -> selected href -> video-info h4 -> hlsUrl flow.
        let jableSearch = try OnlineAdditional.jableSearch("SNOS-329")
        check(OnlinePolicy.metadata(jableSearch, source:.jable),"actual async search endpoint admitted")
        check(!OnlinePolicy.metadata(URL(string:jableSearch.absoluteString + "&redirect=https://evil.example")!,source:.jable),"async query cannot expand permissions")
        let jableHTML = Data("<div class='video-img-box'><h6 class='title'><a href='https://jable.tv/videos/snos-329/'>SNOS-329 Neutral</a></h6></div><a href='/videos/snos-329/'>duplicate</a><a href='/videos/snos-329-chinese-subtitle/'>SNOS-329 neutral subtitle</a><a href='/videos/snos-3290/'>SNOS-3290</a><a href='https://jable.tv.evil.example/videos/snos-329/'>SNOS-329</a>".utf8)
        let exactJable = try OnlineAdditional.jableLines(jableHTML,base:jableSearch,number:"SNOS-329",versions:false)
        let allJable = try OnlineAdditional.jableLines(jableHTML,base:jableSearch,number:"SNOS-329",versions:true)
        check(exactJable.count == 1 && allJable.count == 2,"complete Jable slug, duplicates, suffix opt-in, no first random candidate")
        check(exactJable[0].detailURL?.absoluteString == "https://jable.tv/videos/snos-329/","actual selected href is preserved")
        check(allJable[1].version == "CHINESE-SUBTITLE","explicit version retained")
        let versionURL = allJable[1].detailURL!
        let versionDetail = "<meta property='og:url' content='\(versionURL.absoluteString)'><section class='video-info'><h4>SNOS-329-CHINESE-SUBTITLE Neutral</h4></section>"
        _ = try OnlineAdditional.exactDetail(Data(versionDetail.utf8),page:versionURL,code:"SNOS-329",source:.jable)
        check(true,"complete explicit suffix in heading retained without loose matching")
        let jableDetail = "<meta property='og:url' content='https://jable.tv/videos/snos-329/'><section class='video-info'><h4>SNOS-329 Neutral fixture</h4></section><script>var hlsUrl = '//public-media.jable-cdn.net/hls/neutral/index.m3u8?opaque=a%2Fb';</script>"
        _ = try OnlineAdditional.exactDetail(Data(jableDetail.utf8),page:exactJable[0].detailURL!,code:"SNOS-329",source:.jable)
        check(true,"real Jable video-info h4 is not rejected for lacking h1")
        let issued = try OnlineAdditional.jableMedia(jableDetail)
        check(issued.host == "public-media.jable-cdn.net" && issued.absoluteString.contains("a%2Fb"),"protocol-relative page-issued CDN and opaque query")
        let escapedDetail = jableDetail.replacingOccurrences(of:"//public-media",with:#"https:\/\/public-media"#)
        check(try OnlineAdditional.jableMedia(escapedDetail) == issued,"safe literal URL escape decoding")
        fails(.unsupported) { _ = try OnlineAdditional.jableMedia("<script>var hlsUrl = computeSomething();</script>") }
        fails(.unsupported) { _ = try OnlineAdditional.jableMedia("<div>var hlsUrl = 'https://public-media.jable-cdn.net/x.m3u8';</div>") }
        fails(.unsafe) { _ = try OnlineAdditional.jableMedia("<script>var hlsUrl = 'https://127.0.0.1/a.m3u8';</script>") }
        fails(.noMatch) { _ = try OnlineAdditional.exactDetail(Data(jableDetail.replacingOccurrences(of:"SNOS-329 Neutral",with:"SNOS-3290 Neutral").utf8),page:exactJable[0].detailURL!,code:"SNOS-329",source:.jable) }
        for bad in ["127.0.0.1","10.0.0.1","169.254.169.254","100.64.0.1","192.168.1.1","172.31.9.1","198.18.0.1","203.0.113.1","::1","fd00::1","fe80::1","2001:db8::1","::ffff:127.0.0.1"] {
            check(!OnlineMediaScope.publicAddress(bad),"DNS private/special-use address rejected")
        }
        check(OnlineMediaScope.publicAddress("1.1.1.1"),"public IPv4 accepted")
        check(OnlineMediaScope.publicAddress("2606:4700:4700::1111"),"public IPv6 accepted")
        let encryptedMaster = Data("#EXTM3U\n#EXT-X-SESSION-KEY:METHOD=AES-128,KEYFORMAT=\"identity\",URI=\"../keys/neutral.key\"\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"neutral,fixture\",URI=\"audio.m3u8\"\n#EXT-X-STREAM-INF:BANDWIDTH=1000,AUDIO=\"audio\"\nrenditions/720/index.m3u8\n".utf8)
        let encryptedLeaf = Data("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"../../../keys/neutral.key\"\n#EXTINF:4,\n../../segments/a.ts\n#EXT-X-ENDLIST\n".utf8)
        let jableLog = OnlineRequests()
        let jableProvider = OnlineProvider(transport:OnlineTransport(loader:{ request in
            await jableLog.add(request)
            let u = request.url!
            if u.host == "jable.tv" && u.path.hasPrefix("/search/") { return jableHTML }
            if u.host == "jable.tv" { return Data(jableDetail.utf8) }
            if u.path == "/hls/neutral/index.m3u8" { return encryptedMaster }
            if u.path.hasSuffix("audio.m3u8") { return leaf }
            if u.path.hasSuffix(".key") { return Data(repeating:0,count:16) }
            if u.path.hasSuffix("index.m3u8") { return encryptedLeaf }
            preconditionFailure("unexpected synthetic request")
        }))
        let jableRows = try await jableProvider.discover(.jable,number:"SNOS-329",versions:false)
        let jableQueryCount = await jableLog.count()
        check(jableRows.count == 1 && jableQueryCount == 1,"production Jable discover sends one actual async search")
        let jablePlan = try await jableProvider.resolve(jableRows[0],number:"SNOS-329",versions:false)
        check(jablePlan.url == issued,"production Jable resolver reaches unchanged original AES-128 master")
        check(jablePlan.headers["Referer"] == exactJable[0].detailURL!.absoluteString && jablePlan.headers["Origin"] == "https://jable.tv","normal Jable playback referer/origin")
        let jableRequests = await jableLog.all()
        check(jableRequests.filter { $0.url!.path.hasSuffix(".key") }.count == 1,"public standard AES key preflight deduplicated, not decrypted or logged")
        check(jableRequests.contains { $0.url!.path.hasSuffix("audio.m3u8") } && jableRequests.contains { $0.url!.path.contains("renditions/720") },"all adaptive audio and rendition manifests validated")
        check(!jableRequests.contains { $0.url!.path.hasSuffix(".ts") },"no real or fixture segment probe")
        check(jableRequests.allSatisfy { $0.value(forHTTPHeaderField:"Authorization") == nil && $0.value(forHTTPHeaderField:"Cookie") == nil },"new CDN never receives app credentials")
        fails(.unsafe) { _ = try OnlineManifest.parse(Data("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"https://another-cdn.net/key\"\n#EXTINF:4,\na.ts".utf8),at:root,root:root) }
        fails(.parse) { _ = try OnlineManifest.parse(Data("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,METHOD=NONE,URI=\"key\"\n#EXTINF:4,\na.ts".utf8),at:root,root:root) }
        fails(.parse) { _ = try OnlineManifest.parse(Data("#EXTM3U\n#EXT-X-SESSION-KEY:METHOD=NONE\n#EXTINF:4,\na.ts".utf8),at:root,root:root) }
        let memoLog = OnlineRequests()
        let memoProvider = OnlineProvider(transport:OnlineTransport(loader:{ request in
            await memoLog.add(request)
            let u = request.url!
            if u.path.hasPrefix("/video/") { return Data("<link rel='canonical' href='https://memojav.org/video/DEMO-123'><h1>DEMO-123 Neutral</h1><iframe src='/embed/DEMO-123'></iframe>".utf8) }
            if u.path.hasPrefix("/embed/") { return Data("<script>var player = {id:'DEMO-123'};</script>".utf8) }
            if u.path == "/hls/get_video_info.php" { return Data("{\"success\":true,\"type\":\"hls\",\"url\":\"https://video10.memojav.net/stream/DEMO-123/master.m3u8\"}".utf8) }
            return leaf
        }))
        let memoRows = try await memoProvider.discover(.memojav,number:"DEMO-123",versions:false)
        let memoPlan = try await memoProvider.resolve(memoRows[0],number:"DEMO-123",versions:false)
        check(memoPlan.url.host == "video10.memojav.net" && memoPlan.headers["Referer"] == "https://memojav.org/embed/DEMO-123","MemoJav production literal flow remains unchanged")
        let memoRequests = await memoLog.all()
        check(memoRequests.contains { $0.url!.path == "/hls/get_video_info.php" && $0.url!.query?.contains("sig=") == true && $0.url!.query?.contains("sts=") == true },"MemoJav normal public timestamp proof retained")
        check(memoPlan.headers["Origin"] == nil,"Jable Origin never leaks into MemoJav")
        let missavHTML = Data("<a href='https://missav.ai/cn/snos-329'>SNOS-329 Neutral</a><a href='/cn/snos-329-chinese-subtitle/'>subtitle</a><a href='/cn/snos-3290'>SNOS-3290</a>".utf8)
        let missavRows = try OnlineAdditional.missavLines(missavHTML, base: URL(string:"https://missav.fans/cn/search/SNOS-329")!, number:"SNOS-329", versions:false)
        check(missavRows.count == 1 && missavRows[0].detailURL?.absoluteString == "https://missav.fans/cn/snos-329","current host rewrite keeps exact slug")
        let missavDetail = "<link rel='canonical' href='https://missav.fans/cn/snos-329'><h1>SNOS-329 Neutral</h1><script>source = \"https:\\/\\/surrit.neutral.media/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/playlist.m3u8\";</script>"
        check(try OnlineAdditional.missavMedia(missavDetail).host == "surrit.neutral.media","direct surrit literal only")
        fails(.unsupported) { _ = try OnlineAdditional.missavMedia("<script>eval(function(p,a,c,k,e,d){return p})</script>") }
        fails(.unsafe) { _ = try OnlineAdditional.missavMedia("<script>var source='https://surrit.neutral.media/not-a-uuid/playlist.m3u8';</script>") }
        let avDetail: [String:Any] = ["id":7,"dvd_id":"SNOS-329","storage_base":"/neutral","hls_layout":["master":"https://media.neutral.media/neutral/master.m3u8"]]
        check(try OnlineAdditional.av01Media(avDetail).host == "media.neutral.media","literal AV01 master accepted")
        fails(.incomplete) { _ = try OnlineAdditional.av01Media(["hls_layout":["token":"not-a-url"]]) }
        let issuedAV = Data("<script>window.PLAYER_CONFIG = {\"m3u8\":\"https://issued.neutral.media/neutral/index.m3u8?opaque=a%2Fb\"};</script>".utf8)
        check(try OnlineProvider.config(issuedAV).host == "issued.neutral.media","current embed literal is not limited to stale CDN")
        fails(.parse) { _ = try OnlineProvider.config(Data("<script>window.PLAYER_CONFIG = {\"m3u8\":\"https://issued.neutral.media/a.m3u8\",\"url\":\"https://other.neutral.media/b.m3u8\"};</script>".utf8)) }
        let six = OnlineProvider(transport: OnlineTransport(loader: { try OnlineNeutralFixture.response($0.url!) }))
        for source in [OnlineSource.missav, .av01] {
            let rows = try await six.discover(source, number:"DEMO-123", versions:false)
            let plan = try await six.resolve(rows[0], number:"DEMO-123", versions:false)
            check(plan.source == source && plan.headers["Cookie"] == nil && plan.headers["Authorization"] == nil, "neutral \(source.rawValue) reaches player handoff")
        }
        check(try await six.resolve(try await six.discover(.missav, number:"DEMO-123", versions:false)[0], number:"DEMO-123", versions:false).headers["Origin"] == "https://missav.fans","scoped MissAV origin")
        let leakHTML = Data("<a href='/cn/snos-329-uncensored-leak'>SNOS-329 leak</a><a href='/cn/snos-329'>SNOS-329 original</a><a href='/cn/snos-3290'>SNOS-3290</a>".utf8)
        let leakRows = try OnlineAdditional.missavLines(leakHTML, base: URL(string:"https://missav.fans/cn/search/SNOS-329")!, number:"SNOS-329", versions:true)
        check(leakRows.count == 2 && leakRows[0].detailURL != leakRows[1].detailURL,"version lines stay separate")
        let selected = leakRows[0]
        let selectedDetail = "<link rel='canonical' href='\(selected.detailURL!.absoluteString)'><h1>\(selected.code) Neutral</h1><video class='player' src='https://surrit.selected.media/11111111-1111-1111-1111-111111111111/720p/video.m3u8'></video>"
        let other = leakRows[1]
        let otherDetail = "<link rel='canonical' href='\(other.detailURL!.absoluteString)'><h1>\(other.code) Neutral</h1><video class='player' src='https://surrit.other.media/22222222-2222-2222-2222-222222222222/720p/video.m3u8'></video>"
        let isolatedLog = OnlineRequests()
        let isolatedProvider = OnlineProvider(transport: OnlineTransport(loader: { request in
            await isolatedLog.add(request)
            let url = request.url!
            if url.path.hasPrefix("/cn/search/") { return leakHTML }
            if url.absoluteString == selected.detailURL!.absoluteString { return Data(selectedDetail.utf8) }
            if url.absoluteString == other.detailURL!.absoluteString { return Data(otherDetail.utf8) }
            if url.host == "surrit.selected.media" { return Data("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\n720p/video.m3u8\n".utf8) }
            if url.path.hasSuffix("720p/video.m3u8") { return leaf }
            preconditionFailure("unexpected selected-line request")
        }))
        let chosen = try await isolatedProvider.discover(.missav, number:"SNOS-329", versions:true)
        check(chosen.count == 2,"production discovery retains both exact versions")
        let chosenPlan = try await isolatedProvider.resolve(chosen[0], number:"SNOS-329", versions:true)
        check(chosenPlan.url.host == "surrit.selected.media","selected line uses only its own detail playlist")
        let chosenRequests = await isolatedLog.all()
        check(!chosenRequests.contains { $0.url?.host == "surrit.other.media" },"other version playlist is not fetched")
        check(!chosenRequests.contains { $0.url?.path.hasSuffix(".ts") == true },"selected line still does not fetch segments")
        fails(.drm) { _ = try OnlineManifest.parse(Data("#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"skd://asset\"\n#EXTINF:4,\na.ts".utf8), at:root, root:root) }
        check(!OnlinePolicy.discoveredMedia(URL(string:"https://user:pass@issued.neutral.media/a.m3u8")!, source:.thirdPartyAVDB),"issued URL cannot carry userinfo")
        check(!OnlinePolicy.discoveredMedia(URL(string:"http://issued.neutral.media/a.m3u8")!, source:.javmenu),"issued media must stay HTTPS")
        check(!OnlinePolicy.discoveredMedia(URL(string:"https://10.1.2.3/a.m3u8")!, source:.av01),"issued media cannot be a bare IP")
        for expected in [OnlineFailure.keyUnavailable, OnlineFailure.blocked] {
            let keyProvider = OnlineProvider(transport:OnlineTransport(loader:{ request in
                if request.url!.path == "/hls/neutral/index.m3u8" { return Data("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"key\"\n#EXTINF:4,\na.ts".utf8) }
                if expected == .blocked { throw OnlineFailure.blocked }
                return Data(repeating:0,count:15)
            }))
            do {
                _ = try await keyProvider.validatedPlan(media:issued,referrer:exactJable[0].detailURL!,line:exactJable[0],number:"SNOS-329",pageIssued:true)
                preconditionFailure("unavailable or access-controlled key must not create a plan")
            } catch { check(OnlineFailure.classify(error) == expected,"key failure stops instead of guessing credentials or accepting invalid bytes") }
        }
        let attributedProvider = OnlineProvider(transport: OnlineTransport(loader: { request in
            if request.url!.host == "helvid.com" { throw OnlineFailure.keyUnavailable }
            return try fixture(request)
        }))
        let attributed = OnlinePlaybackModel(provider: attributedProvider)
        attributed.query(.thirdPartyAVDB, number: "DEMO-123", versions: false)
        attributed.query(.javmenu, number: "DEMO-123", versions: false)
        try await settle(attributed)
        check(attributed.state(.javmenu).label.contains("找到候选，待解析"), "discovery is never labelled playable")
        let failedLine = try await attributedProvider.discover(.thirdPartyAVDB, number: "DEMO-123", versions: false)[0]
        let goodLine = try await attributedProvider.discover(.javmenu, number: "DEMO-123", versions: false)[0]
        attributed.choose(failedLine, number: "DEMO-123", versions: false)
        check(attributed.resolutions[.thirdPartyAVDB]?.line.id == failedLine.id && attributed.resolutions[.javmenu] == nil, "resolving belongs only to exact source and line")
        try await settle(attributed)
        check(attributed.resolutions[.thirdPartyAVDB]?.status == .failed(.keyUnavailable) && attributed.plan == nil, "failed key cannot launch player")
        check(attributed.resolutions[.thirdPartyAVDB]!.label.contains("第三方AVDB") && attributed.resolutions[.thirdPartyAVDB]!.label.contains("Full"), "failure visibly identifies provider and line")
        attributed.choose(goodLine, number: "DEMO-123", versions: false); try await settle(attributed)
        check(attributed.plan?.source == .javmenu && attributed.resolutions[.javmenu]?.status == .validated, "valid manifest launches only chosen provider")
        check(attributed.resolutions[.thirdPartyAVDB]?.status == .failed(.keyUnavailable), "other provider error remains correctly attributed")
        check(attributed.resolutions[.javmenu]!.label.contains("尚未确认首帧"), "manifest validation cannot claim playback frame")
        var otherLine = goodLine
        otherLine = OnlineLine(source: .javmenu, recordID: goodLine.recordID, code: goodLine.code, version: goodLine.version, lineKey: "other", routeDigest: "changed")
        attributed.choose(otherLine, number: "DEMO-123", versions: false); try await settle(attributed)
        check(attributed.plan == nil && attributed.resolutions[.javmenu]?.line.id == otherLine.id && attributed.resolutions[.javmenu]?.status == .failed(.noMatch), "changed line clears old plan and binds its own error")
        let lateProvider = OnlineProvider(transport: OnlineTransport(loader: { request in
            if request.url!.host == "javmenu.com" { try? await Task.sleep(nanoseconds: 150_000_000) }
            return try fixture(request)
        }))
        let late = OnlinePlaybackModel(provider: lateProvider)
        late.choose(goodLine, number: "DEMO-123", versions: false)
        late.choose(failedLine, number: "DEMO-123", versions: false); try await settle(late)
        try await Task.sleep(nanoseconds: 200_000_000)
        check(late.plan?.source == .thirdPartyAVDB && late.resolutions[.javmenu]?.status == .failed(.cancelled), "late old-source result never overwrites newly selected plan")
        late.choose(goodLine, number: "DEMO-123", versions: false)
        late.query(.javmenu, number: "NEXT-456", versions: false); try await settle(late)
        try await Task.sleep(nanoseconds: 200_000_000)
        check(late.plan == nil && late.resolutions.isEmpty && late.state(.javmenu) == .failed(.noMatch), "changed film clears old plan and pending resolution")
        late.choose(goodLine, number: "DEMO-123", versions: false); late.reset()
        try await Task.sleep(nanoseconds: 200_000_000)
        check(late.plan == nil && late.states.isEmpty && late.resolutions.isEmpty && late.queryMessages.isEmpty, "account reset defeats late source/line result")
        check(cancelled.queryMessages.isEmpty, "reset clears source-scoped capacity message")
        print("PASS \(assertions) production online playback assertions; six registry, exact DOM/JSON/identity, bounded safe HLS, independent model and credential isolation; build 231 selected-line")
        if ProcessInfo.processInfo.environment["ONLINE_PLAYBACK_LIVE"] == "1" {
            do {
                let real = OnlineProvider(); let routes = try await OnlinePlaybackModel.bounded { try await real.discover(.memojav,number:"START-642",versions:false) }
                guard let line = routes.first else { throw OnlineFailure.noMatch }
                let result = try await OnlinePlaybackModel.bounded { try await real.resolve(line,number:"START-642",versions:false) }
                print("LIVE MemoJav exact discovery + literal public flow + unprotected validated HLS: PASS; host=\(result.url.host ?? ""); no segments; first-frame UNVERIFIED")
            } catch {
                print("LIVE MemoJav: \(OnlineFailure.classify(error).localizedDescription); no bypass; first-frame UNVERIFIED")
            }
        }
    }
}
