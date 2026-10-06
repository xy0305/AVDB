"""Layout arithmetic + source contracts only; not visual or device proof."""
from pathlib import Path
import math, plistlib, re, subprocess, tempfile
ui = Path('AVDB/Views/Components/JAVDBUI.swift').read_text()
# Execute the ACTUAL Swift helper on CI, not a duplicated Python formula.
start = ui.index('    static func columnCount(')
end = ui.index('\n    /// 是否 iPad', start)
helper = ui[start:end].replace('CGFloat', 'Double')
swift = 'import Foundation\nenum AdaptiveLayout { static var contentMaxWidth: Double { 1100 }\n' + helper + '\n}\n'
cases = [(375,12,3),(320,20,2),(500,20,4),(768,20,4),(1024,20,6),(1366,20,6)]
for width, pad, expected in cases:
    swift += f'assert(AdaptiveLayout.columnCount(width: {width}, padding: {pad}) == {expected})\n'
    usable = min(width,1100)-2*pad
    minimum = 100 if width < 600 else 150
    assert (usable-(expected-1)*12)/expected >= minimum
    print(f'{width}: {expected} columns, card {(usable-(expected-1)*12)/expected:.1f}pt')
import shutil
if shutil.which('swift'):
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp)/'layout.swift'; path.write_text(swift)
        subprocess.run(['swift',str(path)],check=True)
else:
    print('Swift unavailable locally: arithmetic checked; actual Swift helper executes on macOS CI')
info = plistlib.loads(Path('AVDB/Resources/Info.plist').read_bytes())
assert not info['UIRequiresFullScreen']
assert len(info['UISupportedInterfaceOrientations~ipad']) == 4
assert not info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes']
assert Path('AVDB.xcodeproj/project.pbxproj').read_text().count('TARGETED_DEVICE_FAMILY = "1,2";') == 2
assert 'geometry.size' in ui and 'UIScreen' not in ui.replace('// Scene-local geometry: never infer split-window dimensions from UIScreen.', '')
player = Path('AVDB/Views/Player/PlayerView.swift').read_text()
lock = player.split('enum OrientationLock {')[1]
assert lock.index('guard UIDevice.current.userInterfaceIdiom != .pad') < lock.index('request(target')
assert '== .pad ? .all' in Path('AVDB/AVDBApp.swift').read_text()
for name in ['Actors/ActorsView','Detail/MovieDetailView']:
    assert 'UIScreen.main.bounds' not in Path(f'AVDB/Views/{name}.swift').read_text()
assert 'static var contentMaxWidth: CGFloat { 1100 }' in ui
assert 'min(6, max(1,' in ui
print('PASS: iPad window sizing, orientation, multitasking source contracts (not visual proof)')
