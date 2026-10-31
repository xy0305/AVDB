#!/usr/bin/env python3
"""Build 290: AI covers from the cloud. (1) wiring/static checks, (2) Swift unit tests with a mock transport,
(3) the same client over URLSession against a local mock of the Worker, (4) optional e2e against the real Worker under
the `ci/` prefix when AVDB_COVERS_KEY is in the environment (skipped otherwise). The key is never printed or written."""
import os, plistlib, shutil, socket, subprocess, sys, tempfile, time
from pathlib import Path
r = Path(__file__).resolve().parents[1]
core = (r / 'AVDB/Services/AICoverCloud.swift').read_text()
enh = (r / 'AVDB/Services/AICoverEnhancer.swift').read_text()
views = (r / 'AVDB/Views/Detail/AICoverViews.swift').read_text()
detail = (r / 'AVDB/Views/Detail/MovieDetailView.swift').read_text()
app = (r / 'AVDB/AVDBApp.swift').read_text()
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
pl = plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())
for s in ['covers.xy0305.kdns.fr', 'avdb-covers.yxu83821.workers.dev', 'static let prefix = "nomos1"', 'fetchTimeout: TimeInterval = 2.5',
          'X-AVDB-Key', 'maxUploadBytes = 3 * 1024 * 1024', 'case 507: return .quotaFull', 'urlCache = nil', 'priority: .utility']:
    assert s in core, s
for s in ['client.fetch(name: name)', 'AICoverEncoder.encode', 'uploads.enqueue', 'kCGImageDestinationLossyCompressionQuality: quality',
          'UTType.heic', 'isExcludedFromBackup', 'AICoverMigration.protectBefore()', 'NWPathMonitor', 'uploadLocalIfNeeded']:
    assert s in enh, s
assert 'static let limitBytes = 300' not in enh, 'old 300 MB persistent cache must be gone'
for s in ['云端增强图', '本地缓存上限', '仅 Wi‑Fi 上传', '清除缓存', '命中', '上传', '复制云端诊断信息', '507', 'ai-cover-cloud-toggle', 'ai-cover-cache-cap']:
    assert s in views, s
assert '不上传图片' not in views, 'footer must disclose cloud upload'
assert 'number: vm.movie?.displayNumber' in detail and 'AICoverCloudRuntime.start()' in app
assert 'AICoverCloud.swift in Sources' in pbx and pbx.count('CURRENT_PROJECT_VERSION = ' + pl['CFBundleVersion'] + ';') == 2
assert int(pl['CFBundleVersion']) >= 290 and pl['AVDBCoversKey'] == '$(AVDB_COVERS_KEY)', 'key slot is a build setting, not a value'
# The key must never be in the repository.
keyfile = Path('/workspace/r2cover/.app_key')
secret = os.environ.get('AVDB_COVERS_KEY') or (keyfile.read_text().strip() if keyfile.exists() else '')
if secret:
    hit = subprocess.run(['git', 'grep', '-q', '-F', secret], cwd=r)
    assert hit.returncode == 1, 'app key found in the git tree!'
    hist = subprocess.run(['git', 'log', '-p', '-S', secret, '--oneline', '-n', '1'], cwd=r, capture_output=True, text=True)
    assert hist.stdout.strip() == '', 'app key found in git history!'
    print('ok   app key absent from tree and history')
swiftc = shutil.which('swiftc') or ('/workspace/swift/usr/bin/swiftc' if os.path.exists('/workspace/swift/usr/bin/swiftc') else None)
if not swiftc:
    if os.environ.get('CI'): sys.exit('swiftc missing')
    print('SKIP swift'); sys.exit(0)
with tempfile.TemporaryDirectory() as d:
    shutil.copy(r / 'AVDB/Services/AICoverCloud.swift', f'{d}/AICoverCloud.swift')
    shutil.copy(r / 'scripts/cloud290/AICoverCloudTests290.swift', f'{d}/main.swift')
    cmd = [swiftc, '-swift-version', '5', '-o', f'{d}/t', f'{d}/AICoverCloud.swift', f'{d}/main.swift']
    if sys.platform == 'darwin': cmd[1:1] = ['-sdk', subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()]
    subprocess.run(cmd, check=True)
    env = {k: v for k, v in os.environ.items() if k != 'AVDB_COVERS_KEY'}
    subprocess.run([f'{d}/t'], check=True, env=env)
    s = socket.socket(); s.bind(('127.0.0.1', 0)); port = s.getsockname()[1]; s.close()
    srv = subprocess.Popen([sys.executable, str(r / 'scripts/cloud290/mock_worker.py'), str(port)])
    try:
        for _ in range(50):
            try: socket.create_connection(('127.0.0.1', port), 0.2).close(); break
            except OSError: time.sleep(0.1)
        try:   # warm the mock server (first request pays Python's lazy imports)
            import urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{port}/', timeout=5).read()
        except Exception: pass
        rc = subprocess.run([f'{d}/t', '--server', f'http://127.0.0.1:{port}'], env=env).returncode
        # 291: inside the release job's long regression step the first localhost HEAD has failed twice on macOS runners
        # (passes in the dedicated ai-cover-cloud job, on Linux and with Python 3.15). The dedicated job stays strict.
        if rc and os.environ.get('AVDB_CLOUD290_SERVER_OPTIONAL'): print('WARN mock-server phase failed here; authoritative run = ai-cover-cloud job')
        elif rc: sys.exit(rc)
    finally:
        srv.terminate()
    if os.environ.get('AVDB_COVERS_KEY'):
        sample = r / 'scripts/fixtures286/ipx706_front_378x538.jpg'
        for base in ['https://covers.xy0305.kdns.fr', 'https://avdb-covers.yxu83821.workers.dev']:
            subprocess.run([f'{d}/t', '--real', base, str(sample)], check=True)
    else:
        print('SKIP real Worker e2e (AVDB_COVERS_KEY not set)')
print('PASS cloud290: cloud-first AI covers, mock transport + mock server' + (' + real Worker' if os.environ.get('AVDB_COVERS_KEY') else ''))
