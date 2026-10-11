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
assert 'node is UIControl' in player and 'point.y >= 72' in player and 'bounds.height - 108' in player
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
print('PASS gesture integration source contracts (not device/UI acceptance)')
if sys.platform != 'darwin':
    print('SKIP executable CoreGraphics Swift regression locally: requires macOS CI')
    sys.exit(0)
with tempfile.TemporaryDirectory() as tmp:
    executable = str(Path(tmp)/'gesture-regression')
    subprocess.run(['xcrun', 'swiftc', str(state), str(test), '-o', executable], check=True)
    subprocess.run([executable], check=True)
