#!/usr/bin/env python3
"""Build 288 cold-load evidence (CI Mac, bundled LiveModels only):
 1. macOS CLI with the shipping loader under `sandbox-exec` (all outbound IP denied): small / turbo cold (first
    process) + warm (second process, Core ML cache), NLLB, plus the exact 287 config as an A/B.
 2. iOS simulator host app (fresh install, Core ML on CPU): small → turbo → NLLB load + first transcription.
Writes evidence-live288/coldload/*.json and summary.md."""
import json, os, platform, shutil, subprocess, sys, time
from pathlib import Path
r = Path(__file__).resolve().parents[1]
out = r / 'evidence-live288' / 'coldload'; out.mkdir(parents=True, exist_ok=True)
assert platform.system() == 'Darwin'
models = r / 'AVDB/Resources/LiveModels'
assert (models / 'openai_whisper-small_216MB/AudioEncoder.mlmodelc').exists(), 'LiveModels not populated'
JA = '雨が降りそうだから、傘を持って行ってね。'
work = Path(os.environ.get('RUNNER_TEMP', '/tmp')) / 'cold288'; work.mkdir(parents=True, exist_ok=True)
voices = subprocess.run(['say', '-v', '?'], capture_output=True, text=True).stdout.splitlines()
ja = [v.split()[0] for v in voices if 'ja_JP' in v]
voice = next((v for v in ja if v.startswith('Kyoko')), ja[0])
subprocess.run(['say', '-v', voice, '-r', '190', '-o', str(work / 's.aiff'), JA], check=True)
wav = work / 'sample288.wav'
subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', str(work / 's.aiff'), str(wav)], check=True)
mode = sys.argv[1] if len(sys.argv) > 1 else 'all'
summary = []
if mode in ('all', 'mac'):
    pkg = r / 'scripts/live288/coldload'; src = pkg / 'Sources/ColdLoad288'
    for f in ['AVDB/Services/LiveSubtitleCore.swift', 'AVDB/Services/LiveTranslationPrep.swift', 'AVDB/Services/LiveSpeechEngines.swift', 'AVDB/Services/LiveAppleTranslation.swift',
              'scripts/live288/ColdLoadCore288.swift']:
        shutil.copy(r / f, src)
    subprocess.run(['swift', 'build', '-c', 'release', '--package-path', str(pkg)], check=True)
    binp = Path(subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path', '--package-path', str(pkg)], text=True).strip())
    profile = work / 'nonet.sb'
    profile.write_text('(version 1)\n(allow default)\n(deny network-outbound (remote ip))\n(deny network-inbound (local ip))\n')
    runs = [('small-cold', 'small', True), ('small-warm', 'small', False), ('turbo-cold', 'turbo', False), ('turbo-warm', 'turbo', False),
            ('legacy287-small', 'legacy287:small', False), ('legacy287-turbo', 'legacy287:turbo', False)]
    mac = {}
    for name, tiers, nllb in runs:
        j = out / f'mac-{name}.json'
        cmd = ['sandbox-exec', '-f', str(profile), str(binp / 'ColdLoad288'), str(models), tiers, str(wav), JA, str(j)] + (['nllb'] if nllb else [])
        t0 = time.time()
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=1500)
        (out / f'mac-{name}.log').write_text(p.stdout + p.stderr)
        res = json.loads(j.read_text()) if j.exists() else {'error': f'exit {p.returncode}', 'tail': (p.stdout + p.stderr)[-2000:]}
        res['wall_s'] = time.time() - t0
        mac[name] = res
        print(name, json.dumps(res, ensure_ascii=False)[:1500])
    (out / 'mac.json').write_text(json.dumps(mac, ensure_ascii=False, indent=2))
    for name in ['small-cold', 'small-warm', 'turbo-cold', 'turbo-warm']:
        m = mac[name]
        assert m.get('network_probe', '').startswith('blocked'), (name, m.get('network_probe'))
        w = m['whisper'][0]
        assert w['ok'] and w['tokenizer'] == 'LiveBundledTokenizer', (name, w)
        summary.append(f"macOS sandbox(no network) {name}: load {w['load_s']:.1f}s · 首句 {w.get('first_transcribe_ms', 0):.0f}ms · 「{w.get('text', '')}」")
    assert mac['small-cold']['nllb']['ok'], mac['small-cold']['nllb']
    summary.append(f"macOS NLLB load {mac['small-cold']['nllb']['load_s']:.1f}s · {mac['small-cold']['nllb']['translate_ms']:.0f}ms 「{mac['small-cold']['nllb']['zh']}」")
    for name in ['legacy287-small', 'legacy287-turbo']:
        summary.append(f"A/B 287 config {name}: {json.dumps({k: v for k, v in mac[name].items() if k in ('ok', 'load_s', 'timeout', 'error', 'tokenizer')}, ensure_ascii=False)[:400]}")
