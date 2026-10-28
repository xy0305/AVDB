"""Build 275 — list small covers prefer HQ, fall back to JavDB (static contracts)."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
loader = (root / "AVDB/Services/ImageLoader.swift").read_text()
resolver = (root / "AVDB/Services/DetailPosterResolver.swift").read_text()
front = (root / "scripts/test-front-posters.py").read_text()

assert "enum ListHQCoverCache" in loader
assert "public enum ListCoverPolicy" in loader
assert "ListCoverPolicy.sources(movie: movie)" in loader
assert "secondFallbackURL: sources.dropFirst(2).first" in loader
assert "DetailPosterPolicy.candidates(number: movie.number).first" in loader
assert "ListHQCoverCache.url(for: movie.number)" in loader
assert "AmazonPoster.allowedImage(url)" in loader
assert "AvbaseMetadata.allowedDiscoveredImage(url)" in loader
assert "awsimgsrc.dmm.co.jp" in loader
assert "ListHQCoverCache.store(number: movie.number, source: winner.source)" in resolver
# Keep legacy FrontPosterPolicy source order contracts intact.
assert "FrontPosterPolicy.sources(thumb:thumb,cover:wrap) == [wrap,thumb]" in front
assert "ListCoverPolicy.sources(movie: movie)" in front
print("PASS Build 275 list HQ prefer + JavDB fallback contracts")
