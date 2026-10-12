"""Offline parser/domain contracts plus optional readonly live checks.

No login, credentials, writes, or paywall bypass. Live mode only GETs public pages.
"""
from pathlib import Path
import json, plistlib, re, shutil, subprocess, sys, urllib.request

root = Path(__file__).resolve().parents[1]
core = (root / "AVDB/Services/JavRankingCore.swift").read_text()
source = (root / "AVDB/Services/JavRankingSource.swift").read_text()
view = (root / "AVDB/Views/JavRankingView.swift").read_text()
user = (root / "AVDB/Views/User/UserView.swift").read_text()
fixtures = root / "scripts/javranking-fixtures"

assert "WKWebView" not in core + source + view
assert "javranking:" in core
assert "JavDBSDK.shared.search" in view and "MovieDetailView(movieID: verified.id)" in view
assert "Pan115" not in view and "offline" not in view.lower()
assert "JavRankingView()" in user
assert "invalidateAndCancel" in source and "pages.removeAll()" in source and "generation +=" in source
assert "httpShouldSetCookies = false" in source
assert "static.javranking.cc" in core and "jdbstatic.com" in core
assert "facts-panel__row" in core and "review-list" in core
assert "aria-label" in core

info = plistlib.loads((root / "AVDB/Resources/Info.plist").read_bytes())
build = info["CFBundleVersion"]
assert build.isdigit() and int(build) >= 167
assert (root / "AVDB.xcodeproj/project.pbxproj").read_text().count(f"CURRENT_PROJECT_VERSION = {build};") == 2

swift = r'''
import Foundation
''' + core + r'''

let base = URL(string: "https://javranking.cc")!
assert((try? JRPolicy.domain("javranking.cc"))?.absoluteString == "https://javranking.cc")
assert((try? JRPolicy.domain("https://javranking.cc/"))?.absoluteString == "https://javranking.cc")
for bad in ["http://user:pass@javranking.cc", "https://javranking.cc/zh-hans/", "https://javranking.cc:443", "https://127.0.0.1", "javascript:alert(1)", "https://javranking.cc/?q=1", "localhost"] {
    do { _ = try JRPolicy.domain(bad); fatalError("accepted \(bad)") } catch {}
}
assert(JRPolicy.route("/zh-hans/videos/26/", relativeTo: "/zh-hans/", base: base) == "/zh-hans/videos/26/")
assert(JRPolicy.route("?page=2", relativeTo: "https://javranking.cc/zh-hans/explore/", base: base) == "/zh-hans/explore/?page=2")
assert(JRPolicy.route("https://evil.example/zh-hans/videos/1/", relativeTo: "/zh-hans/", base: base) == nil)
assert(JRPolicy.route("/zh-hans/videos/1/?token=secret", relativeTo: "/zh-hans/", base: base) == nil)
assert(JRPolicy.route("/en/videos/1/", relativeTo: "/zh-hans/", base: base) == nil)
assert(JRPolicy.image("https://static.javranking.cc/video/cover/26.webp", base: base) != nil)
assert(JRPolicy.image("https://c0.jdbstatic.com/covers/pp/pPORm.jpg", base: base) != nil)
assert(JRPolicy.image("https://missav.ws/cover.jpg", base: base) == nil)
assert(JRPolicy.image("http://static.javranking.cc/a.webp", base: base) == nil)
assert(JRPolicy.normalizedCode("dass-092") == JRPolicy.normalizedCode("DASS092"))

let fixture = CommandLine.arguments[1]
let html = try String(contentsOfFile: fixture, encoding: .utf8)
let page = try JRHTML.parse(html, path: "/zh-hans/explore/", base: base)
assert(page.videos.contains { $0.path == "/zh-hans/videos/26/" && $0.code == "DASS-092" }, "missing live card")
assert(page.videos.first { $0.path == "/zh-hans/videos/26/" }?.image?.contains("static.javranking.cc") == true)
assert(page.next == "/zh-hans/explore/?page=2", page.next ?? "nil")
assert(!page.videos.contains { $0.path.contains("/en/") })
assert(page.links.contains { $0.path == "/zh-hans/rankings/" })
assert(!page.links.contains { $0.path.contains("marks") || $0.path.contains(".md") })

let detailHTML = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
let detail = try JRHTML.parse(detailHTML, path: "/zh-hans/videos/26/", base: base)
assert(detail.detail?.code == "DASS-092" || detail.detail?.title.isEmpty == false)
assert(detail.magnets.allSatisfy { $0.hasPrefix("magnet:?xt=urn:btih:") })
assert(!detail.metadata.isEmpty, "facts missing")
assert(detail.images.allSatisfy { $0.hasPrefix("https://") })

let indexData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
let index = try JRIndex.parse(indexData, base: base)
assert(index.videos.contains { $0.path == "/zh-hans/videos/80/" && $0.code == "010115_001" })
assert(index.categories.contains { $0.name == "中出" })
assert(index.entities.contains { $0.path.hasPrefix("/zh-hans/makers/") || $0.path.hasPrefix("/zh-hans/actors/") })
assert(index.videos.allSatisfy { !$0.id.hasPrefix("http") && $0.id.hasPrefix("javranking:") })
print("PASS offline parser/domain")
'''

