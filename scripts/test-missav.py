"""Read-only capture replay through shipping Swift parser and URLSession boundary.
No credentials, account login, 115 network requests, or cloud writes.
"""
from pathlib import Path
import gzip, json, shutil, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
read = lambda p: (root / p).read_text()
core = read('AVDB/Services/MissAVCore.swift')
source = read('AVDB/Services/MissAVSource.swift')
view = read('AVDB/Views/MissAVRankingView.swift')
rank = read('AVDB/Views/Rankings/RankingsView.swift')
assert 'MissAVRankingView()' in rank and 'JavRankingView(rankingsOnly: true)' in rank
assert 'RankingTab.allCases' in rank and 'initialTab: RankingTab = .top250' in rank
assert 'WKWebView' not in core + source + view and 'Widget.' not in core + source + view
assert 'JavDBSDK.shared.exactMovie(code: code' in view
assert 'MovieDetailView(movieID: movie.id)' in view and 'SearchMovieResultView(keyword: code)' in view
assert 'Pan115Client' not in view and 'addOfflineTask' not in source
assert 'videos.append(contentsOf: fresh)' in view and '.sorted(' not in view
assert 'revision == token' in view and 'epoch == source.generation' in view
assert 'invalidateAndCancel' in source and 'withTaskCancellationHandler' in source
assert 'DownloadLinkDetector.isOfflineResource(url)' in read('AVDB/Views/Detail/MovieDetailView.swift')
project = read('AVDB.xcodeproj/project.pbxproj')
for name in ['MissAVCore.swift','MissAVSource.swift','MissAVRankingView.swift']:
    assert project.count(f'/* {name} in Sources */') == 2
print('PASS additional source only, native exact route/search fallback, original ranking entrypoints, ordered pagination/cancellation and 115 preflight source contracts')
if not shutil.which('swiftc'):
    print('Swift unavailable locally: runtime parser/network/resource tests MUST run on macOS CI; static checks are not runtime evidence')
    raise SystemExit(0)
