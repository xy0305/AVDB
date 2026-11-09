#!/usr/bin/env python3
"""Build 297 — live-subtitle audio-read failures: diagnostic only, no on-video banner."""
import os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
r = Path(__file__).resolve().parents[1]
S = r / 'AVDB/Services'
eng = (S / 'LiveSubtitleEngine.swift').read_text()
reader = (S / 'LiveAudioReader.swift').read_text()
views = (r / 'AVDB/Views/Player/LiveSubtitleViews.swift').read_text()
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
pl = plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())
assert pl['CFBundleVersion'] == '315' and pbx.count('CURRENT_PROJECT_VERSION = 315;') == 2
# Must not set the blocking on-video notice for reader failures
assert '字幕音频读取失败（\\(msg)），拖动进度可重试' not in eng
assert 'self?.notice = "字幕音频读取失败' not in eng
assert '静默自动重试中' in eng
assert 'lastReaderError' in eng
assert '仅诊断，不弹提示' in eng
assert '不包含("字幕音频读取失败")' not in views  # swift uses !n.contains
assert '!n.contains("字幕音频读取失败")' in views
assert 'onError logs once' in reader or 'no on-video banner' in reader
# 295/296 must remain
core = (S / 'LiveSubtitleCore.swift').read_text()
for s in ['enum LiveSeekPolicy', 'readerSuspended', 'adjacentMergeMaxBody = 28', 'static func displaySlice']:
    assert s in core + eng, s
assert 'lead: Double = UserDefaults.standard.object(forKey: "live.subtitle.lead") as? Double ?? 20' in eng
wf = (r / '.github/workflows/lut4-online297.yml').read_text()
for s in ['test-live296.py', 'test-live297.py', 'package-lut297.py', 'AVDB-297-release', 'fetch_llama292.py']:
    assert s in wf, s
assert 'push:' in wf.split('jobs:')[0]
assert 'push:' not in (r / '.github/workflows/lut4-online296.yml').read_text().split('jobs:')[0], '296 dispatch-only'
assert 'push:' not in (r / '.github/workflows/lut4-online295.yml').read_text().split('jobs:')[0]
assert (r / 'Build297-LiveSubtitle-NoAudioBanner.md').exists()
assert "=='310'" in (r / 'scripts/package-lut310.py').read_text()
# Chain prior live regressions (296 already chains 295)
subprocess.run([sys.executable, str(r / 'scripts/test-live296.py')], check=True)
print('PASS live297: audio-read failure diagnostic-only, no on-video banner, 296/295 kept, build 297')