if mode in ('all', 'sim'):
    sim = r / 'evidence-live288' / 'coldload-sim'; sim.mkdir(parents=True, exist_ok=True)
    shutil.copy(wav, sim / 'sample288.wav')
    subprocess.run(['ruby', str(r / 'scripts/live288/setup-coldload288.rb')], check=True, cwd=r)
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
    phones = [d for runtime, rows in devices.items() if 'iOS' in runtime for d in rows if 'iPhone' in d['name']]
    device = next((d for d in phones if 'Pro' in d['name'] and 'Max' not in d['name']), phones[0])
    if device['state'] != 'Booted': subprocess.run(['xcrun', 'simctl', 'boot', device['udid']], check=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device['udid'], '-b'], check=True)
    t0 = time.time()
    b = subprocess.run(['xcodebuild', 'build', '-project', str(sim / 'Cold288.xcodeproj'), '-scheme', 'Cold288', '-configuration', 'Release',
                        '-destination', 'platform=iOS Simulator,id=' + device['udid'], '-derivedDataPath', str(sim / 'Derived'), 'CODE_SIGNING_ALLOWED=NO'],
                       capture_output=True, text=True)
    (sim / 'build.log').write_text(b.stdout[-200000:] + b.stderr[-50000:])
    assert b.returncode == 0, b.stdout[-4000:] + b.stderr[-2000:]
    app = next((sim / 'Derived/Build/Products').glob('Release-iphonesimulator/Cold288.app'))
    subprocess.run(['xcrun', 'simctl', 'uninstall', device['udid'], 'org.avdb.Cold288'], check=False)
    subprocess.run(['xcrun', 'simctl', 'install', device['udid'], str(app)], check=True)
    t1 = time.time()
    p = subprocess.run(['xcrun', 'simctl', 'launch', '--console-pty', '--terminate-running-process', device['udid'], 'org.avdb.Cold288'],
                       capture_output=True, text=True, timeout=2400)
    (sim / 'console.log').write_text(p.stdout + p.stderr)
    line = next((l for l in p.stdout.splitlines() if l.startswith('COLDLOAD288_JSON ')), None)
    assert line, p.stdout[-4000:]
    res = json.loads(line[len('COLDLOAD288_JSON '):]); res['device'] = device['name']; res['wall_s'] = time.time() - t1
    (out / 'simulator.json').write_text(json.dumps(res, ensure_ascii=False, indent=2))
    for w in res['whisper']:
        assert w['ok'] and w['tokenizer'] == 'LiveBundledTokenizer', w
        summary.append(f"simulator {device['name']} cold {w['tier']}: load {w['load_s']:.1f}s · 首句 {w.get('first_transcribe_ms', 0):.0f}ms · 「{w.get('text', '')}」")
    summary.append(f"simulator NLLB: {json.dumps(res.get('nllb'), ensure_ascii=False)[:300]} · tripwire {res['tripwire_hits']} · hub cache {res['hub_cache_created']}")
    assert not res['tripwire_hits'] and not res['hub_cache_created']
(out / f'summary-{mode}.md').write_text('\n'.join(summary) + '\n')
print('\n'.join(summary))
print('PASS coldload288', mode)