transport = read('AVDB/Services/JavRankingSource.swift').split('@MainActor final class JavRankingSource:')[0]
swift = 'import Foundation\nimport Combine\n' + read('AVDB/Services/JavRankingCore.swift') + core + transport + source + read('AVDB/Services/DownloadLinkDetector.swift') + r'''
func check(_ yes: Bool, _ name: String) {
    guard yes else { fatalError("FAIL " + name) }; print("PASS " + name)
}
func fixture(_ name: String) throws -> String { try String(contentsOfFile: CommandLine.arguments[1] + "/" + name + ".html", encoding: .utf8) }
let base = URL(string: "https://missav.ws")!
let first = try MissAVHTML.parse(fixture("weekly"), path: "/dm170/cn/weekly-hot", base: base)
let second = try MissAVHTML.parse(fixture("weekly-page2"), path: "/dm170/cn/weekly-hot?page=2", base: base)
check(first.videos.count == 12 && second.videos.count == 12, "captured real 12-card pages")
check(first.next == "/dm170/cn/weekly-hot?page=2" && second.next == "/dm170/cn/weekly-hot?page=3", "actual next links not synthesized")
check(first.videos.first?.code == "MIMK-288", "captured leading number")
check(first.videos.allSatisfy { $0.rank == nil && $0.score == 0 }, "no fabricated ordinal rank or score")
check(first.videos.allSatisfy { $0.image?.hasPrefix("https://fourhoi.com/") == true }, "actual covers preserved")
check(Set(first.videos.map(\.path)).isDisjoint(with: Set(second.videos.map(\.path))), "real second page is distinct")
let root = try JRHTML.tree(fixture("weekly"))
let expected = root.all { $0.tag == "a" && $0.cls("text-secondary") && ($0.attrs["href"] ?? "").contains("/cn/") }.compactMap { $0.attrs["href"] }.map { URL(string:$0)!.path }
check(first.videos.map(\.path) == expected, "full original DOM order preserved")
for (file, path) in [("today","/dm301/cn/today-hot"),("monthly","/dm273/cn/monthly-hot")] {
    let page = try MissAVHTML.parse(fixture(file), path: path, base: base)
    check(page.videos.count == 12 && page.next == path + "?page=2", "observed " + file + " path and pagination")
}
check(first.routes == MissAVHTML.routes, "observed only day/week/month periods")
let detail = try MissAVHTML.detail(fixture("detail"), video: first.videos[0], base: base)
check(detail.video.code == "MIMK-288" && !detail.metadata.isEmpty, "authoritative detail number fallback")
var noCode = first.videos[0]; noCode.code = ""
let fallback = try MissAVHTML.detail(fixture("detail"), video: noCode, base: base)
check(fallback.video.code == "MIMK-288", "missing slug code uses explicit number only")
var conflict = first.videos[0]; conflict.code = "IPX-247"
let conflictDetail = try MissAVHTML.detail(fixture("detail"), video: conflict, base: base)
check(conflictDetail.video.code.isEmpty, "detail conflict prevents automatic mapping")
for code in ["IPX-247", "FC2-PPV-4956715", "HEYZO-1234", "010115_001"] {
    check(!MissAVHTML.code(slug: code.lowercased(), title: code + " fixture").isEmpty, "strict supported catalogue " + code)
}
check(MissAVHTML.code(slug: "ipx-247-chinese-subtitle", title: "IPX-247 fixture") == "IPX-247", "observed subtitle edition suffix")
check(MissAVHTML.code(slug: "ipx-247", title: "IPX-580 fixture").isEmpty, "conflicting title never fuzzy matches")
check(MissAVHTML.code(slug: "not-a-number", title: "fixture").isEmpty, "non-catalogue slug not a backend id")
for bad in ["https://evil.example/cn/ipx-247", "/cn/ipx-247?token=secret", "javascript:alert(1)", "/cn/ipx-247#x", "/cn/../../x", "?page=0", "?page=2&page=3", "?sort=madeup"] {
    check(MissAVHTML.route(bad, page: URL(string: base.absoluteString + "/dm170/cn/weekly-hot")!, base: base) == nil, "reject unsafe/unknown route")
}
check(MissAVHTML.route("?page=3", page: URL(string: "https://missav.ws/dm170/cn/weekly-hot?page=2")!, base: base) == "/dm170/cn/weekly-hot?page=3", "replace existing query")
for bad in ["https://evil.example/a.jpg", "javascript:x", "http://fourhoi.com/a.jpg"] { check(MissAVHTML.image(bad, base: base) == nil, "image allowlist") }
for bad in [try fixture("blocked"), "<html>empty</html>", "<script>thumbnail</script>", "<div>Just a moment</div>"] {
    do { _ = try MissAVHTML.parse(bad, path: "/dm170/cn/weekly-hot", base: base); fatalError("accepted blocked/empty") } catch { print("PASS blocked/empty page produces recoverable error") }
}
let hex = String(repeating: "a", count: 40)
for good in ["magnet:?xt=urn:btih:" + hex, "magnet:?xt=urn:btih:" + String(repeating:"A",count:32) + "&dn=fixture", "ed2k://|file|fixture.mp4|100|" + String(repeating:"a",count:32) + "|/"] {
    check(DownloadLinkDetector.isOfflineResource(good), "valid 115 resource pure preflight")
}
for bad in ["", "https://missav.ws/cn/ipx-247", "https://example.com/master.m3u8", "magnet:?xt=https://example.com", "magnet:?xt=urn:btih:short", "ed2k://|file|x|1|invalid|/"] {
    check(!DownloadLinkDetector.isOfflineResource(bad), "115 rejects webpage/stream/malformed resource without network")
}
final class MockProtocol: URLProtocol, @unchecked Sendable {
    static var status = 200
    static var payload = Data()
    static var delay = 0.0
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay) { [self] in
            guard !stopped else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"text/html"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.payload)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stopped = true }
}
URLProtocol.registerClass(MockProtocol.self)
Task { @MainActor in
    do {
        let defaults = UserDefaults(suiteName: "MissAVFixtureOnly")!
        defaults.removePersistentDomain(forName: "MissAVFixtureOnly")
        let source = MissAVSource(defaults: defaults, protocolClasses: [MockProtocol.self])
        MockProtocol.payload = Data(try fixture("weekly").utf8)
        let page = try await source.page("/dm170/cn/weekly-hot")
        check(page.videos.count == 12, "shipping URLSession read-only transport replay")
        MockProtocol.status = 403
        do { _ = try await source.page("/dm170/cn/weekly-hot"); fatalError("403 accepted") }
        catch { check(error.localizedDescription.contains("403"), "native 403 remains visible recoverable error") }
        MockProtocol.status = 200; MockProtocol.payload = Data(try fixture("blocked").utf8)
        do { _ = try await source.page("/dm170/cn/weekly-hot"); fatalError("challenge accepted") }
        catch { print("PASS 200 challenge never treated as ranking") }
        MockProtocol.payload = Data(try fixture("weekly").utf8); MockProtocol.delay = 0.2
        let stale = Task { try await source.page("/dm170/cn/weekly-hot") }
        try await Task.sleep(nanoseconds: 30_000_000)
        source.reset()
        do { _ = try await stale.value; fatalError("reset published stale page") } catch { print("PASS reset cancels in-flight transfer and generation") }
        let cancelled = Task { try await source.page("/dm170/cn/weekly-hot") }
        try await Task.sleep(nanoseconds: 30_000_000); cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("cancel returned page") } catch { print("PASS cancelled parent stops URLSession") }
        URLProtocol.unregisterClass(MockProtocol.self)
        print("PASS all Swift MissAV fixture/transport/preflight runtime tests (no live 115)")
        exit(0)
    } catch { fputs("FAIL runtime transport: \(error)\n", stderr); exit(1) }
}
RunLoop.main.run(until: Date().addingTimeInterval(15))
fatalError("async fixture timeout")
'''
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    for p in (root / 'scripts/missav-fixtures').glob('*.gz'):
        (tmp / p.name.removesuffix('.gz')).write_bytes(gzip.decompress(p.read_bytes()))
    (tmp / 'main.swift').write_text(swift)
    subprocess.run(['swiftc','-swift-version','5',str(tmp/'main.swift'),'-o',str(tmp/'regression')],check=True)
    subprocess.run([str(tmp/'regression'),str(tmp)],check=True,timeout=60)
