"""Build 298 — visible home poster upgrades stay bounded (static contracts)."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
loader = (root / "AVDB/Services/ImageLoader.swift").read_text()
home = (root / "AVDB/Views/Home/HomeView.swift").read_text()
grid = (root / "AVDB/Views/Components/JAVDBUI.swift").read_text()
detail = (root / "AVDB/Views/Detail/MovieDetailView.swift").read_text()
resolver = (root / "AVDB/Services/DetailPosterResolver.swift").read_text()

assert "enum VisibleHQPosterPolicy" in loader
assert "static let concurrency = 2" in loader
assert "static let maxPixelCap = 900" in loader
assert "actor VisibleHQPosterScheduler" in loader
assert "ListHQCoverCache.storeNegative" in loader
assert "if Task.isCancelled { return nil }" in loader
assert "ProcessInfo.processInfo.isLowPowerModeEnabled" in loader
policy = loader.split("enum VisibleHQPosterPolicy", 1)[1].split("actor VisibleHQPosterScheduler", 1)[0]
list_fn = loader.split("public static func sources(movie: Movie)", 1)[1].split("public struct MoviePosterImage", 1)[0]
sync = list_fn.split("for source in javdb", 1)[0]
assert "DetailPosterPolicy.candidates" not in sync and "DMMCoverURLs.upgrade" not in sync
assert policy.count("return source") == 1 and "return Array(result.prefix(1))" in policy
assert "for guess in DetailPosterPolicy.candidates(number: movie.number).prefix(2)" not in policy
for host in ("awsimgsrc.dmm.co.jp", "pics.dmm.co.jp", "m.media-amazon.com", "images-na.ssl-images-amazon.com", "www.tenhow.net", "image.mgstage.com", "pic.duga.jp"):
    assert host in loader, host
assert "secondFallbackURL: sources.dropFirst(2).first" in loader, "synchronous list still has at most three attempts, JavDB last"
assert "upgradesVisibleHQ" in home and home.count("upgradesVisibleHQ: true") == 4
assert "MoviePosterImage(movie: movie, upgradesVisibleHQ: upgradesVisibleHQ)" in grid
assert "DetailPosterResolver.resolve" in detail
assert "VisibleHQPoster" not in detail
assert "AICover" not in loader.split("enum VisibleHQPosterPolicy")[1].split("enum ListHQCoverCache")[0]
assert "ListHQCoverCache.store(number: movie.number, source: winner.source)" in resolver
print("PASS Build 298 visible HQ contracts")
