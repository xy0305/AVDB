#!/usr/bin/env python3
"""Build 289 — accuracy + speed first: SenseVoice-Small (sherpa-onnx, CPU int8) is the default live recognizer;
Apple on-device recognition (SpeechAnalyzer on iOS 26+, SFSpeechRecognizer on-device below) is the thermal / lag
fallback with a small non-blocking toast; Whisper small/turbo are manual-only (turbo = on-demand download, not
bundled); recognition at utility QoS on one serial worker, read-ahead throttled under heat, hitch monitor; build 289."""
import plistlib, subprocess, sys
from pathlib import Path
r = Path(__file__).resolve().parents[1]
core = (r / 'AVDB/Services/LiveSubtitleCore.swift').read_text()
eng = (r / 'AVDB/Services/LiveSubtitleEngine.swift').read_text()
sp = (r / 'AVDB/Services/LiveSpeechEngines.swift').read_text()
sv = (r / 'AVDB/Services/LiveSenseVoice.swift').read_text()
sysr = (r / 'AVDB/Services/LiveSystemRecognizers.swift').read_text()
views = (r / 'AVDB/Views/Player/LiveSubtitleViews.swift').read_text()
reader = (r / 'AVDB/Services/LiveAudioReader.swift').read_text()
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
pl = plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())
# default + picker
for s in ['case senseVoice = "sensevoice"', 'SenseVoice（默认）', '苹果系统识别', 'live.subtitle.recognizer289', 'enum AppleASRStatus']:
    assert s in core, s
assert 'degrade(.apple' in core and 'func throttledLead' in core
# SenseVoice via sherpa-onnx C API, Japanese, ITN
for s in ['import SherpaOnnxC', 'SherpaOnnxCreateOfflineRecognizer', 'sense_voice', '"ja"', 'SherpaOnnxDecodeOfflineStream']:
    assert s in sv, s
# Apple fallback
for s in ['SpeechTranscriber', 'SpeechAnalyzer', 'AssetInventory', 'requiresOnDeviceRecognition = true', 'SFSpeechRecognizer(locale', 'enum LiveRecognizerFactory']:
    assert s in sysr, s
# whisper manual + turbo on-demand
for s in ['func downloadTurbo', 'func deleteTurboDownload', 'argmaxinc/whisperkit-coreml', 'isExcludedFromBackup']:
    assert s in sp, s
# anti-stutter
assert '.utility' in eng and 'LiveHitchMonitor' in eng and 'throttledLead' in eng and 'sessionOverride' in eng
assert 'qualityOfService = .utility' in reader or '.utility' in reader
# settings
for s in ['live.subtitle.settings.recognizer', 'live.subtitle.settings.apple.asr.download', 'live.subtitle.settings.turbo.download', '复制诊断日志']:
    assert s in views, s
# project
assert 'LiveSenseVoice.swift in Sources' in pbx and 'LiveSystemRecognizers.swift in Sources' in pbx
assert 'SherpaOnnxC.xcframework in Frameworks' in pbx and 'SherpaOnnxC.xcframework in Embed Frameworks' in pbx
assert pl['CFBundleVersion'] == '289' and pbx.count('CURRENT_PROJECT_VERSION = 289;') == 2
assert 'NSSpeechRecognitionUsageDescription' in pl
wf = (r / '.github/workflows/lut4-online289.yml').read_text()
for s in ['fetch_live289.py', 'test-live289.py', 'package-lut289.py', 'test-live-bench289.py', 'AVDB-289-release']:
    assert s in wf, s
old = (r / '.github/workflows/lut4-online288.yml').read_text()
assert 'push:' not in old.split('jobs:')[0], '288 workflow must be dispatch-only'
assert (r / 'scripts/live289/FUNASR_MODEL_LICENSE.txt').exists()
subprocess.run([sys.executable, str(r / 'scripts/test-live288.py')], check=True)
print('PASS live289: SenseVoice default, Apple fallback + toast, Whisper manual, turbo on-demand, utility QoS, build 289')
