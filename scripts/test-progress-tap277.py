#!/usr/bin/env python3
"""Static guards for Build 277: progress bar tap-to-seek."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
player = (root / "AVDB/Views/Player/PlayerView.swift").read_text()

assert "private var progressBar: some View" in player
assert "SpatialTapGesture()" in player, "tap gesture missing"
assert "tapSeekProgress(atX" in player, "tap seek helper missing"
assert "simultaneousGesture(" in player, "must not replace Slider drag"
assert 'accessibilityIdentifier("player.progress")' in player
bar = player.split("private var progressBar:")[1].split("private func tapSeekProgress")[0]
assert "Slider(" in bar
assert "seek(to: seekValue)" in bar
assert "seekPreview.request(time: seekValue" in bar
helper = player.split("private func tapSeekProgress(atX")[1].split("private func glassButton")[0]
assert "x / width" in helper
assert "seek(to: target)" in helper
assert "!horizontalDrag" in helper
assert "seekPending" in helper

assert (root / "Build277-ProgressTapSeek.md").is_file(), "build note missing"
ci = (root / ".github/workflows/dmm-preview266.yml").read_text()
assert "test-progress-tap277.py" in ci
ipa = (root / ".github/workflows/build-ipa.yml").read_text()
assert "test-progress-tap277.py" in ipa

print("PASS progress-tap277: SpatialTap + Slider drag kept; tapSeekProgress maps x→time")
