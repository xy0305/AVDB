#!/usr/bin/env python3
"""Build 289 iOS-simulator evidence: fresh install of a host app that embeds the shipping SherpaOnnxC.xcframework
(the same one the release IPA embeds) and the bundled LiveModels; SenseVoice + Whisper small cold load and per-chunk
latency on macOS-TTS Japanese lines (CPU in the simulator). Writes evidence-live289/coldload-sim/*."""
import json, os, platform, shutil, subprocess, sys, time, re
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent / 'live287'))
from ja_samples287 import SENTENCES
r = Path(__file__).resolve().parents[1]
sim = r / 'evidence-live289' / 'coldload-sim'; (sim / 'samples').mkdir(parents=True, exist_ok=True)
assert platform.system() == 'Darwin'
voices = subprocess.run(['say', '-v', '?'], capture_output=True, text=True).stdout.splitlines()
ja = [v.split()[0] for v in voices if 'ja_JP' in v]
voice = next((v for v in ja if v.startswith('Kyoko')), ja[0])
refs = []
for i, s in enumerate(SENTENCES[:6]):
    aiff = sim / f'l{i}.aiff'; wav = sim / 'samples' / f'line289_{i}.wav'
    subprocess.run(['say', '-v', voice, '-r', '190', '-o', str(aiff), s['ja']], check=True)
    subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', str(aiff), str(wav)], check=True)
    refs.append({'file': wav.name, 'ja': s['ja']})
(sim / 'samples' / 'samples289.json').write_text(json.dumps(refs, ensure_ascii=False))
subprocess.run(['ruby', str(r / 'scripts/live289/setup-coldload289.rb')], check=True, cwd=r)
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
phones = [d for runtime, rows in devices.items() if 'iOS' in runtime for d in rows if 'iPhone' in d['name']]
device = next((d for d in phones if 'Pro' in d['name'] and 'Max' not in d['name']), phones[0])
if device['state'] != 'Booted': subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True)
subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], check=True)
b = subprocess.run(['xcodebuild', 'build', '-project', str(sim / 'Cold289.xcodeproj'), '-scheme', 'Cold289', '-configuration', 'Release',
                    '-destination', 'platform=iOS Simulator,id=' + device['udid'], '-derivedDataPath', str(sim / 'Derived'), 'CODE_SIGNING_ALLOWED=NO'],
                   capture_output=True, text=True)
(sim / 'build.log').write_text(b.stdout[-200000:] + b.stderr[-50000:])
assert b.returncode == 0, b.stdout[-5000:] + b.stderr[-3000:]
app = next((sim / 'Derived/Build/Products').glob('Release-iphonesimulator/Cold289.app'))
subprocess.run(['xcrun', 'simctl', 'uninstall', device['udid'], 'org.avdb.Cold289'], check=False)
subprocess.run(['xcrun', 'simctl', 'install', device['udid'], str(app)], check=True)
t1 = time.time()
p = subprocess.run(['xcrun', 'simctl', 'launch', '--console-pty', '--terminate-running-process', device['udid'], 'org.avdb.Cold289'],
                   capture_output=True, text=True, timeout=2400)
(sim / 'console.log').write_text(p.stdout + p.stderr)
line = next((l for l in p.stdout.splitlines() if l.startswith('COLDLOAD289_JSON ')), None)
assert line, p.stdout[-4000:]
res = json.loads(line[len('COLDLOAD289_JSON '):]); res['device'] = device['name']; res['wall_s'] = time.time() - t1
def norm(s): return [c for c in s if not re.match(r'[\s、。？！?!「」…,.]', c)]
def cer(h, ref):
    h, ref = norm(h), norm(ref)
    if not ref: return 0.0 if not h else 1.0
    prev = list(range(len(h) + 1))
    for i in range(1, len(ref) + 1):
        cur = [i] + [0] * len(h)
        for j in range(1, len(h) + 1): cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ref[i - 1] != h[j - 1]))
        prev = cur
    return prev[-1] / len(ref)
summary = []
for rec in res['recognizers']:
    ch = rec.get('chunks', [])
    for c in ch: c['cer'] = cer(c['hyp'], c['ref'])
    if ch:
        ms = sum(c['ms'] for c in ch) / len(ch); rtf = sum(c['ms'] for c in ch) / 1000 / sum(c['audio_s'] for c in ch)
        rec['avg_ms'] = ms; rec['rtf'] = rtf; rec['mean_cer'] = sum(c['cer'] for c in ch) / len(ch)
        summary.append(f"simulator {device['name']} {rec['tier']}: load {rec['load_s']:.2f}s · {ms:.0f} ms/chunk · RTF {rtf:.3f} · CER {rec['mean_cer']:.3f}")
    else: summary.append(f"simulator {rec['tier']}: {rec.get('error')}")
(sim / 'simulator289.json').write_text(json.dumps(res, ensure_ascii=False, indent=2))
(sim / 'summary.md').write_text('\n'.join(summary) + '\n')
print('\n'.join(summary))
sv = next(x for x in res['recognizers'] if x['tier'] == 'sensevoice')
assert sv.get('ok'), sv
print('PASS coldload289 sim')
