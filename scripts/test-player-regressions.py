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
build = info['CFBundleVersion']
assert build == '159'
assert Path('AVDB.xcodeproj/project.pbxproj').read_text().count(f'CURRENT_PROJECT_VERSION = {build};') == 2
print(f'PASS: format-check and sheet-lifecycle source contracts; consistent build{build}')

# UI source contracts only: device rendering/VoiceOver still require manual validation.
pan = Path('AVDB/Views/Player/Pan115PlayerView.swift').read_text()
assert '原文件：容器/编码/HDR 支持取决于设备' not in pan
assert 'chosen.isOriginal ?' not in pan
assert 'titleVisibility: .visible' in pan and '} message: {' in pan
assert '6_000_000_000' in pan
assert 'guard shownNotices.insert(message).inserted else { return }' in pan
assert 'noticeTask?.cancel()' in pan and 'catch { return }' in pan
assert 'Button(vm.qualityLabel)' not in pan  # source name only in auto-hide chrome
assert pan.count('resetNotices()') == 3  # definition, start, episode playback
assert pan.count('playbackNotice =') == 3  # declaration, clear, bounded show only
panel = lut.split('struct NativeLUTPanel: View {')[1]
assert 'NavigationStack {' in panel
assert panel.index('}.disabled(!model.supported)') < panel.index('.toolbar {')
assert 'ToolbarItem(placement: .confirmationAction)' in panel
assert 'Button { dismiss() }' in panel
assert '.frame(minHeight: 48)' in panel and '.accessibilityLabel(' in panel
assert '.onChange' not in panel  # no automatic dismiss during analysis/enabling
assert '返回播放' in panel and '.presentationDetents([.medium,.large])' in panel
print('PASS: transient notice dedup/dismiss and persistent LUT Done source contracts (not runtime UI tests)')

# Source replacement must clean up old playback without touching the stable route orientation.
assert '.id(url)' in pan and 'managesOrientation: false' in pan
assert '.background(PlaybackOrientationHost().allowsHitTesting(false))' in pan
assert 'static func dismantleUIViewController' in player
stop = player.split('private func stopPlayback()')[1].split('@ViewBuilder')[0]
assert 'if controller.entered { OrientationLock.set(.portrait' in player
assert 'lut.detach()' in stop and 'playerLayer?.pause()' in stop
assert 'Button("横屏全屏")' in player and 'Button("竖屏播放")' in player
button = player.split('Button { showLUT = true } label: {')[1].split('Spacer(minLength: 8)')[0]
assert '.frame(width: 48, height: 48)' in button
assert '.contentShape(Rectangle())' in button and '.zIndex(20)' in button
assert '.accessibilityIdentifier("player.lut.settings")' in button
assert 'chromeOverlay.zIndex(10)' in player
print('PASS: route-owned orientation across source replacement; explicit fullscreen and 48pt LUT hit-target contracts (not device tests)')

assert 'infoBar' not in player
assert player.count('chromeOverlay.zIndex(10)') == 1
assert 'final class AVDBAppDelegate' in Path('AVDB/AVDBApp.swift').read_text()
assert 'scene.requestGeometryUpdate' in player and 'attempt < 5' in player
assert 'analysisGeneration == analysisToken, self.item === item' in lut
assert 'LUTRevealState.composite(original: source' in lut
print('PASS build158: app delegate, bounded route host orientation, same-frame wipe and analysis epoch contracts')
