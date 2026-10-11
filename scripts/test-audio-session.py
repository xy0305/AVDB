"""Shipping audio ownership + manager executable tests; no claim of device audio acceptance."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
s = (root/'AVDB/Views/Player/PlaybackAudioSession.swift').read_text()
p = (root/'AVDB/Views/Player/PlayerView.swift').read_text()
a = (root/'AVDB/AVDBApp.swift').read_text()
d = (root/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
assert 'setActive(' not in a and 'setCategory(' not in a
assert 'mixWithOthers' not in s
assert 'options: .notifyOthersOnDeactivation' in s
assert 'options: []' in s
assert s.index('audio.begin()\n        return player.makeView') > 0
assert 'AudioOwnedKSVideoPlayer(' in p and 'AudioOwnedTrailerPlayer(' in d
assert 'VideoPlayer(player: AVPlayer(url:' not in d
assert 'player.observe(\\.timeControlStatus' in s
assert 'player.timeControlStatus != .paused' in s
assert 'AVPlayerItemDidPlayToEndTime' in s and 'AVPlayerItemFailedToPlayToEndTime' in s
assert 'coordinator.player.resetPlayer()\n            coordinator.audio.end()' in s
assert 'pipController?.isPictureInPictureActive == true' in s
assert 'while coordinator.pictureInPicture' in s
assert 'playerViewControllerDidStopPictureInPicture' in s
assert 'if state.isPlaying { audio.begin() }' in p
assert 'if layer.options.isSeekedAutoPlay { audio.begin() }' in p
assert 'state == .playedToTheEnd || state == .error' in p
visibility = p.split('.onDisappear {')[1].split('private func stopPlayback')[0]
assert 'stopPlayback()' not in visibility and '.pause()' not in visibility
assert 'audio.end()' not in visibility
assert 'scenePhase' not in s
print('PASS audio source integration: launch, real KS/Apple play, finish/failure, seek/remote resume, teardown, PiP and visibility boundaries')
if sys.platform != 'darwin':
    print('SKIP executable shipping Swift ownership/manager test locally: requires macOS Swift (runs in CI)')
    sys.exit(0)
# Execute the actual production state AND session manager against a recording AVAudioSession.
shipping = s[s.index('struct PlaybackAudioOwnership'):s.index('@MainActor\nfinal class PlaybackAudioLease')]
swift = '''import Foundation
final class AVAudioSession {
 enum Category { case playback }
 enum Mode { case moviePlayback }
 struct CategoryOptions: OptionSet { let rawValue: Int }
 struct SetActiveOptions: OptionSet {
  let rawValue: Int
  static let notifyOthersOnDeactivation = Self(rawValue: 1)
 }
 static let instance = AVAudioSession()
 static func sharedInstance() -> AVAudioSession { instance }
 var events: [String] = []
 func setCategory(_ category: Category, mode: Mode, options: CategoryOptions) throws {
  precondition(options.isEmpty); events.append("category")
 }
 func setActive(_ active: Bool, options: SetActiveOptions = []) throws {
  if !active { precondition(options == .notifyOthersOnDeactivation) }
  events.append(active ? "on" : "off-notify")
 }
}
''' + shipping + '''
MainActor.assumeIsolated {
 let a = UUID(), b = UUID()
 var state = PlaybackAudioOwnership()
 precondition(state.owners.isEmpty)
 state.acquire(a); state.acquire(a)
 precondition(state.owners.count == 1)
 state.acquire(b)
 let old = state.release(a)
 precondition(!state.mayDeactivate(old))
 let idle = state.release(b)
 precondition(state.mayDeactivate(idle))
 state.acquire(a)
 precondition(!state.mayDeactivate(idle))
 _ = state.release(a)
 let audio = PlaybackAudioSession.shared
 let session = AVAudioSession.sharedInstance()
 precondition(session.events.isEmpty) // app boot/browsing is not an activation
 audio.acquire(a)
 precondition(session.events == ["category", "on"])
 // Pause/background/temporary disappear cause no release; resume reasserts without changing category.
 audio.acquire(a)
 precondition(session.events == ["category", "on", "on"])
 audio.acquire(b); audio.release(a)
 RunLoop.main.run(until: Date().addingTimeInterval(0.45))
 precondition(!session.events.contains("off-notify")) // one concrete player remains
 audio.release(b); audio.acquire(a) // synchronous quality/episode source replacement
 RunLoop.main.run(until: Date().addingTimeInterval(0.45))
 precondition(!session.events.contains("off-notify"))
 audio.release(a) // final player stopped/reset before release
 RunLoop.main.run(until: Date().addingTimeInterval(0.45))
 precondition(session.events.last == "off-notify")
 precondition(session.events.filter { $0 == "off-notify" }.count == 1)
 audio.acquire(a) // replay after end
 precondition(Array(session.events.suffix(2)) == ["category", "on"])
 audio.release(a); audio.release(a) // idempotent release/deinit fallback
 RunLoop.main.run(until: Date().addingTimeInterval(0.45))
 precondition(session.events.filter { $0 == "off-notify" }.count == 2)
}
print("PASS executable SHIPPING ownership + manager: no boot activation; exclusive real play; duplicate begin; pause/background preservation; overlapping players; coalesced source replacement; final notify release; replay; duplicate cleanup")
'''
with tempfile.TemporaryDirectory() as tmp:
    f = Path(tmp)/'audio.swift'
    f.write_text(swift)
    subprocess.run(['swift', str(f)], check=True)
