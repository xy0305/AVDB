#!/usr/bin/env python3
"""Build 287 wiring + core regression: live subtitles are wired into the single player (all sources), the
Xcode project carries the sources / WhisperKit / LiveModels folder, and LiveSubtitleCore passes its
platform-neutral regression (VAD, dedupe, captions, cache, guard, scheduler, NLLB tokenizer parity, latency sim)."""
import os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
r = Path(__file__).resolve().parents[1]
player = (r / 'AVDB/Views/Player/PlayerView.swift').read_text()
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
views = (r / 'AVDB/Views/Player/LiveSubtitleViews.swift').read_text()
engine = (r / 'AVDB/Services/LiveSubtitleEngine.swift').read_text()
reader = (r / 'AVDB/Services/LiveAudioReader.swift').read_text()
engines = (r / 'AVDB/Services/LiveSpeechEngines.swift').read_text()
apple = (r / 'AVDB/Services/LiveAppleTranslation.swift').read_text()
# Player wiring: one engine per KSChromePlayer, attached on appear / url / headers, detached on stop, seek hook.
for s in ['@StateObject private var live = LiveSubtitleEngine()', 'attachLiveSubtitles()', 'live.detach()', 'live.didSeek(to: time)',
          'LiveSubtitleOverlay(caption: live.caption', 'chromeVisible: showChrome', 'LiveSubtitleMenuButton(engine: live)',
          'LiveSubtitleSettingsSheet(engine: live', 'LiveTranslationHost(engine: live)', 'p.currentPlaybackTime, Double(p.playbackRate), p.isPlaying',
          'resumeKey ?? progressID ?? url.absoluteString', '|| editingLivePosition || showLiveSettings']:
    assert s in player, s
assert player.count('attachLiveSubtitles()') >= 4          # definition + appear + url + headers
# Modes + style + guard surfaces.
for s in ['"关"', '"日文"', '"中文"', '"双语"']: assert s in (r / 'AVDB/Services/LiveSubtitleCore.swift').read_text(), s
for s in ['chromeReserve', 'LiveOutlinedText', 'live.subtitle.zh.pending', 'live.subtitle.partial', 'player.live.subtitle.menu',
          'LiveSubtitleStyle.fontKey', 'LiveSubtitleStyle.positionKey', '.translationTask(bridge.configuration)']:
    assert s in views, s
for s in ['ProcessInfo.processInfo.thermalState', 'isLowPowerModeEnabled', 'batteryLevel', 'LiveSubtitleCache.key(video:', 'abs(c.time - expected) > 1.5',
          'readerShouldRun', 'max(1, c.rate)']:
    assert s in engine, s
# Reader: audio-only, other streams discarded, headers / UA / referer, interrupt, seek trim, 16 kHz mono float.
for s in ['AVDISCARD_ALL', 'av_find_best_stream(ctx, AVMEDIA_TYPE_AUDIO', '"user_agent"', '"referer"', '"headers"', 'interrupt_callback',
          'AV_SAMPLE_FMT_FLT, 16000', 'av_seek_frame', 'dropUntil', 'skipTarget']:
    assert s in reader, s
for s in ['language: "ja"', 'detectLanguage: false', 'withoutTimestamps: true', 'audioEncoderCompute: encoder', '.cpuAndNeuralEngine', 'promptTokens', 'download: false']:
    assert s in engines, s
for s in ['TranslationSession(installedSource:', 'LanguageAvailability()', 'prepareTranslation()', 'withTimeout(2.0)']:
    assert s in apple, s
# Project: sources, folder reference, WhisperKit exact 1.1.1, build 287.
for f in ['LiveSubtitleCore.swift', 'LiveAudioReader.swift', 'LiveSpeechEngines.swift', 'LiveAppleTranslation.swift', 'LiveSubtitleEngine.swift', 'LiveSubtitleViews.swift']:
    assert f'/* {f} in Sources */,' in pbx, f
    assert (r / ('AVDB/Views/Player/' if f == 'LiveSubtitleViews.swift' else 'AVDB/Services/') / f).exists(), f
assert 'lastKnownFileType = folder; path = LiveModels;' in pbx and '/* LiveModels in Resources */,' in pbx
assert 'argmaxinc/argmax-oss-swift.git' in pbx and 'version = 1.1.1;' in pbx and 'productName = WhisperKit;' in pbx
assert (r / 'AVDB/Resources/LiveModels/README.md').exists()
assert plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())['CFBundleVersion'] == '287'
assert pbx.count('CURRENT_PROJECT_VERSION = 287;') == 2
wf = (r / '.github/workflows/lut4-online287.yml').read_text()
for s in ['fetch_models287.py', 'test-live-bench287.py', 'test-live-ui287.py', 'package-lut287.py', 'actions/cache']: assert s in wf, s
# Core regression with the real Swift toolchain.
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc') or '/workspace/swift/usr/bin/swiftc'
with tempfile.TemporaryDirectory() as d:
    shutil.copy(r / 'AVDB/Services/LiveSubtitleCore.swift', d)
    shutil.copy(r / 'scripts/live287/LiveCoreRegression287.swift', Path(d) / 'main.swift')
    cmd = [swiftc, '-O', '-swift-version', '5', 'LiveSubtitleCore.swift', 'main.swift', '-o', 't']
    if sys.platform == 'darwin': cmd = ['xcrun'] + cmd if swiftc == 'swiftc' else cmd
    subprocess.run(cmd, cwd=d, check=True)
    subprocess.run([str(Path(d) / 't'), str(r / 'scripts/live287')], check=True)
print('PASS live287 wiring: player (all sources) / overlay above chrome / 关·日文·中文·双语 menu / settings / guard / cache / reader / WhisperKit / Apple Translation / project + core regression')
