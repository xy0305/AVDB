import Foundation

// Executes production Swift, injected resolvers/loaders only. No real private-network IO.
enum TangxinNetworkRegression263 {
    actor Calls {
        var paths: [String] = []
        func add(_ path: String) { paths.append(path) }
        func all() -> [String] { paths }
    }
    static func run() async throws {
        let root = TangxinPolicy.featured
        let raw = OnlineMediaScope.diagnostic(root,stage:"详情/嵌入/API/DNS",reason:"解析无结果（getaddrinfo=8）")
        let original = raw.presentation(at:.discovery)
        precondition(original.category == .dns && original.systemCode == 8 && original.detail == .dnsLookup)
        let bridged = raw as NSError
        let copied = NSError(domain:bridged.domain,code:bridged.code,userInfo:bridged.userInfo)
        precondition(OnlineFailure.classify(copied).presentation(at:.discovery) == original)
        precondition(!raw.localizedDescription.contains("原因未确定"))
        let oldKeyStage = OnlineMediaScope.diagnostic(root,stage:"密钥/DNS",reason:"解析无结果（空地址集）").presentation(at:.unknown)
        precondition(oldKeyStage.stage == .key && oldKeyStage.category == .dns && oldKeyStage.detail == .dnsEmpty)
        precondition(PlaybackDiagnostic(stage:.dns,category:.unsafe,host:"192.168.0.1").host == nil)
        precondition(PlaybackDiagnostic(stage:.dns,category:.unsafe,host:"fd27::1").host == nil)
        func rejection(_ addresses:[String],mode:OnlineDNSMode = .strict,approved:Bool = true) -> PlaybackDiagnostic {
            do { try OnlineMediaScope.validateAddresses(addresses,root:root,mode:mode,approvedOrigin:approved); fatalError("unsafe addresses accepted") }
            catch { return OnlineFailure.classify(error).presentation(at:.discovery) }
        }
        precondition(rejection(["198.18.0.1"]).detail == .dnsSynthetic)
        precondition(rejection(["198.19.255.254"],mode:.systemProxy,approved:false).category == .unsafe)
        try OnlineMediaScope.validateAddresses(["198.18.0.1"],root:root,mode:.systemProxy,approvedOrigin:true)
        for address in ["10.0.0.1","127.0.0.1","192.168.0.1","fd27::1","fc00::1","::ffff:10.0.0.1","64:ff9b::a00:1"] {
            precondition(rejection([address],mode:.systemProxy).detail == .dnsPrivate)
        }
        precondition(rejection(["198.18.0.1","10.0.0.1"],mode:.systemProxy).detail == .dnsPrivate)
        let empty = rejection([])
        precondition(empty.category == .dns && empty.detail == .dnsEmpty && empty.addressSummary == "public=0 synthetic=0 private=0 empty=1")
        for (code,category) in [(-1003,PlaybackDiagnostic.Category.dns),(-1006,.dns),(-1202,.tls),(-1004,.connection),(-999,.cancelled)] {
            let diagnostic = PlaybackDiagnostic.system(NSError(domain:NSURLErrorDomain,code:code,userInfo:[NSLocalizedDescriptionKey:"SECRET_URL?token=SECRET"]),stage:.document,url:root)
            precondition(diagnostic.category == category && diagnostic.systemCode == code && diagnostic.errorDomain == NSURLErrorDomain)
            precondition(!diagnostic.display.contains("SECRET"))
        }
        precondition(PlaybackDiagnostic.system(NSError(domain:"OtherDomain",code:-1202),stage:.dns).category == .unknown)
        let gai = TangxinClient(transport:OnlineTransport(resolver:{ _ in throw NSError(domain:"getaddrinfo",code:8) },loader:{ _ in fatalError("DNS must precede loading") }))
        do { _ = try await gai.list(root); fatalError("lookup failure expected") }
        catch { let d = OnlineFailure.classify(error).presentation(at:.discovery); precondition(d.category == .dns && d.stage == .discovery && d.systemCode == 8 && d.errorDomain == "getaddrinfo") }
        let strict = TangxinClient(transport:OnlineTransport(resolver:{ _ in ["198.18.0.1"] },loader:{ _ in fatalError("strict DNS must stop before loader") }))
        do { _ = try await strict.list(root); fatalError("strict rejected expected") }
        catch { let d = OnlineFailure.classify(error).presentation(at:.discovery); precondition(d.detail == .dnsSynthetic && d.stage == .discovery && d.dnsContext) }
        let log = Calls()
        let client = TangxinClient(transport:OnlineTransport(resolver:{ _ in ["198.18.0.1"] },loader:{ r in
            await log.add(r.url!.path)
            if r.url!.path.hasSuffix(".m3u8") { return Data(TangxinFixtures261.playlist.utf8) }
            if r.url!.path.hasSuffix("key.bin") { return Data(repeating:0,count:16) }
            if r.url!.path.hasSuffix(".jpg") { return Data([0]) }
            if r.url!.path.hasPrefix("/v/") { return Data(TangxinFixtures261.detail.utf8) }
            return Data(TangxinFixtures261.first.utf8)
        })).withDNSMode(.systemProxy)
        precondition(client.transport.dnsMode == .systemProxy)
        let page = try await client.list(root)
        let detail = try await client.detail(page.videos[0].url)
        _ = try await client.image(page.videos[0].poster!)
        _ = try await client.playback(detail)
        let paths = await log.all()
        precondition(paths.contains { $0.hasSuffix(".m3u8") } && paths.contains { $0.hasSuffix("key.bin") } && paths.contains { $0.hasSuffix(".jpg") } && paths.contains { $0.hasPrefix("/v/") })
        // Build 274: site 307s `/featured/2` → `/featured/2/`. Canonicalize before GET; never follow Location.
        precondition(TangxinPolicy.featured.path.hasSuffix("/"))
        let barePage = URL(string: "https://tangxinvlog.app/featured/2")!
        let bareVideo = URL(string: "https://tangxinvlog.app/v/neutral1")!
        precondition(TangxinPolicy.documentURL(barePage)?.path == "/featured/2/")
        precondition(TangxinPolicy.documentURL(bareVideo)?.path == "/v/neutral1/")
        precondition(TangxinPolicy.documentURL(TangxinPolicy.featured)?.path == "/featured/")
        precondition(TangxinPolicy.documentURL(URL(string: "https://elsewhere.org/featured/2")!) == nil)
        precondition(TangxinPolicy.documentURL(URL(string: "https://tangxinvlog.app/featured/2?x=1")!) == nil)
        let slashLog = Calls()
        let slashClient = TangxinClient(transport:OnlineTransport(resolver:{ _ in ["198.18.0.1"] },loader:{ r in
            await slashLog.add(r.url!.path)
            precondition(r.url!.path.hasSuffix("/"), "client must GET directory form, not bare path that 307s")
            if r.url!.path.hasPrefix("/v/") { return Data(TangxinFixtures261.detail.utf8) }
            if r.url!.path == "/featured/2/" { return Data(TangxinFixtures261.second.utf8) }
            return Data(TangxinFixtures261.first.utf8)
        })).withDNSMode(.systemProxy)
        let page2 = try await slashClient.list(barePage)
        precondition(page2.videos.count == 1)
        _ = try await slashClient.detail(bareVideo)
        let slashPaths = await slashLog.all()
        precondition(slashPaths.contains("/featured/2/") && slashPaths.contains("/v/neutral1/"))
        precondition(!slashPaths.contains("/featured/2") && !slashPaths.contains("/v/neutral1"))
        // HLS parser validates each segment/key URL, not just root playlist.
        for child in ["https://other.example.org/segment.ts","https://127.0.0.1/segment.ts","http://t.5gcdn.xyz/segment.ts"] {
            let text = "#EXTM3U\n#EXT-X-TARGETDURATION:5\n#EXTINF:5,\n" + child + "\n#EXT-X-ENDLIST\n"
            do { _ = try OnlineManifest.parse(Data(text.utf8),at:detail.stream,root:detail.stream); fatalError("unsafe child accepted") } catch {}
        }
        for code in [-1202,-999] {
            let errorClient = TangxinClient(transport:OnlineTransport(loader:{ _ in throw NSError(domain:NSURLErrorDomain,code:code) }))
            do { _ = try await errorClient.list(root); fatalError("error expected") }
            catch { let d = OnlineFailure.classify(error).presentation(at:.discovery); precondition(d.category == (code == -999 ? .cancelled : .tls) && d.systemCode == code && d.stage == .discovery) }
        }
        print("PASS263+274 production diagnostic legacy/typed/NSError roundtrip, DNS strict/approved-proxy/private/empty/getaddrinfo/TLS/cancel, client list/image/detail/HLS/key propagation, trailing-slash documentURL (no Location follow); native player segment IO NOT covered")
    }
}
