#!/usr/bin/env python3
"""Build 288 — live-subtitle model loading never hangs silently:
small first in 自动 then turbo warmed in background, one in-flight load per tier, timeouts → failed + 重试,
status readout (加载中 / 编译中（首次） / 就绪 / 失败), bundled tokenizer only (no Hub), prewarm off,
encoder ANE + decoder GPU, NLLB off the critical path, diagnostic log copyable from settings, build 288."""
import plistlib, subprocess, sys
from pathlib import Path
r = Path(__file__).resolve().parents[1]
eng = (r / 'AVDB/Services/LiveSubtitleEngine.swift').read_text()
sp = (r / 'AVDB/Services/LiveSpeechEngines.swift').read_text()
views = (r / 'AVDB/Views/Player/LiveSubtitleViews.swift').read_text()
host = (r / 'scripts/live287/LiveUIHost287.swift').read_text()
for s in ['prewarm: false, load: false, download: false', 'kit.tokenizer = tokenizer', 'try await kit.loadModels()',
          'AutoTokenizerWrapper.from(modelFolder: folder)', 'final class LiveBundledTokenizer: WhisperTokenizer',
          '(.cpuAndNeuralEngine, .cpuAndGPU)', 'isModelMultilingual = true', 'units: MLComputeUnits = .cpuAndGPU',
          'final class LiveDiagnostics', 'func report(']:
    assert s in sp, s
assert 'prewarm: true' not in sp and 'HubApi(' not in sp
for s in ['final class LiveModelLoader', 'if let t = tasks[tier]', 'throw Timeout(tier: tier, seconds: timeout)', 'withThrowingTaskGroup',
          'static let smallTimeout: Double = 120', 'loadTranslatorInBackground()', 'func retry()', 'func diagnosticReport()', 'os_proc_available_memory()',
          'didReceiveMemoryWarningNotification', '编译中（首次）', '加载中', '失败 — ', 'tier: .small) }', '首次需编译模型，请保持前台']:
    assert s in eng, s
assert 'await self.ensureTranslator()\n                guard !Task.isCancelled, self.mode != .off else { return }\n                self.beginRunning()' not in eng
for s in ['live.subtitle.retry', 'engine.retry()', 'UIPasteboard.general.string = engine.diagnosticReport()', '复制诊断日志',
          'engine.modelStatus', 'engine.phaseText', '模型状态与诊断']:
    assert s in views, s
for s in ['var modelStatus', 'func retry()', 'func diagnosticReport()', 'var phaseText', '--failed']:
    assert s in host, s
assert int(plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())['CFBundleVersion']) >= 288
subprocess.run([sys.executable, str(r / 'scripts/test-live287.py')], check=True)
print('PASS live288: staged small→turbo, deduped loads, timeout + retry, status readout, offline tokenizer, diagnostics, build 288')
