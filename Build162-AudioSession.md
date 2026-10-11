# Build 162 — Playback audio-session lifecycle

Version: 1.0.2 (162). Baseline: fetched origin/main, 8cc8145 (build 161); no newer remote commit existed at implementation start.

## Cause

AVDBApp.init configured exclusive `.playback`/`.moviePlayback` with empty options and activated AVAudioSession before any media existed. Entering the app could therefore interrupt another app's music/video. KSChromePlayer also activated on appearance, and there was no matching final deactivation. The short Apple trailer constructed an ephemeral AVPlayer in body. KSPlayer itself activates audio in KSAVPlayer/KSMEPlayer construction (and newer dependency revisions also reassert on play), so removing only the startup call would not provide a complete release policy.

## Targeted fix and coverage

- Startup and ordinary browsing never configure or activate the audio session. No `mixWithOthers` workaround.
- One small app-owned, UUID-based ownership manager configures exclusive playback for concrete playback requests. Leases cover shared KSChromePlayer (including PlayerView and 115), and the Apple trailer.
- Shared KS rendering wraps the existing public KSVideoPlayer.Coordinator.makeView API. Ownership starts BEFORE dependency construction, accounting for dependency-side activation without forking or swizzling KSPlayer. Ready/play-button, auto-playing seek, and system remote/PiP resume also acquire ownership.
- KS player destruction pauses and resets the underlying coordinator before releasing. Natural completion and terminal failure pause and release as well; replay reacquires. Item/source replacement preserves the same lease where possible. A 350 ms generation-checked idle grace coalesces `.id(url)` replacement, so overlapping old/new children do not cause deactivate/reactivate flutter.
- The Apple trailer now has stable AVPlayer storage and the same native AVKit controls, hosted by AVPlayerViewController instead of the SwiftUI VideoPlayer convenience wrapper. Waiting/playing (not construction or appearance) acquires ownership. Completion, load/play failure and final teardown stop/release it. AVKit delegate state retains legitimate detached PiP playback until PiP ends.
- `onDisappear` only cancels UI gesture/ticker work; it does not pause or release audio. LUT presentation, temporary covering, switching background, and legitimate PiP are not terminal boundaries. KS detached PiP retention uses the system controller's actual active flag, not the dependency's potentially stale requested-PiP flag.
- Explicit pause retains its lease while the playback route/item remains alive. This deliberately preserves immediate resume, buffering, interruptions and background/PiP semantics; pause is not claimed to mean final stop. Final exit/finish/failure releases. When the last owner ends, `setActive(false, options: .notifyOthersOnDeactivation)` notifies other apps; bounded retries log any system refusal.

Build 161 gesture recognizer/state implementation is unchanged. Left brightness/right system-volume adjustment, seek/double-tap, LUT, source/quality/episode controls, 115 protocol and orientation behavior remain covered by their existing regressions. No real account mutation is involved.

## Validation and limits

`scripts/test-audio-session.py` checks startup and playback integration boundaries and executes the SHIPPING pure ownership policy plus session manager against a recording AVAudioSession on macOS CI. It checks no boot activation, exclusive play, duplicate begin, retained pause/background ownership, overlapping players, coalesced replacement, final notify release, replay, and duplicate cleanup. Existing layout, gestures, CoreImage/LUT, MediaPipe and 115 tests remain in the IPA workflow.

This Linux/iSH environment cannot execute Swift/UIKit or install and exercise the resulting iOS app. Local source contracts can pass here; Swift executable tests and full iOS Release compilation run on macOS CI. CI/test success does not establish real-device external-music behavior. Device acceptance is still required: play music in another app, launch/browse AVDB, start media, pause/resume, replace quality/source/episode, open/close LUT, background/PiP, finish/exit the last player, test trailer load failure and replay. Other apps decide whether to resume after the notification; AVDB cannot promise automatic resumption. Process kill/crash is ultimately subject to iOS audio-session cleanup.
