#!/usr/bin/env python3
"""Build 323 播放页样式: thin white chrome (reference screenshot), 倍速 menu, real-throughput download speed.
Static source contracts on Linux; on macOS the throughput sampler is compiled and executed."""
from pathlib import Path
import plistlib, subprocess, sys, tempfile

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '338' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 338;') == 2

player = (r/'AVDB/Views/Player/PlayerView.swift').read_text()
views = (r/'AVDB/Views/Player/LiveSubtitleViews.swift').read_text()
chrome = player.split('    private var chromeOverlay: some View {')[1].split('    private var progressBar: some View {')[0]
bar = player.split('    private var progressBar: some View {')[1].split('    private func tapSeekProgress(atX')[0]
top = chrome.split('// The UIKit single/double recognizers')[0]
bottom = chrome.split('progressBar')[1]

# Existing identifiers / contracts preserved.
for ident in ['player.subtitle.settings', 'player.lut.settings', 'player.play.toggle', 'player.episode.settings',
              'player.source.settings', 'player.online-quality-status', 'player.playback.rate']:
    assert f'.accessibilityIdentifier("{ident}")' in chrome, ident
assert '.accessibilityIdentifier("player.progress")' in bar
assert '.accessibilityIdentifier("player.lut.hold-original")' in player
assert player.count('chromeOverlay.zIndex(10)') == 1 and 'infoBar' not in player
assert 'excludedTop: safeArea.top + 80' in player and 'excludedBottom: safeArea.bottom + 116' in player
assert 'LiveSubtitleMenuButton(engine: live)' in bottom
assert '.accessibilityIdentifier("player.live.subtitle.menu")' in views
assert 'player.live.subtitle.mode.\\(m.rawValue)' in views
lutButton = chrome.split('if lutHoldConsumed { lutHoldConsumed = false } else { showLUT = true }')[1].split('Spacer(minLength: 8)')[0]
assert '.frame(width: 48, height: 48)' in lutButton and '.contentShape(Rectangle())' in lutButton and '.zIndex(20)' in lutButton
assert 'LongPressGesture(minimumDuration: 0.35)' in chrome and 'lut.holdOriginal(true)' in chrome

# Style: no capsule / glass / dark fills on the chrome, light scrim only.
for banned in ['Capsule()', '.liquidGlass(', '.glassSurface(', '.glassEffect(', 'Material', '.black.opacity(0.35), in:']:
    assert banned not in chrome, banned
assert '.glassSurface(' not in bar and 'Capsule().fill(Color.white.opacity(0.32)).frame(height: 3)' in bar
assert 'private func glassButton' not in player and 'private func capsuleButton' not in player
live_label = views.split('struct LiveSubtitleMenuButton: View {')[1].split('struct LiveSubtitleStatusChip')[0].split('} label: {')[-1]
assert 'Capsule' not in live_label and '.background(' not in live_label and 'frame(minHeight: 48)' in live_label

# Top: X, title (one truncated line), online subtitles, LUT, orientation/fill — no copied extras.
assert top.index('Image(systemName: "xmark")') < top.index('Text(title.isEmpty') < top.index('player.subtitle.settings') \
    < top.index('player.lut.settings') < top.index('Button("横屏全屏")')
assert '.lineLimit(1)' in top and '.truncationMode(.tail)' in top
for banned in ['house', 'airplayvideo', 'AVRoutePickerView', '弹幕', 'headphones', 'folder', 'film', 'SUPJAV', 'logo']:
    assert banned not in chrome, banned
# Bottom: play/pause only on the left (no next-episode, no +10 s button); plain text 1080P/选集/倍速 on the right.
assert 'forward.fill' not in chrome and 'forward.end' not in chrome and '+ 10' not in chrome
assert 'chromeTextLabel(subtitle.isEmpty ? "播放源" : subtitle)' in bottom
assert 'chromeTextLabel("选集")' in bottom
assert 'chromeTextLabel(playbackRate == 1 ? "倍速"' in bottom
assert bottom.index('player.play.toggle') < bottom.index('Spacer(minLength: 8)') < bottom.index('player.source.settings') \
    < bottom.index('player.episode.settings') < bottom.index('player.playback.rate')
