"""Offline external-library regressions. All credentials/data are synthetic; no remote requests."""
from pathlib import Path
import shutil, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = root / 'AVDB/Services/ExternalLibraryClient.swift'
s = source.read_text()
u = (root / 'AVDB/Views/User/UserView.swift').read_text()
d = (root / 'AVDB/Views/Detail/MovieDetailView.swift').read_text()
assert 'static let apiKey' not in s
assert 'URLSession.shared' not in s
assert 'kSecAttrAccessibleWhenUnlockedThisDeviceOnly' in s
assert 'SecItemCopyMatching' in s and 'SecItemUpdate' in s and 'SecItemDelete' in s
assert 'config.urlCache = nil' in s and 'config.urlCredentialStorage = nil' in s
assert 'completionHandler(nil)' in s
assert 'setValue(token, forHTTPHeaderField: "X-API-Key")' in s
assert 'generation == settings.revision' in s and 'invalidateAndCancel()' in s
assert 'defaults.set(token' not in s and 'print(' not in s
assert 'SecureField(' in u and 'external-settings-entry' in u and 'HTTP 未加密' in u
assert '.task(id: externalSettings.revision)' in d and 'externalStatus = error.localizedDescription' in d
assert 'fetchLinks(for: number)' in d
assert 'ExternalLibraryError.url(error.code.rawValue)' in s
assert 'forHTTPHeaderField: "Accept"' in s
assert 'current == attempt' in s and 'generation == settings.revision' in s
assert 'external-test-connection' in u and '.disabled(hasUnsavedEdits || diagnostics.isTesting)' in u
assert 'external-migrate-port' in u and 'connectionTask?.cancel()' in u
import plistlib
plist = plistlib.loads((root / 'AVDB/Resources/Info.plist').read_bytes())
ats = plist['NSAppTransportSecurity']
assert ats == {'NSAllowsArbitraryLoads': True}, 'Review any ATS override instead of assuming HTTP is allowed'
assert plist['CFBundleVersion'] == '178'
print('PASS source security/UI wiring checks (not simulator UI execution)')
if shutil.which('swiftc'):
    with tempfile.TemporaryDirectory() as tmp:
        binary = str(Path(tmp) / 'external-regression')
        subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', str(source), str(root / 'scripts/ExternalLibraryRegression.swift'), '-o', binary], check=True)
        subprocess.run([binary], check=True, timeout=60)
else:
    print('SKIP executable Swift regressions: swiftc unavailable; macOS CI is required')
