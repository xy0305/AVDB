import Foundation
import ImageIO
import CryptoKit

private final class Metrics: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let lock = NSLock()
    var protocols: [String] = []
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Default system trust evaluation only; never supply credentials.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust { completionHandler(.performDefaultHandling, nil) }
        else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock(); defer { lock.unlock() }; protocols = metrics.transactionMetrics.compactMap { $0.networkProtocolName }
    }
    func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return protocols }
}

enum NativeProbe {
    static let page = URL(string: "https://www.javbus.com/DSOD-070")!
    static let ua = "Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    static func cleanLocation(_ value: String) -> String {
        guard var c = URLComponents(string: value) else { return "[unparseable]" }
        c.user = nil; c.password = nil; c.fragment = nil
        if c.query != nil { c.query = "redacted" }; return c.string ?? "[redacted]"
    }
    static func fetch(_ url: URL, headers: [String:String], label: String, image: Bool) async -> (Data?, [String:Any]) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 10
        let metrics = Metrics()
        let session = URLSession(configuration: config, delegate: metrics, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.httpShouldHandleCookies = false
        for (key,value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let start = Date()
        var row: [String:Any] = ["label":label,"url":url.absoluteString,"explicitHeaders":headers,"startedAt":ISO8601DateFormatter().string(from:start),"defaultWireHeaders":"unknown; URLRequest properties are not a wire capture"]
        do {
            let (bytes,response) = try await session.bytes(for: request)
            guard let h = response as? HTTPURLResponse else { throw NSError(domain:"Probe", code:1) }
            row["status"] = h.statusCode; row["contentType"] = h.mimeType ?? ""
            if let l = h.value(forHTTPHeaderField:"Location") { row["locationRedacted"] = cleanLocation(l) }
            var data = Data(); let cap = image ? 2*1024*1024 : 768*1024
            for try await b in bytes { if data.count >= cap { throw NSError(domain:"BodyLimit",code:2) }; data.append(b) }
            row["bytes"] = data.count
            row["sha256"] = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
            // Await delivery of metrics after finite body completion; no additional request.
            for _ in 0..<50 { if !metrics.snapshot().isEmpty { break }; try await Task.sleep(nanoseconds:10_000_000) }
            row["protocols"] = metrics.snapshot(); row["elapsedSeconds"] = Date().timeIntervalSince(start)
            // Refuse every redirect, including validation entrances. No destination visited.
            guard h.statusCode == 200, h.url == url else {
                row["stopped"] = "non-200 or redirect; no destination visited"; return (nil,row)
            }
            if image {
                guard ["image/jpeg","image/png"].contains(h.mimeType ?? ""),
                      let source = CGImageSourceCreateWithData(data as CFData,nil),
                      let cg = CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else {
                    row["decoded"] = false; return (nil,row)
                }
                row["decoded"] = true; row["width"] = cg.width; row["height"] = cg.height
            } else {
                let text = String(decoding:data,as:UTF8.self).lowercased()
                if ["driver-verify","captcha","cf-chl-","challenge-platform","just a moment"].contains(where:text.contains) {
                    row["challengeDetected"] = true; return (nil,row)
                }
                guard h.mimeType == "text/html" else { row["error"] = "not HTML"; return (nil,row) }
            }
            return (data,row)
        } catch {
            let e = error as NSError
            row["errorDomain"] = e.domain; row["errorCode"] = e.code
            row["elapsedSeconds"] = Date().timeIntervalSince(start); row["protocols"] = metrics.snapshot()
            return (nil,row)
        }
    }
    static func match(_ pattern:String,_ text:String) -> [String]? {
        guard let r = try? NSRegularExpression(pattern:pattern,options:[.caseInsensitive,.dotMatchesLineSeparators]), let m = r.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at:i),in:text).map { String(text[$0]) } ?? "" }
    }
    static func run() async -> [String:Any] {
        var rows = [[String:Any]](); var chains = [[String:Any]]()
        for publicHeaders in [false,true] {
            let label = publicHeaders ? "public-header-combination" : "production252-explicit"
            let headers = publicHeaders ? ["User-Agent":ua,"Accept-Language":"zh-CN,zh;q=0.9,en;q=0.7","Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"] : ["Accept":"text/html"]
            let (data,row) = await fetch(page,headers:headers,label:label+"-page",image:false); rows.append(row)
            var chain: [String:Any] = ["label":label,"success":false]
            guard let data, let html = String(data:data,encoding:.utf8) else { chain["stopReason"] = "page unavailable/challenge"; chains.append(chain); continue }
            // Work identity must be a value node, not an incidental recommendation title.
            let identity = match(#"<span\b[^>]*class=["']header["'][^>]*>\s*(?:識別碼|识别码|ID)\s*[:：]\s*</span>\s*<span\b[^>]*>\s*DSOD-?070\s*</span>"#,html) != nil
            var imageURL: URL? = nil
            let anchors = try! NSRegularExpression(pattern:#"<a\b[^>]*class=["'][^"']*\bavatar-box\b[^"']*["'][^>]*>.*?</a>"#,options:[.caseInsensitive,.dotMatchesLineSeparators])
            for m in anchors.matches(in:html,range:NSRange(html.startIndex...,in:html)) {
                guard let range = Range(m.range,in:html) else { continue }; let node = String(html[range])
                guard match(#"<span\b[^>]*>\s*池田マリナ\s*</span>"#,node) != nil,
                      let img = match(#"<img\b[^>]*src=["']([^"']+)["'][^>]*>"#,node),
                      match(#"\btitle=["']池田マリナ["']"#,img[0]) != nil,
                      let url = URL(string:img[1].replacingOccurrences(of:"&amp;",with:"&"),relativeTo:page)?.absoluteURL,
                      url.scheme == "https", url.host == page.host, url.user == nil, url.password == nil,
                      url.query == nil, url.fragment == nil, url.path.hasPrefix("/pics/actress/"),
                      ["jpg","jpeg","png"].contains(url.pathExtension.lowercased()) else { continue }
                imageURL = url; break
            }
            chain["workIdentityMatched"] = identity; chain["actorSameAvatarNodeMatched"] = imageURL != nil
            guard identity, let url = imageURL else { chain["stopReason"] = "fixture validation failed"; chains.append(chain); continue }
            let ih = publicHeaders ? ["User-Agent":ua,"Accept-Language":"zh-CN,zh;q=0.9,en;q=0.7","Accept":"image/avif,image/webp,image/*,*/*;q=0.8","Referer":page.absoluteString] : [:]
            let (image,imageRow) = await fetch(url,headers:ih,label:label+"-avatar",image:true); rows.append(imageRow)
            chain["success"] = image != nil; chains.append(chain)
        }
        return ["schema":1,"os":ProcessInfo.processInfo.operatingSystemVersionString,"environment":ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == nil ? "macOS" : "iOS Simulator","records":rows,"chains":chains,"policy":"2 predefined independent chains; no cookie/credential; default TLS; no redirects; no retry; max 2 pages+2 avatars; no cover download"]
    }
}
#if NATIVE_CLI
@main struct Entry {
    static func main() async throws {
        let result = await NativeProbe.run()
        let data = try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
        print(String(decoding:data,as:UTF8.self))
    }
}
#endif
