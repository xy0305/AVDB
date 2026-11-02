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
assert "upgradesVisibleHQ" in home and home.count("upgradesVisibleHQ: true") == 4
assert "MoviePosterImage(movie: movie, upgradesVisibleHQ: upgradesVisibleHQ)" in grid
assert "DetailPosterResolver.resolve" in detail
assert "VisibleHQPoster" not in detail
assert "AICover" not in loader.split("enum VisibleHQPosterPolicy")[1].split("enum ListHQCoverCache")[0]
assert "ListHQCoverCache.store(number: movie.number, source: winner.source)" in resolver
print("PASS Build 298 visible HQ contracts")
