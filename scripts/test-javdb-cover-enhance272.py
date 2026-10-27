"""272: JavDB-native cover clarity — host gate, default off, CISharpenLuminance only."""
from pathlib import Path
R = Path(__file__).resolve().parents[1]
loader = (R / "AVDB/Services/ImageLoader.swift").read_text()
resolver = (R / "AVDB/Services/DetailPosterResolver.swift").read_text()
ui = (R / "AVDB/Views/User/UserView.swift").read_text()
note = (R / "Build272-JavDBCoverEnhance.md").read_text()
wf = (R / ".github/workflows/dmm-preview266.yml").read_text()

assert "public enum JavDBCoverEnhance" in loader
assert 'defaultsKey = "javdb.cover.enhance.enabled"' in loader
assert "CISharpenLuminance" in loader
assert "kCIInputSharpnessKey" in loader
assert "highResSkipPixels = 1200" in loader
assert "JavDBCoverEnhance.maybeApply" in loader
assert "JavDBCoverEnhance.cacheTag" in loader
assert "import CoreImage" in loader

# Host allowlist — only JavDB CDN covers
assert "JavDBConstants.imageCDNHost" in loader
assert "JavDBConstants.webCDNHost" in loader
assert 'path.contains("/covers/")' in loader
assert 'path.contains("/small_covers/")' in loader

# Enhance block must not whitelist non-JavDB hosts
enhance_block = loader.split("public enum JavDBCoverEnhance")[1].split("public enum FrontPosterPolicy")[0]
for banned_host in ["pics.dmm.co.jp", "awsimgsrc.dmm.co.jp", "m.media-amazon.com",
                    "www.javbus.com", "www.tenhow.net", "image.tmdb.org",
                    "image.mgstage.com", "raw.githubusercontent.com"]:
    assert banned_host not in enhance_block, banned_host
assert "isJavDBNativeCover" in enhance_block
assert "shouldEnhance" in enhance_block

# Detail path: enhance winner only; identity separates e0/e1
assert "JavDBCoverEnhance.maybeApply" in resolver
assert "JavDBCoverEnhance.cacheTag" in resolver
assert "invalidateCoverCaches" in resolver

# Settings: off by default (@AppStorage false), accessibility id
assert '@AppStorage("javdb.cover.enhance.enabled") private var coverEnhance = false' in ui
assert 'javdb-cover-enhance-setting' in ui
assert "JavDB 早期封面清晰化" in ui
assert "ImageLoader.shared.clearCache" in ui

# No ML model for covers
assert "VNCoreML" not in enhance_block and "MLModel" not in enhance_block

assert "CISharpenLuminance" in note and "tp.spfcas.com" in note
assert ("Off by default" in note) or ("默认关闭" in note)
assert "test-javdb-cover-enhance272.py" in wf

print("PASS JavDB cover enhance 272 contract")
