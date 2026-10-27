import Foundation
actor OnlineLog254 {
    var requests:[URLRequest]=[]
    func add(_ r:URLRequest) { requests.append(r) }
    func all() -> [URLRequest] { requests }
}
@main struct OnlineRegression254 {
    static var count=0
    static func check(_ value:Bool,_ message:String) { count += 1; precondition(value,message) }
    static func fails(_ failure:OnlineFailure,_ work:() throws -> Void) {
        do { try work(); preconditionFailure("expected \(failure)") } catch { check(OnlineFailure.classify(error)==failure,"wrong failure \(error)") }
    }
    static let root=URL(string:"https://jzxz.freeboldspirit.site/oo5/neutral/video.m3u8")!
    static let packed = #"eval(function(p,a,c,k,e,d){/* inert, never execute */return p}('f=\'8://7.6/5-4-3-2-1/e.0\';d=\'8://7.6/5-4-3-2-1/c/9.0\';b=\'8://7.6/5-4-3-2-1/a/9.0\';',16,16,'m3u8|1769e38e302b|919c|4986|fcd3|57b8359e|neutral.media|surrit|https|video|1080p|source1280|720p|source842|playlist|source'.split('|'),0,{}))"#
    static func playerHTML(_ code:String="DEMO-123",host:String="sadie-shop.site") throws -> Data {
        let rows:[[String:Any]]=[["number":1,"url":"https://"+host+"/e/Neutral1"]]
        let json=String(data:try JSONSerialization.data(withJSONObject:rows),encoding:.utf8)!
        let encoded=String(data:try JSONSerialization.data(withJSONObject:json,options:.fragmentsAllowed),encoding:.utf8)!.dropFirst().dropLast()
        let config="player(JSON.parse('"+encoded+"'), 123, '"+code.lowercased()+"', '', '')"
        let escaped=config.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"\"",with:"&quot;")
        return Data(("<h1>"+code+" Neutral</h1><div x-data=\""+escaped+"\"></div>").utf8)
    }
    static func response(_ r:URLRequest) throws -> Data {
        let u=r.url!,h=u.host!
        if h=="jable.tv" {
            if u.path.hasPrefix("/search/") { return Data("<a href='/videos/demo-1230/'>wrong</a><a href='/videos/demo-123/'>neutral</a>".utf8) }
            return Data("<meta property='og:url' content='https://jable.tv/videos/demo-123/'><section class='video-info'><h4>DEMO-123 Neutral</h4></section><script>var hlsUrl='https://neutral.jable-cdn.net/demo/index.m3u8';</script>".utf8)
        }
        if h=="missav.fans" {
            if u.path.contains("/search/") { return Data("<a href='https://missav.ws/en/demo-123'>wrong mirror</a><a href='https://missav.media/en/demo-123'>wrong mirror</a><a href='/en/demo-123'>neutral</a>".utf8) }
            return Data(("<link rel='canonical' href='https://missav.fans/en/demo-123'><h1>DEMO-123 Neutral</h1><script>"+packed+"</script>").utf8)
        }
        if h=="123av.com" {
            if u.path=="/en/search" { return Data("<a href='/en/v/demo-1230'>wrong</a><a href='/en/v/demo-123'>neutral</a><a href='/en/v/demo-123-uncensored-leaked'>different edition</a>".utf8) }
            return try playerHTML()
        }
        if h=="sadie-shop.site" {
            if u.path=="/stream" { return Data(("{\"status\":\"ok\",\"media\":{\"stream\":\""+root.absoluteString+"\"}}").utf8) }
            return Data("<html><div id='player'></div></html>".utf8)
        }
        if h=="memojav.org" {
            if u.path.hasPrefix("/video/") { return Data("<link rel='canonical' href='https://memojav.org/video/DEMO-123'><h1>DEMO-123 Neutral</h1><iframe src='/embed/DEMO-123'></iframe>".utf8) }
            if u.path.hasPrefix("/embed/") { return Data("<script>var config={id:'DEMO-123'};</script>".utf8) }
            return Data("{\"success\":true,\"type\":\"hls\",\"url\":\"https://video10.memojav.net/stream/neutral/index.m3u8\"}".utf8)
        }
        if h=="javday.app" {
            if u.path.contains("/search/") {
                return Data("<a class='videoBox' href='/videos/DEMO123/'><div class='videoBox-info'><div class='title'>DEMO-123 Neutral</div></div></a><a class='videoBox' href='/videos/WRONG999/'><div class='videoBox-info'><div class='title'>WRONG-999</div></div></a>".utf8)
            }
            return Data("<meta property='og:url' content='https://javday.app/videos/DEMO123/'><meta property='og:title' content='DEMO-123 Neutral'><h1>DEMO-123 Neutral</h1><video id='J_prismPlayer'><source src='https://javday.homes/videos/neutral/index.m3u8' type='application/x-mpegURL'/></video><script>url: 'https://javday.homes/videos/neutral/index.m3u8'</script>".utf8)
        }
        if h=="javday.homes" || h.hasSuffix(".javday.homes") {
            if u.path.hasSuffix("leaf.m3u8") { return Data("#EXTM3U\n#EXTINF:4,\nhttps://edge.javday.homes/videos/neutral/seg.ts\n#EXT-X-ENDLIST\n".utf8) }
            return Data("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nleaf.m3u8\n".utf8)
        }
        if u.path.hasSuffix("leaf.m3u8") { return Data("#EXTM3U\n#EXTINF:4,\n../neutral.ts\n#EXT-X-ENDLIST\n".utf8) }
        if u.path.hasSuffix(".m3u8") { return Data("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\n720/leaf.m3u8\n".utf8) }
        throw OnlineFailure.unsafe
    }
    @MainActor static func settle(_ m:OnlinePlaybackModel) async throws {
        for _ in 0..<100 { if m.resolving==nil && !m.states.values.contains(.querying) { return };try await Task.sleep(nanoseconds:20_000_000) }
        preconditionFailure("model did not settle")
    }
    @MainActor static func main() async throws {
        check(OnlineSource.allCases.count==5,"exactly five sources")
        check(OnlineIdentity.key("ssis_001")=="SSIS-001","full digits preserved")
        for bad in ["DEMO-1230","XDEMO-123","DEMO-0123","DEMO-123-LEAK","../DEMO-123"] { check(OnlineIdentity.version(bad,number:"DEMO-123",allowVersions:false)==nil,"wrong number") }
        check(OnlineIdentity.version("DEMO-123-UNCENSORED-LEAK",number:"DEMO-123",allowVersions:true) != nil,"explicit edition")
        for a in ["127.0.0.1","10.0.0.1","192.168.1.1","198.18.8.8","198.19.0.1","fd27:712::1","::1","169.254.169.254","2001:db8::1"] { check(!OnlineMediaScope.publicAddress(a),"private/FakeIP forbidden") }
        check(OnlineMediaScope.publicAddress("8.8.8.8"),"public address")
        for u in ["http://jable.tv/videos/demo-123/","https://jable.tv.evil.net/videos/demo-123/","https://u:p@jable.tv/videos/demo-123/","https://127.0.0.1/video/DEMO-123","https://jable.tv:444/videos/demo-123/"] { check(!OnlinePolicy.metadata(URL(string:u)!,source:.jable),"unsafe metadata") }
        check(!OnlinePolicy.embed(URL(string:"https://unknown.site/e/Neutral1")!),"unknown embed does not widen hosts")
        // Stream-issued /oo5/ hosts rotate; accept shape via discoveredMedia, not a fixed allowlist.
        for host in ["jzxz.freeboldspirit.site","85kq.cleartruevision.site","8vpr.deeptrueforce.site","jmv1.grayson-store.site"] {
            let issued=URL(string:"https://"+host+"/oo5/neutral/video.m3u8")!
            check(OnlinePolicy.discoveredMedia(issued,source:.av123),"stream-issued /oo5/ accepted for "+host)
            check(!OnlinePolicy.media(issued,source:.av123),"unscoped media allowlist stays closed for rotating "+host)
        }
        check(!OnlinePolicy.discoveredMedia(URL(string:"https://85kq.cleartruevision.site/other/video.m3u8")!,source:.av123),"non-/oo5/ path rejected")
        check(!OnlinePolicy.discoveredMedia(URL(string:"http://85kq.cleartruevision.site/oo5/video.m3u8")!,source:.av123),"non-HTTPS rejected")
        fails(.incomplete) { _=try OneTwoThreeAVAdapter.embeds(playerHTML(host:"unknown.site"),page:URL(string:"https://123av.com/en/v/demo-123")!,number:"DEMO-123") }
        fails(.incomplete) { _=try OneTwoThreeAVAdapter.stream(Data("{\"status\":\"ok\",\"media\":{\"stream\":\"https://evil.example/other/x.m3u8\"}}".utf8)) }
        let rotated=try OneTwoThreeAVAdapter.stream(Data("{\"status\":\"ok\",\"media\":{\"stream\":\"https://85kq.cleartruevision.site/oo5/neutral/video.m3u8\"}}".utf8))
        check(rotated.host=="85kq.cleartruevision.site" && rotated.path.hasPrefix("/oo5/"),"rotating CDN host from stream JSON")
        fails(.noMatch) { _=try OneTwoThreeAVAdapter.embeds(playerHTML("DEMO-1230"),page:URL(string:"https://123av.com/en/v/demo-123")!,number:"DEMO-123") }
        fails(.blocked) { try OnlineAdapters.rejectChallenge("<title>Just a moment...</title><div id='challenge-form'></div>") }
        let unrelated = #"eval(function(p,a,c,k,e,d){return p}('ad',62,9999,'advert|library'.split('|'),0,{}))"#
        check(try OnlineAdditional.missavMedia("<script>"+unrelated+"</script><script>"+packed+"</script>").host == "surrit.neutral.media","unrelated packer not a source container")
        let decoded=try OnlineAdditional.missavMedia("<script>"+packed+"</script>")
        check(decoded.host=="surrit.neutral.media","word table decoded without executing")
        fails(.unsupported) { _=try OnlineAdditional.missavMedia("<script>"+packed+packed+"</script>") }
        fails(.tooLarge) { _=try OnlineAdditional.missavMedia("<script>"+packed.replacingOccurrences(of:",16,16,",with:",16,99999,")+"</script>") }
        fails(.unsafe) { _=try OnlineManifest.parse(Data("#EXTM3U\n#EXTINF:4,\nhttps://127.0.0.1/x.ts".utf8),at:root,root:root) }
        fails(.drm) { _=try OnlineManifest.parse(Data("#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"key\"\n#EXTINF:4,\na.ts".utf8),at:root,root:root) }
        check(try OnlineManifest.parse(Data("#EXTM3U\n#EXTINF:4,\n../a.ts\n".utf8),at:root,root:root).variants.isEmpty,"relative same-origin segments")
        let log=OnlineLog254();let provider=OnlineProvider(transport:OnlineTransport(loader:{ r in await log.add(r);return try response(r) }))
        for s in OnlineSource.allCases {
            let lines=try await provider.discover(s,number:"DEMO-123",versions:false);check(lines.count==1,"exact source match \(s)")
            let plan=try await provider.resolve(lines[0],number:"DEMO-123",versions:false)
            check(plan.source==s && plan.number=="DEMO-123","no source switch")
            check(plan.headers["Referer"] != nil && plan.headers["User-Agent"]==OnlinePolicy.ua,"native headers")
            check(plan.headers["Cookie"]==nil && plan.headers["Authorization"]==nil,"no account leakage")
        }
        let requests=await log.all()
        check(requests.allSatisfy { $0.value(forHTTPHeaderField:"Cookie")==nil && $0.value(forHTTPHeaderField:"Authorization")==nil },"requests anonymous")
        check(requests.allSatisfy { !$0.url!.path.hasSuffix(".ts") },"no segment download")
        let isolated=OnlinePlaybackModel(provider:OnlineProvider(transport:OnlineTransport(loader:{ r in if r.url?.host=="jable.tv" { throw OnlineFailure.blocked };return try response(r) })))
        isolated.query(.jable,number:"DEMO-123",versions:false);isolated.query(.av123,number:"DEMO-123",versions:false);try await settle(isolated)
        check(isolated.states[.jable] == .failed(.blocked),"source failure isolated")
        if case .found(let lines)=isolated.states[.av123] { check(lines.count==1,"other source survives") } else { preconditionFailure("other source lost") }
        let slow=OnlinePlaybackModel(provider:OnlineProvider(transport:OnlineTransport(loader:{ r in try await Task.sleep(nanoseconds:200_000_000);return try response(r) })))
        slow.query(.av123,number:"DEMO-123",versions:false);slow.query(.av123,number:"DEMO-123",versions:false);slow.cancel(.av123)
        try await Task.sleep(nanoseconds:300_000_000);check(slow.states[.av123] == .idle && slow.plan==nil,"cancel prevents late result")
        slow.query(.av123,number:"DEMO-123",versions:false);slow.reset();try await Task.sleep(nanoseconds:300_000_000);check(slow.states.isEmpty,"reset prevents late account result")
        print("PASS \(count) production five-adapter assertions; neutral HTML/HLS only; no adult media or first-frame claim")
        try await OnlineSafetyRegression255.run()
        if ProcessInfo.processInfo.environment["ONLINE254_LIVE"]=="1" {
            for s in OnlineSource.allCases {
                let code:String; switch s { case .memojav: code="START-642"; case .javday: code="ABF-378"; default: code="FNS-249" };let real=OnlineProvider();var stage="exact-search"
                do {
                    let rows=try await OnlinePlaybackModel.bounded { try await real.discover(s,number:code,versions:false) }
                    print("LIVE254 source=\(s.rawValue) number=\(code) search-candidates=\(rows.count)")
                    guard let line=rows.first else { throw OnlineFailure.noMatch }
                    stage="static-detail-and-media-parse"
                    let parsed=try await OnlinePlaybackModel.bounded { try await real.resolveMedia(line,number:code,versions:false) }
                    print("LIVE254 source=\(s.rawValue) static-parse=PASS host=\(parsed.media.host ?? "")")
                    stage="all-manifests-and-public-DNS"
                    let plan=try await OnlinePlaybackModel.bounded { try await real.validatedPlan(media:parsed.media,referrer:parsed.referrer,line:line,number:code,pageIssued:true) }
                    print("LIVE254 source=\(s.rawValue) manifest-validation=PASS host=\(plan.url.host ?? "") FIRST-FRAME=UNVERIFIED")
                } catch {
                    print("LIVE254 source=\(s.rawValue) stage=\(stage) result=\(OnlineFailure.classify(error)) FIRST-FRAME=UNVERIFIED")
                    if s == .missav && OnlineFailure.classify(error) == .tooLarge {
                        do {
                            let page=URL(string:"https://missav.fans/en/fns-249")!
                            let data=try await real.transport.fetch(page,cap:2*1024*1024)
                            let text=try OnlineAdditional.html(data)
                            print("DIAG254 missav public-detail-bytes=\(data.count)")
                            for m in JRHTML.matches(#"return\s+p\}\('((?:\\.|[^'\\])*)',(\d+),(\d+),'([^'\\]*)'\.split\('\|'\),0,\{\}\)\)"#,text) {
                                print("DIAG254 missav radix=\(m[2]) count=\(m[3]) payload-length=\(m[1].count) table-length=\(m[4].count) has-source=\(m[4].components(separatedBy:"|").contains("source"))")
                            }
                        } catch { print("DIAG254 missav bounded-detail=\(OnlineFailure.classify(error))") }
                    }
                }
            }
        }
    }
}
