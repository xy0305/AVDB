"""Fail closed when preview source settings or built bundle versions drift."""
import pathlib
import plistlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[1]
project = (root / 'AVDB.xcodeproj/project.pbxproj').read_text()
assert re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);', project) == ['266', '266']
assert set(re.findall(r'MARKETING_VERSION = ([^;]+);', project)) == {'1.0.2'}
source = plistlib.loads((root / 'AVDB/Resources/Info.plist').read_bytes())
assert source['CFBundleVersion'] == '$(CURRENT_PROJECT_VERSION)'
assert source['CFBundleShortVersionString'] == '1.0.2'
workflow = (root / '.github/workflows/dmm-preview266.yml').read_text()
assert 'AVDB-unsigned-1.0.2-266-dmm-preview' in workflow
if len(sys.argv) > 1:
    built = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
    assert built['CFBundleVersion'] == '266', built['CFBundleVersion']
    assert built['CFBundleShortVersionString'] == '1.0.2'
    assert built['AVDBSourceCommit'] == sys.argv[2]
print('PASS: DMM preview source/build version synchronization')
