import Foundation
import Darwin
@main struct Probe255 {
 static func main() async {
  print("PLATFORM", ProcessInfo.processInfo.operatingSystemVersionString)
  for host in ["jable.tv","missav.ws","123av.com","memojav.org"] {
   var result:UnsafeMutablePointer<addrinfo>?
   let rc=getaddrinfo(host,nil,nil,&result)
   var records:[String]=[];var cur=result
   while let item=cur {
    var buf=[CChar](repeating:0,count:Int(NI_MAXHOST));let a=item.pointee
    if let addr=a.ai_addr { let r=getnameinfo(addr,a.ai_addrlen,&buf,socklen_t(NI_MAXHOST),nil,0,NI_NUMERICHOST);let ip=String(cString:buf);records.append("family=\(a.ai_family),numericStatus=\(r),public=\(OnlineMediaScope.publicAddress(ip)),address=\(ip)") }
    cur=a.ai_next
   }
   if let result { freeaddrinfo(result) }
   print("DNS",host,"rc",rc,records)
  }
  let provider=OnlineProvider()
  for (source,number) in [(OnlineSource.jable,"PRWF-017"),(.missav,"PRWF-017"),(.av123,"PRWF-017"),(.memojav,"PRWF-017"),(.missav,"FNS-249"),(.av123,"FNS-249"),(.memojav,"START-642")] {
   do { let lines=try await provider.discover(source,number:number,versions:false);print("DISCOVER",source.rawValue,number,"count",lines.count) }
   catch { print("DISCOVER",source.rawValue,number,"failure",OnlineFailure.classify(error).localizedDescription) }
  }
  print("FIRST_FRAME not_tested; manifest not_requested in discover probe")
 }
}
