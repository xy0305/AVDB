import Foundation
final class Location252:NSObject,URLSessionTaskDelegate,@unchecked Sendable {
 func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {
  print("REDIRECT252",response.statusCode,response.url?.absoluteString ?? "",request.url?.absoluteString ?? "");completionHandler(nil)
 }
}
@main struct LocationProbe252 {
 static func main() async {
  let c=URLSessionConfiguration.ephemeral;c.httpCookieStorage=nil;c.httpShouldSetCookies=false;c.urlCredentialStorage=nil;c.timeoutIntervalForResource=12
  let s=URLSession(configuration:c,delegate:Location252(),delegateQueue:nil)
  for path in ["DSOD-070","DAZD-315","DSOD-010","DSOD-022","pics/actress/zhl_a.jpg"] {
   do { let (bytes,r)=try await s.bytes(from:URL(string:"https://www.javbus.com/"+path)!);print("HTTP252",path,(r as? HTTPURLResponse)?.statusCode ?? 0,r.mimeType ?? "");var n=0;for try await _ in bytes {n+=1;if n>=128 {break}} } catch { print("ERROR252",path,error.localizedDescription) }
  };s.invalidateAndCancel()
 }
}
