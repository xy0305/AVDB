#!/usr/bin/env python3
"""Static guards for Build 273 Amazon exact-ASIN MAIN._SCRM_ HQ path."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
poster = (root / "AVDB/Services/TenhowPoster.swift").read_text()
resolver = (root / "AVDB/Services/DetailPosterResolver.swift").read_text()
evidence = json.loads((root / "scripts/hq-amazon-evidence.json").read_text())

assert "static func directHQ(asin: String)" in poster
assert ".01.MAIN._SCRM_.jpg" in poster
assert "/images/P/" in poster
assert "AmazonPoster.directHQ" in resolver
assert "MAIN._SCRM_" in resolver

discover = resolver.split("private static func discoverTenhow", 1)[1].split("private static func tenhowHTML", 1)[0]
assert "AmazonPoster.directHQ" in discover
assert "amazonHTML" not in discover and "amazon.co.jp/dp/" not in discover
assert "amazonHTML" not in resolver  # HTML fetch removed from resolver; parser stays in TenhowPoster

for banned in ["googleapis", "paapi", "AssociateTag", "search-alias", "field-keywords"]:
    assert banned not in poster.lower() and banned not in discover.lower(), banned

for item in evidence:
    scrm = item["direct_scrm"]
    asin = item["asin"]
    assert scrm["url"] == f"https://m.media-amazon.com/images/P/{asin}.01.MAIN._SCRM_.jpg"
    assert scrm["sha256"] == item["original"]["sha256"]
    assert scrm["original_pixels"] == item["original"]["original_pixels"]

print("PASS amazon-hq273: directHQ MAIN._SCRM_ wired; evidence hashes match Build196 originals; no search")