# Double-tap skip stays.
assert 'AVDBDoubleTapPolicy.perform(' in player and 'seek: { skip(by: $0) }' in player

# Progress: time left, Slider + tap-to-seek + seek preview, duration right.
assert bar.index('formatTime(isSeeking ? seekValue : currentTime)') < bar.index('Slider(') < bar.index('formatTime(duration)')
assert 'SpatialTapGesture()' in bar and 'tapSeekProgress(atX: event.location.x' in bar
assert 'seekPreview.request(time: seekValue' in bar and 'seekPreviewCard' in bar and 'seek(to: seekValue)' in bar

# 倍速.
assert 'static let playbackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]' in player
rate = player.split('private func applyPlaybackRate()')[1].split('\n    }\n')[0]
assert 'coordinator.playerLayer?.player' in rate and 'player.playbackRate = playbackRate' in rate
ready = player.split('if state == .readyToPlay {')[1].split('syncTime()')[0]
assert 'applyPlaybackRate()' in ready, 'replaced item must get the session rate again'
ticker = player.split('private func startTicker()')[1].split('private func applyOnlineQuality')[0]
assert 'applyPlaybackRate()' in ticker and 'sampleThroughput()' in ticker

# Download speed: real transferred bytes only, never encoded/indicated bitrate; hidden when unmeasurable.
sampler = player.split('struct PlaybackThroughputSampler: Equatable {')[1].split('/// Route lifetime')[0]
assert 'numberOfBytesTransferred' in sampler
for banned in ['indicatedBitrate', 'observedBitrate', 'averageVideoBitrate', 'peakBitRate', 'estimatedDataRate']:
    assert banned not in sampler, banned
assert 'if let downloadSpeed {' in top and 'player.download.speed' in top
assert 'throughput.reset()' in player.split('.onChange(of: url)')[1].split('.onChange(of: headers)')[0]

# Release wiring.
wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 338' in wf and 'feat/player-chrome-323' in wf
assert 'python3 scripts/test-player-chrome323.py' in wf
assert 'scripts/package-lut338.py' in wf and 'AVDB-338-release' in wf and 'AVDB-322-' not in wf
pkg = (r/'scripts/package-lut338.py').read_text()
assert "=='338'" in pkg and 'AVDB-unsigned-1.0.2-338-logout-access.ipa' in pkg
assert (r/'Build323-PlayerChrome.md').is_file()
print('PASS player-chrome323 source contracts: thin white chrome, identifiers kept, 倍速 menu, real-throughput speed, release 323')

if sys.platform != 'darwin':
    print('SKIP executable throughput sampler check locally: requires macOS CI')
    sys.exit(0)
src = 'import Foundation\nimport AVFoundation\nstruct PlaybackThroughputSampler: Equatable {' + sampler
main = r'''
var s = PlaybackThroughputSampler()
s.sample(totalBytes: nil, at: 0); precondition(s.bytesPerSecond == nil)
s.sample(totalBytes: 1_000_000, at: 1); precondition(s.bytesPerSecond == nil)  // first sample: no rate yet
s.sample(totalBytes: 2_000_000, at: 1.5); precondition(s.bytesPerSecond == 2_000_000)
s.sample(totalBytes: 2_000_000, at: 2.0); precondition(s.bytesPerSecond == 1_000_000)
s.sample(totalBytes: 500, at: 2.5); precondition(s.bytesPerSecond == nil)       // new item: counter restarted
s.sample(totalBytes: 0, at: 3.0); precondition(s.bytesPerSecond == nil)         // unmeasurable → hidden
precondition(PlaybackThroughputSampler.display(3.2 * 1024 * 1024) == "3.2 MB/s")
precondition(PlaybackThroughputSampler.display(512 * 1024) == "512 KB/s")
print("PASS throughput sampler executable")
'''
with tempfile.TemporaryDirectory() as tmp:
    a = Path(tmp)/'s.swift'; a.write_text(src)
    m = Path(tmp)/'main.swift'; m.write_text(main)
    exe = str(Path(tmp)/'t')
    subprocess.run(['xcrun', 'swiftc', str(a), str(m), '-o', exe], check=True)
    subprocess.run([exe], check=True)
