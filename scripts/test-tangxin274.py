#!/usr/bin/env python3
"""Static guards for Build 274 Tangxin trailing-slash documentURL (HTTP 307 root cause)."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
core = (root / "AVDB/Services/TangxinCore.swift").read_text()
network = (root / "scripts/TangxinNetworkRegression263.swift").read_text()
fixtures = (root / "scripts/TangxinFixtures261.swift").read_text()

assert 'static let featured = URL(string: "https://tangxinvlog.app/featured/")!' in core
assert "static func documentURL(_ url: URL) -> URL?" in core
assert "percentEncodedPath = encoded + \"/\"" in core or "percentEncodedPath = encoded + \"/\"" in core.replace("'", '"')
assert "components.percentEncodedPath = encoded + \"/\"" in core
assert "guard let target = TangxinPolicy.documentURL(url)" in core
assert "OnlineTransport" in core and "willPerformHTTPRedirection" not in core  # Tangxin does not open redirects itself
# Must not re-enable generic redirect following in OnlineTransport for this fix
transport = (root / "AVDB/Services/OnlinePlaybackCore.swift").read_text()
assert "willPerformHTTPRedirection" in transport
assert "completionHandler(nil)" in transport

assert 'TangxinPolicy.documentURL(barePage)?.path == "/featured/2/"' in network
assert 'precondition(r.url!.path.hasSuffix("/"), "client must GET directory form, not bare path that 307s")' in network
assert 'slashPaths.contains("/featured/2/")' in network

assert 'path == "/featured/2" || path == "/featured/2/"' in fixtures
assert "Build274-TangxinTrailingSlash.md" in (root / "Build274-TangxinTrailingSlash.md").name or True
assert (root / "Build274-TangxinTrailingSlash.md").is_file()

print("PASS tangxin274: documentURL trailing-slash canonicalize; OnlineTransport still blocks redirects; fixtures accept /featured/2/")
