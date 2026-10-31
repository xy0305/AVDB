#!/usr/bin/env python3
"""Build 292 — live subtitle translation quality: pre-MT tables (≤ 3-kana interjections, set phrases), moan/breath
skip, sentence + final-particle splitting, title-name glossary, post fixes (unsupported leading 「现在」, NLLB filler
hallucinations on garbled fragments, repetition loops); optional on-device LLM (Sakura-1.5B GGUF on llama.cpp/Metal,
downloaded on request, 机翻 label, CC BY-NC-SA attribution) with context, guarded fallback to Apple/NLLB.
Static checks + Swift translation regression (Linux/macOS)."""
import os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
r = Path(__file__).resolve().parents[1]
S = r / 'AVDB/Services'
prep = (S / 'LiveTranslationPrep.swift').read_text(); llm = (S / 'LiveLLMTranslation.swift').read_text()
core = (S / 'LiveSubtitleCore.swift').read_text(); eng = (S / 'LiveSubtitleEngine.swift').read_text()
apple = (S / 'LiveAppleTranslation.swift').read_text(); views = (r / 'AVDB/Views/Player/LiveSubtitleViews.swift').read_text()
player = (r / 'AVDB/Views/Player/PlayerView.swift').read_text()
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text(); pl = plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())
for s in ['static let interjections', 'static let phrases', 'func isMoan(', 'func splitAtFinalParticle(', 'func cutRepetition(',
          'fillerOutputs', 'func glossary(names:', 'func protect(', 'enum LiveMTRunner', 'protocol LiveContextTranslating']:
    assert s in prep, s
for s in ['sakura-1.5b-qwen2.5-v1.0-Q5KS.gguf', '6722487146c594984e4d222cae0b926c9715ffff712afb5f348b603417c01680', 'CC BY-NC-SA 4.0',
          '机翻', 'hf-mirror.com', 'isExcludedFromBackup', '#if canImport(llama)', 'llama_memory_seq_rm', 'n_gpu_layers = 99']:
    assert s in llm, s
for s in ['LiveMTRunner.runDetailed', 'func history(before', 'var machine', 'static func llmAllowed(', 'mtLine']:
    assert s in core, s
for s in ['func setTitleNames(', 'func downloadLLM()', 'func deleteLLM()', 'checkLLMGuard()', 'LiveLLMTranslator.load()', 'pipeline.glossary = glossary']:
    assert s in eng, s
for s in ['func contextTranslate(', 'setLLMAllowed', 'llmPausedUntil', 'llmSkippedLate']:
    assert s in apple, s
assert 'caption.machine' in views and 'live.subtitle.settings.llm.download' in views and 'LiveLLMModel.license' in views
assert 'applyLiveTitleNames()' in player
for s in ['LiveTranslationPrep.swift in Sources', 'LiveLLMTranslation.swift in Sources', 'llama.xcframework in Frameworks', 'llama.xcframework in Embed Frameworks']:
    assert s in pbx, s
assert int(pl['CFBundleVersion']) >= 292
wf = (r / '.github/workflows/lut4-online292.yml').read_text()
for s in ['test-live292.py', 'package-lut292.py', 'AVDB-292-release', 'fetch_llama292.py']:
    assert s in wf, s
assert 'push:' not in (r / '.github/workflows/lut4-online291.yml').read_text().split('jobs:')[0], '291 workflow must be dispatch-only'
assert (r / 'THIRD_PARTY/LiveTranslation-292.md').exists()
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc') or '/workspace/swift/usr/bin/swiftc'
with tempfile.TemporaryDirectory() as d:
    files = ['LiveSubtitleCore.swift', 'LiveTranslationPrep.swift', 'LiveAppleTranslation.swift', 'LiveLLMTranslation.swift']
    for f in files: shutil.copy(S / f, d)
    shutil.copy(r / 'scripts/live292/LiveMTRegression292.swift', Path(d) / 'main.swift')
    cmd = [swiftc, '-O', '-swift-version', '5'] + files + ['main.swift', '-o', 't']
    if sys.platform == 'darwin' and swiftc == 'swiftc': cmd = ['xcrun'] + cmd
    subprocess.run(cmd, cwd=d, check=True)
    out = subprocess.run([str(Path(d) / 't')], cwd=d, capture_output=True, text=True)
    print(out.stdout[-3000:])
    assert out.returncode == 0 and 'ALL PASS 292 translation' in out.stdout
print('PASS live292: MT tables/moan skip/splitting/glossary/post fixes, LLM routing + guard + cool-down, 机翻 label, optional Sakura download, llama.xcframework, build 292')
