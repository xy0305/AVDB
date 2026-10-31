#!/usr/bin/env python3
"""Build 291 — missed live subtitles: late-but-valid lines are shown (clamped to arrival), lateness split into
source vs compute (no more Apple switch at RTF 0.05), heat no longer restarts the engine (hot swap + hysteresis),
same-video re-resolve keeps the pipeline, reader paces on an extrapolated playhead, catches up when > 6 s behind,
retries forever with backoff, reads the lowest-bandwidth HLS variant, accepts disguised segment extensions;
VAD floor ceiling (BGM) + max-length-split crash fix; stale Whisper preference migrated; per-stage counters in the
diagnostics; main-thread work moved off (cache load, diagnostics file write, AI-cover disk decode); hitch monitor
ignores inactive-app gaps and logs big hitches with context. Static checks + Swift core regression (Linux/macOS)."""
import os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
r = Path(__file__).resolve().parents[1]
core = (r / 'AVDB/Services/LiveSubtitleCore.swift').read_text()
eng = (r / 'AVDB/Services/LiveSubtitleEngine.swift').read_text()
reader = (r / 'AVDB/Services/LiveAudioReader.swift').read_text()
diag = (r / 'AVDB/Services/LiveSpeechEngines.swift').read_text()
enh = (r / 'AVDB/Services/AICoverEnhancer.swift').read_text()
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
pl = plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())
for s in ['var arrival: Double?', 'static let lateLimit', 'func currentSegment(at', 'var sourceLag: Double', 'var computeLate: Bool',
          'func computeBound(', 'var stageLine: String', 'stats.droppedLate', 'stats.discardedReset', 'stats.staleResults',
          'static let floorCeiling', 'thresholdCeiling', 'let keep = max(0,', 'static let recoverSeconds', 'live.subtitle.recognizer291',
          'legacy == .apple ? .apple : .senseVoice', 'if thermal >= 3 { return .degrade(.apple']:
    assert s in core, s
assert 'if thermal >= 2 { return .degrade(.apple' not in core, '290 heat → Apple restart loop must be gone'
for s in ['private func hotSwap(to', 'reason=\\(reason)', 'func start(reason: String)', '换源（同一视频）', 'var rawPlayhead',
          '_playing ? min(30', '读取落后', 'readerCatchUps', 'pipeline.computeBound()', 'LiveSubtitleGuard.recoverSeconds',
          'cache.load(key) }.value', 'pipeline.snapshotStats.stageLine', 'applicationState == .active', 'willResignActiveNotification',
          'if !hitches.running { hitches.start() }']:
    assert s in eng, s
assert 'let late = recent.filter { $0.jaLatency > 2.0 }.count' not in eng, '290 clock-based lateness switch must be gone'
assert 'pipeline = LivePipeline(store: cache.load(cacheKey)' not in eng, 'cache must not be decoded on the main actor'
for s in ['waitForSeekOrStop(tok, timeout:', 'extension_picky', 'allowed_extensions', 'lowestVariantStream', 'variant_bitrate', 'failureCount']:
    assert s in reader, s
assert 'if attempts > 3 { onError?(msg); waitForSeekOrStop(tok); attempts = 0 }' not in reader
assert 'writer.asyncAfter' in diag
assert 'func imageOffMain(key:' in enh and 'preparingForDisplay()' in enh and 'cache.memoryImage(key: newKey)' in enh
assert pl['CFBundleVersion'] == '291' and pbx.count('CURRENT_PROJECT_VERSION = 291;') == 2
wf = (r / '.github/workflows/lut4-online291.yml').read_text()
for s in ['test-live291.py', 'package-lut291.py', 'AVDB-291-release']:
    assert s in wf, s
assert 'push:' not in (r / '.github/workflows/lut4-online290.yml').read_text().split('jobs:')[0], '290 workflow must be dispatch-only'
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc') or '/workspace/swift/usr/bin/swiftc'
with tempfile.TemporaryDirectory() as d:
    shutil.copy(r / 'AVDB/Services/LiveSubtitleCore.swift', d)
    shutil.copy(r / 'AVDB/Services/LiveTranslationPrep.swift', d)
    shutil.copy(r / 'scripts/live291/LiveCoreRegression291.swift', Path(d) / 'main.swift')
    cmd = [swiftc, '-O', '-swift-version', '5', 'LiveSubtitleCore.swift', 'LiveTranslationPrep.swift', 'main.swift', '-o', 't']
    if sys.platform == 'darwin' and swiftc == 'swiftc': cmd = ['xcrun'] + cmd
    subprocess.run(cmd, cwd=d, check=True)
    subprocess.run([str(Path(d) / 't')], check=True)
subprocess.run([sys.executable, str(r / 'scripts/test-live289.py')], check=True)
print('PASS live291: late lines shown, source/compute lateness, hot swap + hysteresis, reader catch-up/backoff/low variant, VAD fixes, counters, build 291')