home = fixtures / "index.html"
video = fixtures / "videos-detail.html"
index = fixtures / "search-index.json"
assert home.exists() and video.exists() and index.stat().st_size > 100, "fixtures incomplete"
assert "data-video-card" in home.read_text(errors="replace")
assert "DASS-092" in video.read_text(errors="replace")
if shutil.which("swift"):
    subprocess.run(["swift", "-e", swift, str(home), str(video), str(index)], check=True, cwd=root)
else:
    print("Swift unavailable locally; source contracts checked, Swift parser executes on macOS CI")
    html = home.read_text(errors="replace")
    assert 'href="/zh-hans/videos/26/"' in html and "DASS-092" in html and "static.javranking.cc" in html
    explore = (fixtures / "explore.html").read_text(errors="replace")
    assert 'href="?page=2"' in explore and 'aria-label="下一页"' in explore
    detail = video.read_text(errors="replace")
    assert "facts-panel" in detail and "magnet:?xt=urn:btih:" in detail and "application/ld+json" in detail
    data = json.loads(index.read_text())
    assert any(v.get("videoId") == 80 and v.get("code") == "010115_001" for v in data["videos"])
    assert any(e.get("kind") in {"actor", "maker", "director"} for e in data["entities"])
    filt = json.loads((fixtures / "filter-index.json").read_text())
    assert any(c.get("name") == "中出" for c in filt["categories"])
    assert any("categoryIds" in v for v in filt["videos"])

if "--live" in sys.argv:
    def get(path):
        req = urllib.request.Request("https://javranking.cc" + path, headers={"User-Agent": "AVDB-readonly", "Accept": "text/html,application/json"})
        with urllib.request.urlopen(req, timeout=45) as response:
            body = response.read(2_000_000)
            assert 200 <= response.status < 300, response.status
            assert response.geturl().startswith("https://javranking.cc/"), response.geturl()
            return response.status, response.geturl(), body
    status, final, body = get("/zh-hans/")
    html = body.decode("utf-8", "replace")
    assert "data-video-card" in html and "/zh-hans/rankings/" in html and "/zh-hans/explore/" in html
    status, final, body = get("/zh-hans/explore/?page=2")
    page = body.decode("utf-8", "replace")
    assert 'href="?page=3"' in page or 'data-page="3"' in page
    status, final, body = get("/zh-hans/videos/26/")
    detail = body.decode("utf-8", "replace")
    assert "DASS-092" in detail and "magnet:?xt=urn:btih:" in detail
    status, final, body = get("/zh-hans/search-index.json")
    data = json.loads(body)
    assert data["videos"] and data["videos"][0]["videoId"] > 0
    print("PASS readonly live pages", final)
print("PASS javranking")
