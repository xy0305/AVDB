from pathlib import Path
import plistlib
lut = Path('AVDB/Views/Player/NativeLUT.swift').read_text()
player = Path('AVDB/Views/Player/PlayerView.swift').read_text()
# Source-contract regressions; these are not device/UI tests.
assert lut.index('pathExtension.lowercased() == "m3u8"') < lut.index('loadTracks(withMediaType: .video)')
assert '8_000_000_000' in lut and 'formatTimeout = Task' in lut
assert '未发现视频轨道，LUT 已禁用' in lut
assert '视频格式信息为空，LUT 已禁用' in lut
assert '格式检查超时，LUT 已禁用' in lut
assert 'guard generation == token, item === next else { return }' in lut
assert 'formatTask?.cancel(); formatTask = nil' in lut
assert 'formatTimeout?.cancel(); formatTimeout = nil' in lut
assert '}.disabled(!model.supported)' in lut
sheet = player.split('.sheet(isPresented: $showLUT, onDismiss: {')[1].split('}) { NativeLUTPanel')[0]
assert 'showChrome = true' in sheet and 'startTicker()' in sheet
assert 'OrientationLock' not in sheet and '.pause()' not in sheet and 'detach()' not in sheet
disappear = player.split('.onDisappear {')[1].split('private func stopPlayback')[0]
assert 'guard !showLUT else { return }' in disappear
assert 'guard !playbackActive else' in player
assert 'guard !Task.isCancelled else { return }\n                syncTime()' in player
info = plistlib.loads(Path('AVDB/Resources/Info.plist').read_bytes())
assert info['CFBundleVersion'] == '151'
assert Path('AVDB.xcodeproj/project.pbxproj').read_text().count('CURRENT_PROJECT_VERSION = 151;') == 2
print('PASS: format-check and sheet-lifecycle source contracts; consistent build151')
