from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
player = (root/'AVDB/Views/Player/PlayerView.swift').read_text()
state = root/'AVDB/Views/Player/AVDBAdjustmentPan.swift'
test = root/'scripts/GestureRegression.swift'
assert player.count('UIPanGestureRecognizer(target:') == 1
assert player.count('slider.sendActions(for: .valueChanged)') == 1
assert 'SystemVolume' not in player and 'HiddenVolumeView' not in player
assert 'if gestureRecognizer === recognizer { dragStart = point }' in player
should_begin = player.split('func gestureRecognizerShouldBegin')[1].split('func gestureRecognizer(')[0]
assert 'velocity(' not in should_begin and 'translation(' not in should_begin
assert 'node is UIControl' in player and 'point.y >= parent.excludedTop' in player and 'view.bounds.height - parent.excludedBottom' in player
assert 'excludedTop: safeArea.top + 80' in player and 'excludedBottom: safeArea.bottom + 116' in player
assert 'return !blocked && point.y >= excludedTop' in player
assert 'blocked: editingSubtitlePosition || showOnlineSubtitles' in player
assert 'slider.window === window, slider.isEnabled' in player
assert '!isHidden, alpha == 1' in player
assert 'AVAudioSession.sharedInstance().outputVolume' in player
assert 'screen.brightness = value' in player
assert 'view.volume.submit(value)' in player and '请使用硬件音量键' in player
assert 'gesture.state == .cancelled || gesture.state == .failed' in player
assert 'state.size == view.bounds.size' in player
assert 'sourceID != c.parent.sourceID' in player
assert 'showLUT || seekPending || (isSeeking && !horizontalDrag)' in player
assert 'if horizontalDrag && !cancelled' in player
assert 'seekGeneration == token' in player
assert 'duration > 3600 ? 0.55 : 0.35' in player
# Pause and buffering are not eligibility gates in the UIKit receiver.
receiver = player.split('struct PlayerGestureLayer:')[1]
assert 'isPlaying' not in receiver and 'isBuffering' not in receiver
# Verify production call graph, not just the existence of helper symbols.
callback = player.split('onDoubleTap: { x, width in')[1].split('onSingleTap:')[0]
assert 'AVDBDoubleTapPolicy.perform(x: x, width: width,' in callback
assert 'toggle: { toggleActualPlayback() }, seek: { skip(by: $0) }' in callback
assert callback.count('skip(by:') == 1
actual = player.split('private func toggleActualPlayback()')[1].split('private func skip(')[0]
assert 'guard let layer = coordinator.playerLayer' in actual
assert 'if layer.player.isPlaying' in actual and 'layer.pause()' in actual and 'layer.play()' in actual
assert 'audio.begin()' in actual
assert 'seek(' not in actual and 'currentTime =' not in actual and 'isPlaying =' not in actual
assert 'singleTap.require(toFail: doubleTap)' in receiver
assert 'doubleTap.numberOfTapsRequired = 2' in receiver
recognized = receiver.split('@objc func doubleTap(')[1].split('@objc func singleTap')[0]
assert 'guard !parent.blocked, let view = gesture.view' in recognized
assert 'parent.onDoubleTap(point.x, view.bounds.width)' in recognized
spacer = player.split('// The UIKit single/double recognizers')[1].split('progressBar')[0]
assert '.allowsHitTesting(false)' in spacer and '.onTapGesture' not in spacer
pan = (root/'AVDB/Views/Player/Pan115PlayerView.swift').read_text()
menu = pan.split('struct PlaybackVersionMenu: View')[1].split('private struct OfflineCandidate')[0]
assert 'ForEach(Array(episodes.enumerated())' in menu
assert 'Text(AVDBPlaybackFileSize.text(bytes: file.size))' in menu
assert 'Text(file.name)' in menu and 'file.fileID == currentID' in menu
assert 'KSChromePlayer(' in pan and 'if showEpisodes {' in pan
print('PASS production gesture/size integration source contracts (not device/UI acceptance)')
if sys.platform != 'darwin':
    print('SKIP executable CoreGraphics Swift regression locally: requires macOS CI')
    sys.exit(0)
with tempfile.TemporaryDirectory() as tmp:
    executable = str(Path(tmp)/'gesture-regression')
    subprocess.run(['xcrun', 'swiftc', str(state), str(test), '-o', executable], check=True)
    subprocess.run([executable], check=True)
