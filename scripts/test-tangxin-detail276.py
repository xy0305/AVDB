#!/usr/bin/env python3
"""Static guards for Build 276 Tangxin detail: cover play hit target + pill tags."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = (root / "AVDB/Views/TangxinView.swift").read_text()

assert "tangxin.play.cover" in view, "cover play affordance id missing"
assert "tangxin.play" in view, "bar play id kept for UITests"
assert "loadingDetail" in view and "resolvingPlay" in view
assert "startPlayback" in view
assert "FlowLayout(spacing:8)" in view
assert "Capsule()" in view
assert "NavigationLink(value:tag) { Text(tag.name).font(.caption).frame(minHeight:44) }" not in view
assert "coverPlayHero" in view and "tagChips" in view
assert "allowsHitTesting(false)" in view
assert "liquidGlassCircle()" in view

assert (root / "Build276-TangxinDetailPlayTags.md").is_file(), "build note missing"
ci = (root / ".github/workflows/dmm-preview266.yml").read_text()
assert "test-tangxin-detail276.py" in ci

print("PASS tangxin-detail276: cover play overlay + FlowLayout pill tags; loading/play state split")
