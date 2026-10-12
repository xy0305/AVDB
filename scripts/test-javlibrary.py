"""Native parser tests. Successful-page fixtures are MOCK; challenge capture is real/sanitized.
Swift executable coverage is mandatory on CI; on Alpine only static checks can run.
"""
from pathlib import Path
import shutil, subprocess, sys, tempfile, json
root=Path(__file__).resolve().parents[1]
core=(root/'AVDB/Services/JavRankingCore.swift').read_text()+'\n'+(root/'AVDB/Services/JavLibraryCore.swift').read_text()
source=(root/'AVDB/Services/JavLibrarySource.swift').read_text()
view=(root/'AVDB/Views/JavLibraryView.swift').read_text()
assert 'URLSessionConfiguration.ephemeral' in source and 'httpCookieStorage = nil' in source
assert 'Authorization' not in source and 'Pan115' not in source+view
assert 'JavDBSDK.shared.exactMovie(code: video.code)' in view
assert 'MovieDetailView(movieID: movie.id)' in view
assert 'source.acceptVerifiedCookies' in view and 'WKWebsiteDataStore.nonPersistent()' in view
assert 'evaluateJavaScript' not in view and 'print(' not in source+view
assert 'Link("来源演员页", destination: actor.url)' in view
assert 'invalidateAndCancel' in source and 'cookies = []' in source
project=(root/'AVDB.xcodeproj/project.pbxproj').read_text()
for name in ['JavLibraryCore.swift','JavLibrarySource.swift','JavLibraryView.swift']:
 assert project.count('/* '+name+' in Sources */')==2
fixtures=root/'scripts/javlibrary-fixtures'
for name in ['mock-videos.html','mock-actors.html','challenge-sanitized.html']:
 assert (fixtures/name).exists()
swift=core+r'''
func check(_ value: Bool, _ name: String) { if !value { fatalError(name) } }
let dir = CommandLine.arguments[1]
func fixture(_ name: String) throws -> String { try String(contentsOfFile: dir + "/" + name, encoding: .utf8) }
let url = JLPolicy.route(.mostWanted, mode: "1", page: 1)
check(url.path == "/cn/vl_mostwanted.php", "real route")
check(JLPolicy.route(.highlyRated).path == "/cn/vl_bestrated.php", "rated route")
check(JLPolicy.route(.actors).path == "/cn/star_mostfav.php", "actor route")
check(url.query?.contains("mode=1") == true, "time filter")
for invalid in ["https://user:pass@example.com", "https://example.com/path", "https://example.com:443", "https://127.0.0.1", "http://example.com", "https://example.com?q=x"] {
 check((try? JLPolicy.domain(invalid)) == nil, "invalid domain " + invalid)
}
check((try? JLPolicy.domain("www.javlibrary.com")) == JLPolicy.canonical, "canonical domain")
check(JLPolicy.cookieDomain(".javlibrary.com", matches: "www.javlibrary.com"), "normal parent-domain verification cookie")
check(!JLPolicy.cookieDomain("javlibrary.com", matches: "eviljavlibrary.com"), "cookie suffix attack")
check(!JLPolicy.cookieDomain("javdb.com", matches: "www.javlibrary.com"), "no JavDB cookie forwarding")
check(!JLPolicy.cookieDomain("115.com", matches: "www.javlibrary.com"), "no 115 cookie forwarding")
check(!JLPolicy.cookieDomain("com", matches: "www.javlibrary.com"), "no TLD cookie")
check(JLPolicy.sourceURL("https://evil.example/cn/?v=x", relativeTo: url) == nil, "foreign route")
let page = try JLHTML.parse(fixture("mock-videos.html"), pageURL: url)
check(page.videos.count == 1, "dedup / invalid code / foreign host")
check(page.videos[0].code == "ABP-123", "exact code")
check(page.videos[0].title.contains("& entity"), "entities")
check(page.filters.map(\.value) == ["1", "2"], "source filters")
check(page.next?.query?.contains("page=2") == true, "pagination")
let noLoop = try JLHTML.parse(fixture("mock-videos.html"), pageURL: JLPolicy.route(.mostWanted, page: 2))
check(noLoop.next == nil, "no backward/repeated pagination")
let actors = try JLHTML.parse(fixture("mock-actors.html"), pageURL: JLPolicy.route(.actors))
check(actors.actors.count == 1 && actors.actors[0].id == "actor-a", "actor identity")
check(actors.actors[0].rank == 1, "source rank")
check(actors.actors[0].url.path == "/cn/vl_star.php", "actor source fallback")
check(JRPolicy.exactCode("ABP-123") == JRPolicy.exactCode("abp123"), "normalization")
check(JRPolicy.exactCode("ABP-123") != JRPolicy.exactCode("ABP-1234"), "no fuzzy match")
check(JRPolicy.exactCode("FC2-PPV-123") != JRPolicy.exactCode("FC2-123"), "FC2 isolation")
for status in [200,403,503] {
 let response = HTTPURLResponse(url:url,statusCode:status,httpVersion:nil,headerFields:nil)!
 do { _ = try JLPolicy.validate(Data(try fixture("challenge-sanitized.html").utf8), response:response); fatalError("accepted challenge") }
 catch JLError.verification {} catch { fatalError("wrong challenge error") }
}
let header = HTTPURLResponse(url:url,statusCode:403,httpVersion:nil,headerFields:["cf-mitigated":"challenge"])!
do { _ = try JLPolicy.validate(Data("opaque".utf8), response:header); fatalError("accepted challenge header") }
catch JLError.verification {} catch { fatalError("wrong header challenge error") }
check((try? JLHTML.parse("<html>unrecognized</html>", pageURL:url)) == nil, "unsupported page explicit error")
print("PASS JavLibrary native parser: routes, filters, pagination, identity, mapping, challenge cases")
'''
if shutil.which('swift'):
 with tempfile.TemporaryDirectory() as temp:
  path=Path(temp)/'main.swift';path.write_text(swift)
  subprocess.run(['swift',str(path),str(fixtures)],check=True)
elif '--require-swift' in sys.argv:
 raise SystemExit('Swift required')
else:
 print('PASS static contracts; Swift executable parser tests deferred to macOS CI (no local Swift)')
print('Live evidence:',json.dumps(json.loads((fixtures/'access-evidence.json').read_text())))
