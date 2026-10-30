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
assert build.isdigit() and int(build) >= 163
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
button = player.split('if lutHoldConsumed { lutHoldConsumed = false } else { showLUT = true }')[1].split('Spacer(minLength: 8)')[0]
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

# Version chooser must be a real child of the player ZStack, not a transparent sheet.
route = pan.split('struct PlaybackVersionMenu: View {')[0]
menu = pan.split('struct PlaybackVersionMenu: View {')[1].split('private struct OfflineCandidate')[0]
overlay = route.split('if showEpisodes {')[1].split('.zIndex(30)')[0]
assert route.count('PlaybackVersionMenu(') == 1
assert route.index('KSChromePlayer(') < route.index('if showEpisodes {') < route.index('.toolbar(.hidden')
assert '.sheet(isPresented: $showEpisodes)' not in pan
assert '.presentationBackground' not in pan
assert 'currentID: vm.currentEpisode?.fileID' in overlay
assert 'close: { showEpisodes = false }' in overlay
assert 'let close: () -> Void' in menu and '@Environment' not in menu and 'dismiss()' not in menu
assert 'Button(action: close)' in menu
assert 'close(); play(index)' in menu and 'close(); deleteCurrent()' in menu
assert 'file.fileID == currentID' in menu
assert '正在播放 ·' in menu and 'selected ? .white' in menu and 'selected ? .black' in menu
assert 'Text(file.name)' in menu and '.lineLimit(1)' in menu and '.truncationMode(.middle)' in menu
assert 'GeometryReader' in menu and 'geometry.safeAreaInsets' in menu
assert 'min(310,' in menu and 'min(contentHeight, availableHeight)' in menu
# Build 212 compact two-line policy: exact sizes, real row count and >=44pt targets.
assert '@ScaledMetric(relativeTo: .body)' in menu
assert 'min(max(scaledTitleSize / 15, 1), 1.3)' in menu
assert 'private var rowHeight: CGFloat { 56 * textScale }' in menu
assert '.system(size: 15 * textScale, weight: .semibold)' in menu
assert '.system(size: 12 * textScale).monospacedDigit()' in menu
assert '.system(size: 11 * textScale)' in menu
assert 'HStack(spacing: 4)' in menu and 'VStack(spacing: 6)' in menu
assert '.padding(.horizontal, 8)' in menu and '}.padding(8)' in menu
assert '.frame(maxWidth: .infinity, minHeight: rowHeight)' in menu
assert '.frame(maxWidth: .infinity, minHeight: 44)' in menu
assert 'let rowCount = episodes.count + (canDelete ? 1 : 0)' in menu
assert 'CGFloat(episodes.count) * rowHeight + (canDelete ? 44 : 0)' in menu
assert 'CGFloat(max(0, rowCount - 1)) * 6 + 16' in menu
assert '.accessibilityElement(children: .ignore)' in menu
label = menu.split('.accessibilityLabel(')[2].split('.accessibilityIdentifier')[0]
assert 'file.name' in label and 'file.size' in label
# Numeric examples tied to the above production source contracts, not rendering tests.
def compact_height(count, delete, scale, screen, top=0, bottom=0):
    rows = count + int(delete)
    content = count * 56 * scale + (44 if delete else 0) + max(0, rows - 1) * 6 + 16
    return min(content, max(0, screen - top - bottom - 32))
assert compact_height(4, True, 1, 390) == 308
assert compact_height(0, False, 1, 390) == 16
assert compact_height(1, False, 1, 390) == 72
for scale in [1, 1.15, 1.3]:
    assert 56 * scale >= 44
    for count in [1, 4, 5, 30]:
        assert compact_height(count, count > 1, scale, 390, 0, 21) <= 337
assert compact_height(30, True, 1, 390, 0, 21) == 337
print('PASS build212: compact 15/12/11pt two-line menu, 56/44pt targets, 310pt width, exact height and scroll cap contracts')
assert 'ScrollView {' in menu and '.background(.regularMaterial, in: RoundedRectangle' in menu
assert 'Color.black.opacity(0.24)' in menu
assert 'onSelectEpisode: vm.episodes.count > 1 ? { showEpisodes = true } : nil' in route
assert '.pause(' not in overlay + menu and 'playURL =' not in overlay + menu
assert 'Task { await vm.deleteEpisode(file) }' in route
assert 'Button("删除此版本", role: .destructive)' in route
assert 'let file = pendingDelete' in route and 'pendingDelete = vm.currentEpisode' in overlay
print('PASS: in-player compact version overlay, bounded filenames, fileID highlight, explicit close and single-file confirmation source contracts (NOT device rendering tests)')
