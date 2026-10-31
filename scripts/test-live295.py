#!/usr/bin/env python3
"""Build 295 — tear down live-subtitle 2nd HLS during scrub; reopen after settle; gate first open; LUT noteSeek."""
import os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
r = Path(__file__).resolve().parents[1]
S = r / 'AVDB/Services'
core = (S / 'LiveSubtitleCore.swift').read_text()
eng = (S / 'LiveSubtitleEngine.swift').read_text()
reader = (S / 'LiveAudioReader.swift').read_text()
player = (r / 'AVDB/Views/Player/PlayerView.swift').read_text()
lut = (r / 'AVDB/Views/Player/NativeLUT.swift').read_text()
surf = (r / 'AVDB/Views/Player/NativeHLSLUTSurface.swift').read_text()
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
pl = plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())
assert pl['CFBundleVersion'] == '295' and pbx.count('CURRENT_PROJECT_VERSION = 295;') == 2
for s in ['enum LiveSeekPolicy', 'coalesceNanoseconds', 'mayReopen(playerReady:', 'mayFirstOpen(playing:']:
    assert s in core, s
for s in ['seekSettled', 'ensureReader', 'readerSuspended', 'firstOpenGate', 'LiveSeekPolicy.coalesceNanoseconds',
          'reader.stop()', 'holdForSeek(true)', '首开字幕读取']:
    assert s in eng, s
assert 'var isRunning: Bool' in reader
# 295 「实时字幕选择关不灵敏」: OFF flips UI state immediately; teardown deferred + cache snapshot detached.
for s in ['modeToken', 'saveCacheDetached', 'await Task.yield()', '实时字幕已关闭', 'latencyCounter % 10']:
    assert s in eng, s
assert 'if mode == .off { saveCache(force: true); stopRunning()' not in eng, 'synchronous OFF teardown must be gone'
views = (r / 'AVDB/Views/Player/LiveSubtitleViews.swift').read_text()
assert 'player.live.subtitle.mode.' in views and 'Picker("实时字幕", selection: $engine.mode)' not in views
for s in ['live.seekSettled', 'lut.noteSeek()', 'live.didSeek']:
    assert s in player, s
assert 'func noteSeek(' in lut and 'func noteSeek(' in surf
assert '解码停滞，已回原画' in surf
wf = (r / '.github/workflows/lut4-online295.yml').read_text()
for s in ['test-live295.py', 'package-lut295.py', 'AVDB-295-release', 'fetch_llama292.py']:
    assert s in wf, s
assert 'push:' in wf.split('jobs:')[0]
assert 'push:' not in (r / '.github/workflows/lut4-online294.yml').read_text().split('jobs:')[0], '294 dispatch-only'
assert 'push:' not in (r / '.github/workflows/lut4-online293.yml').read_text().split('jobs:')[0]
assert (r / 'Build295-Seek-BlackScreen.md').exists()
assert "=='295'" in (r / 'scripts/package-lut295.py').read_text()
# SenseVoice default + lead 20 preserved
assert 'lead: Double = UserDefaults.standard.object(forKey: "live.subtitle.lead") as? Double ?? 20' in eng
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc') or '/workspace/swift/usr/bin/swiftc'
with tempfile.TemporaryDirectory() as d:
    files = ['LiveSubtitleCore.swift', 'LiveTranslationPrep.swift', 'LiveAppleTranslation.swift', 'LiveLLMTranslation.swift']
    for f in files:
        shutil.copy(S / f, d)
    shutil.copy(r / 'scripts/live295/LiveSeekRegression295.swift', Path(d) / 'main.swift')
    cmd = [swiftc, '-O', '-swift-version', '5'] + files + ['main.swift', '-o', 't']
    if sys.platform == 'darwin' and Path(swiftc).name == 'swiftc':
        cmd = ['xcrun'] + cmd
    subprocess.run(cmd, cwd=d, check=True)
    out = subprocess.run([str(Path(d) / 't')], cwd=d, capture_output=True, text=True)
    print(out.stdout[-4000:])
    if out.stderr:
        print(out.stderr[-2000:], file=sys.stderr)
    assert out.returncode == 0 and 'ALL PASS 295 seek-policy' in out.stdout
subprocess.run([sys.executable, str(r / 'scripts/test-live294.py')], check=True)
print('PASS live295: seek teardown+settle reopen, first-open gate, LUT noteSeek, build 295')
