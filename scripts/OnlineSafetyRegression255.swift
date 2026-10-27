import Foundation
@MainActor enum OnlineSafetyRegression255 {
 static func run() async throws {
  var count=0
  func check(_ value:Bool,_ reason:String) { count += 1;precondition(value,reason) }
  for ip in ["8.8.8.8","1.1.1.1","2606:4700:4700::1111","::ffff:8.8.8.8","::ffff:808:808","64:ff9b::808:808"] { check(OnlineMediaScope.publicAddress(ip),"public/mapped/NAT64 public rejected") }
  for ip in ["::ffff:127.0.0.1","::ffff:192.168.1.1","::ffff:c612:303","::ffff:198.18.3.3","64:ff9b::a00:1","64:ff9b::c612:303","fd27::1","198.18.3.139","198.19.0.1","10.0.0.1","169.254.169.254","192.0.2.1","2001:db8::1","::1","not-an-address"] { check(!OnlineMediaScope.publicAddress(ip),"private/reserved/malformed address accepted") }
  let root=URL(string:"https://missav.fans/en/search/PRWF-017")!
  try OnlineMediaScope.validateAddresses(["8.8.8.8","::ffff:1.1.1.1"],root:root)
  for addresses in [[],["8.8.8.8","10.0.0.1"],["198.18.3.139"]] {
   do { try OnlineMediaScope.validateAddresses(addresses,root:root);preconditionFailure("DNS must stop before request") }
   catch { let text=OnlineFailure.classify(error).localizedDescription;check(text.contains("DNS") && text.contains("missav.fans"),"missing exact DNS reason") }
  }
  let urls:[(OnlineSource,URL)]=[(.jable,JableAdapter.search("PRWF-017")),(.missav,MissAVAdapter.search("PRWF-017")),(.av123,OneTwoThreeAVAdapter.search("PRWF-017")),(.memojav,MemoJavAdapter.page("PRWF-017")),(.javday,JavDayAdapter.search("PRWF-017"))]
  for (source,url) in urls { check(OnlinePolicy.metadata(url,source:source),"production search URL rejected") }
  for u in ["https://123av.com/en/search?keyword=PRWF-017&x=1","https://123av.com/en/search?keyword=PRWF-017&keyword=FNS-249","https://fs1.app/search/PRWF-017/?q=FNS-249","https://memojav.org/video/PRWF-017?url=https://internal.local","https://javday.app/search/wd/PRWF-017/?x=1","https://javday.app/videos/PRWF017/?token=x"] { let url=URL(string:u)!;check(!OnlineSource.allCases.contains { OnlinePolicy.metadata(url,source:$0) },"unknown/duplicate/search-injection query accepted") }
  var signed=URLComponents(string:"https://video10.memojav.net/stream/neutral.m3u8")!;signed.queryItems=[URLQueryItem(name:"token",value:"NEUTRAL_SIGNED_SECRET")]
  let err=OnlineMediaScope.diagnostic(signed.url!,stage:"清单/DNS",reason:"中性失败")
  let label=OnlinePlaybackModel.State.failed(err).label
  check(label.contains("video10.memojav.net") && label.contains("清单/DNS") && !label.contains("NEUTRAL_SIGNED_SECRET") && !label.contains("neutral.m3u8"),"UI diagnostic leaked URL query/path")
  check(OnlinePolicy.addressRejection(URL(string:"http://missav.fans/en/PRWF-017")!).contains("格式"),"format reason missing")
  check(OnlinePolicy.addressRejection(URL(string:"https://127.0.0.1/x")!).contains("host"),"host reason missing")
  check(OnlinePolicy.addressRejection(URL(string:"https://missav.fans/private?x=1")!).contains("path/query"),"path/query reason missing")
  let model=OnlinePlaybackModel(provider:OnlineProvider(transport:OnlineTransport(loader:{ request in
   throw OnlineMediaScope.diagnostic(request.url!,stage:"查询/DNS",reason:"中性无结果")
  })))
  for source in OnlineSource.allCases {
   model.query(source,number:"PRWF-017",versions:false)
   for _ in 0..<100 { if model.state(source) != .querying { break };try await Task.sleep(nanoseconds:10_000_000) }
   let host=urls.first { $0.0 == source }!.1.host!
   check(model.state(source).label.contains(host),"per-source UI reason lost or crossed")
  }
  check(model.plan == nil,"failed DNS must not launch player")
  print("PASS255",count,"neutral public-DNS/mapped-IPv6/private/empty-DNS/query/stage/UI-isolation assertions")
 }
}
