import Foundation
actor CompatibilityLog256 {
 var urls:[URL]=[]
 func add(_ url:URL) { urls.append(url) }
 func all() -> [URL] { urls }
}
@MainActor enum OnlineCompatibilityRegression256 {
 static func run() async throws {
  var count=0
  func check(_ value:Bool,_ reason:String) { count += 1;precondition(value,reason) }
  func rejects(_ addresses:[String],root:URL,mode:OnlineDNSMode = .systemProxy,approved:Bool = true) {
   do { try OnlineMediaScope.validateAddresses(addresses,root:root,mode:mode,approvedOrigin:approved);preconditionFailure("unsafe DNS accepted") }
   catch { check(true,"rejected") }
  }
  let root=URL(string:"https://video10.memojav.net/stream/neutral/index.m3u8?token=NEUTRAL_SECRET_256")!
  for ip in ["198.18.0.0","198.18.255.255","198.19.0.0","198.19.255.255","::ffff:198.18.3.3","::ffff:c613:ffff","64:ff9b::c612:303"] {
   check(OnlineMediaScope.syntheticAddress(ip),"precise synthetic classification")
   rejects([ip],root:root,mode:.strict)
   try OnlineMediaScope.validateAddresses(["8.8.8.8",ip],root:root,mode:.systemProxy,approvedOrigin:true)
   check(true,"mixed public and synthetic allowed")
   rejects([ip],root:root,approved:false)
  }
  for ip in ["198.17.255.255","198.20.0.0","fd27::1","fd27:1234::1","fc00::1","::ffff:10.0.0.1","64:ff9b::a00:1","64:ff9b:1::c612:303","198.18.1.999","198.18.x.1","198.18.1.1%en0","2002:c612:303::1"] { check(!OnlineMediaScope.syntheticAddress(ip),"synthetic boundary") }
  for addresses in [[],["8.8.8.8","198.18.1.1","10.0.0.1"],["198.18.1.1","127.0.0.1"],["fd27::1"],["169.254.169.254"],["192.168.1.1"],["172.16.0.1"],["224.0.0.1"],["2001:db8::1"],["not-an-ip"],Array(repeating:"198.18.1.1",count:33)] { rejects(addresses,root:root) }
  rejects(["198.18.1.1"],root:URL(string:"https://198.18.1.1/a")!)
  let queries=OnlineSource.allCases.map { s -> URL in
   switch s {case .jable:return JableAdapter.search("DEMO-123");case .missav:return MissAVAdapter.search("DEMO-123");case .av123:return OneTwoThreeAVAdapter.search("DEMO-123");case .memojav:return MemoJavAdapter.page("DEMO-123")}
  }
  let log=CompatibilityLog256()
  let transport=OnlineTransport(resolver:{ _ in ["198.18.3.139"] },loader:{ r in await log.add(r.url!);return try OnlineRegression254.response(r) })
  for url in queries {
   do { _=try await transport.fetch(url,cap:2*1024*1024);preconditionFailure("strict request escaped") } catch { check(true,"strict rejects") }
  }
  check(await log.all().isEmpty,"strict must reject before request")
  let compat=OnlineProvider(transport:transport.withDNSMode(.systemProxy))
  for source in OnlineSource.allCases {
   let lines=try await compat.discover(source,number:"DEMO-123",versions:false)
   check(lines.count==1,"compat discover")
   let plan=try await compat.resolve(lines[0],number:"DEMO-123",versions:false)
   check(plan.source==source && plan.headers["Cookie"]==nil,"compat prepare same source")
  }
  let urls=await log.all()
  for host in ["jable.tv","missav.ws","123av.com","memojav.org","sadie-shop.site","video10.memojav.net","jzxz.freeboldspirit.site","neutral.jable-cdn.net","surrit.neutral.media"] { check(urls.contains { $0.host==host },"mode propagated through approved source "+host) }
  check(urls.contains { $0.path.hasSuffix("leaf.m3u8") },"child manifest preflight")
  check(urls.allSatisfy { $0.scheme=="https" && $0.host != "198.18.3.139" && !$0.path.hasSuffix(".ts") },"original HTTPS hostname; no segment fetch")
  let keyLog=CompatibilityLog256()
  let keys=OnlineProvider(transport:OnlineTransport(dnsMode:.systemProxy,resolver:{ _ in ["::ffff:c612:303"] },loader:{ r in
   await keyLog.add(r.url!)
   if r.url!.path.hasSuffix(".key") { return Data(repeating:0,count:16) }
   return Data("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"neutral.key\"\n#EXTINF:4,\nneutral.ts\n#EXT-X-ENDLIST\n".utf8)
  }))
  let memo=(try await compat.discover(.memojav,number:"DEMO-123",versions:false))[0]
  _=try await keys.validatedPlan(media:root,referrer:MemoJavAdapter.page("DEMO-123"),line:memo,number:"DEMO-123")
  check(await keyLog.all().contains { $0.path.hasSuffix(".key") },"key DNS gets mode")
  for raw in ["https://198.18.3.139/x","https://127.0.0.1/x","https://localhost/x","https://unapproved.net/x","https://missav.ws/private?token=NEUTRAL_SECRET_256","https://123av.com/en/search?keyword=DEMO-123&extra=1"] {
   let before=await log.all().count
   do { _=try await compat.transport.fetch(URL(string:raw)!,cap:1024);preconditionFailure("unsafe URL accepted") } catch { check(true,"URL still rejected") }
   check(await log.all().count==before,"unsafe URL never reaches loader")
  }
  let mixed=OnlineTransport(dnsMode:.systemProxy,resolver:{ _ in ["198.18.1.1","192.168.1.1"] },loader:{ _ in preconditionFailure("mixed unsafe request escaped") })
  do { _=try await mixed.fetch(root,cap:1024);preconditionFailure("mixed unsafe accepted") } catch { let label=OnlineFailure.classify(error).localizedDescription;check(!label.contains("NEUTRAL_SECRET_256") && !label.contains("index.m3u8"),"sensitive query/path redacted") }
  let suite="online256.neutral."+UUID().uuidString
  let prefs=UserDefaults(suiteName:suite)!
  defer { prefs.removePersistentDomain(forName:suite) }
  let model=OnlinePlaybackModel(provider:OnlineProvider(transport:transport),preferences:prefs)
  check(!model.systemProxyCompatibility,"new install strict by default")
  model.query(.jable,number:"DEMO-123",versions:false);try await OnlineRegression254.settle(model)
  check(model.state(.jable).label.contains("DNS"),"strict model presents DNS error")
  model.setSystemProxyCompatibility(true)
  check(model.states.isEmpty && model.plan==nil,"mode resets prior strict failure")
  model.query(.jable,number:"DEMO-123",versions:false);try await OnlineRegression254.settle(model)
  guard case .found(let found)=model.state(.jable) else { preconditionFailure("toggle not wired to real transport") }
  check(found.count==1,"compat model query")
  let cachedCount=await log.all().count
  model.query(.jable,number:"DEMO-123",versions:false);try await OnlineRegression254.settle(model)
  check(await log.all().count==cachedCount,"same mode metadata cache used")
  model.setSystemProxyCompatibility(false)
  model.query(.jable,number:"DEMO-123",versions:false);try await OnlineRegression254.settle(model)
  check(model.state(.jable).label.contains("DNS"),"strict cannot reuse compat cache")
  model.setSystemProxyCompatibility(true)
  model.query(.jable,number:"DEMO-123",versions:false);try await OnlineRegression254.settle(model)
  check(await log.all().count>cachedCount,"returning compat requires fresh metadata")
  let restored=OnlinePlaybackModel(provider:OnlineProvider(transport:transport),preferences:prefs)
  check(restored.systemProxyCompatibility,"local bool preference restored")
  check(prefs.dictionaryRepresentation()[OnlinePlaybackModel.proxyPreferenceKey] as? Bool == true,"stores only preference bool")
  let slow=OnlinePlaybackModel(provider:OnlineProvider(transport:OnlineTransport(resolver:{ _ in ["198.18.1.1"] },loader:{ r in
   try? await Task.sleep(nanoseconds:150_000_000)
   return try OnlineRegression254.response(r)
  })),preferences:prefs)
  slow.query(.jable,number:"DEMO-123",versions:false)
  try await Task.sleep(nanoseconds:30_000_000);slow.setSystemProxyCompatibility(false)
  try await Task.sleep(nanoseconds:250_000_000)
  check(slow.states.isEmpty && slow.plan==nil,"mode switch cancels queries and stale generation")
  slow.setSystemProxyCompatibility(true)
  slow.choose(found[0],number:"DEMO-123",versions:false)
  try await Task.sleep(nanoseconds:30_000_000);slow.setSystemProxyCompatibility(false)
  try await Task.sleep(nanoseconds:250_000_000)
  check(slow.plan==nil && slow.resolving==nil && slow.resolutions.isEmpty,"mode switch cancels playback preparation")
  print("PASS256",count,"production injected DNS / four-source propagation / keys / boundary / redaction / mode preference / cache isolation / cancellation assertions; no real private network request")
 }
}
