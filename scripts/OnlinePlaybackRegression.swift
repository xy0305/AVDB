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
        check(!OnlinePolicy.bound(URL(string:"https://2608.xbv2608.com/other/a.ts")!,to:root),"path bound")
        let leaf = Data("#EXTM3U\n#EXTINF:4,\na.ts\n#EXT-X-ENDLIST\n".utf8)
        check(try OnlineManifest.parse(leaf,at:root,root:root).variants.isEmpty,"leaf manifest")
        let master = Data("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nchild.m3u8\n".utf8)
        check(try OnlineManifest.parse(master,at:root,root:root).variants.count == 1,"master variant")
        for key in ["#EXT-X-KEY:METHOD=AES-128,URI=\"key\"", "#EXT-X-SESSION-KEY:METHOD=AES-128,URI=\"key\""] {
            fails(.blocked) { _ = try OnlineManifest.parse(Data(("#EXTM3U\n"+key+"\n#EXTINF:4,\na.ts").utf8),at:root,root:root) }
        }
        fails(.parse) { _ = try OnlineManifest.parse(Data("<html>#EXTM3U</html>".utf8),at:root,root:root) }
        fails(.unsafe) { _ = try OnlineManifest.parse(Data("#EXTM3U\n#EXTINF:4,\nhttps://127.0.0.1/a.ts".utf8),at:root,root:root) }
        fails(.unsafe) { _ = try OnlineManifest.parse(Data("#EXTM3U\n#EXTINF:4,\n../a.ts".utf8),at:root,root:root) }
        let page = try fixture(URLRequest(url:OnlineProvider.page("DEMO-123")))
        check(try OnlineProvider.javmenu(page,number:"DEMO-123").count == 1,"real DOM selector")
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
        let av = Data("{\"videos\":[{\"id\":42439,\"dvd_id\":\"SSIS-001\"},{\"id\":1,\"dvd_id\":\"SSIS-0010\"}]}".utf8)
        check(try OnlineAdditional.av01Records(av,number:"SSIS-001").count == 1,"AV01 real id exact matching")
        let proof = OnlineAdditional.memoProof(milliseconds:1792686900000)
        check(proof.count == 2 && proof[0].name == "sig" && proof[1].name == "sts","normal public timestamp proof")
        check(try OnlineAdditional.memoMedia(Data("{\"success\":true,\"type\":\"hls\",\"url\":\"https%3A%2F%2Fvideo10.memojav.net%2Fstream%2FDEMO-123%2Fmaster.m3u8\"}".utf8)).host == "video10.memojav.net","normal once-encoded URL")
        print("PASS \(assertions) production online playback assertions; six registry, exact DOM/JSON/identity, bounded safe HLS, independent model and credential isolation")
        if ProcessInfo.processInfo.environment["ONLINE_PLAYBACK_LIVE"] == "1" {
            do {
                let real = OnlineProvider(); let routes = try await OnlinePlaybackModel.bounded { try await real.discover(.memojav,number:"START-642",versions:false) }
                guard let line = routes.first else { throw OnlineFailure.noMatch }
                let result = try await OnlinePlaybackModel.bounded { try await real.resolve(line,number:"START-642",versions:false) }
                print("LIVE MemoJav exact discovery + literal public flow + unprotected validated HLS: PASS; host=\(result.url.host ?? ""); no segments; first-frame UNVERIFIED")
            } catch { print("LIVE MemoJav: \(OnlineFailure.classify(error).localizedDescription); no bypass; first-frame UNVERIFIED") }
        }
    }
}
