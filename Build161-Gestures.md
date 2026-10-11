# AVDB 1.0.2 (161): Build10-style reliable landscape pan

## Baseline and playback coverage

Default remote branch is `main`, audited at `6bc01095ac307776b46318cfddaf157828228db1` (project/plist build160). Work was isolated from historical AVDB working trees. Reference: Pornhub main `eaced71`, Docs/Build10.md, PHAdjustmentPan and its executable tests; KSPlayer 2.3.4 SwiftUI/Video/IOSVideoPlayerView and ZFPlayer `1ede0b9` reviewed as implementation evidence, not copied as a replacement player.

AVDB uses `KSChromePlayer` for its JavDB stream `PlayerView` and for `Pan115PlayerView`: 115 transcoded sources, original file URLs and episode/source replacement all enter the same native KSVideoPlayer layer and chrome. Only this shared player's gesture integration changed; no login, offline, filesystem, API, source selection or episode business code was changed. The detail-page short trailer uses the existing separate Apple `VideoPlayer` and intentionally retains its standard controls; it is not the full-feature movie route and was not replaced.

Unlike PH's IOSVideoPlayerView, AVDB uses KSVideoPlayer's SwiftUI representable, which returns the underlying player view, not the official chrome with its official pan. Keep AVDB's one overlay UIPanGestureRecognizer and one output target; do not install a second official/app pan or remove unrelated targets. Native LUT, chrome, fullscreen/portrait menu, rate, PiP/background hooks, quality selection, 115 headers and item replacement stay intact. No dependency upgrade.

## Semantics

- Original touchdown (shouldReceive) determines left brightness/right route volume; crossing center later does not change it. Maximum one touch.
- Production `AVDBAdjustmentPan` waits for >=6pt and a 1.15 dominant axis, not a one-shot shouldBegin displacement/velocity rejection. Axis remains locked. Consume all displacement before lock so lock itself does not jump.
- Landscape vertical increment = previous requested value minus incremental y / max(180, height*0.8), clamped each event. Immediate reversal at either limit; independent of event frequency away from saturation. Paused/buffering are not gates.
- Brightness uses public UIScreen for the player's actual window screen. Right-side initial value is AVAudioSession.outputVolume, including legitimate zero; never use an unready slider as starting volume.
- MPVolumeView is 100x44, alpha 1, nonhidden, placed outside the visible player bounds in its live scene hierarchy before first touch. Require window attachment and enabled UISlider; submit with public setValue and valueChanged only. No private class lookup, KVC or private volume API. Missing/unavailable control displays a hardware-button fallback, not a fabricated percentage success.
- **Important boundary:** MPVolumeView's internal UISlider hierarchy is not an Apple-documented stable programmatic system-volume interface. Public UIKit operations on that hierarchy are a common best-effort adapter, not a guaranteed volume setter. Fixed-volume/AirPlay/Bluetooth routes, OS changes or control lifecycle may prevent effect even when an event is submitted. The HUD displays the requested percentage, not independently verified hardware output.
- Existing chrome and top72/bottom108 control exclusion stay above the receiver; UIControl ancestors are excluded. Progress slider remains native. All adjustment/seek/error HUDs and loading indicator ignore touches.
- Horizontal retains AVDB's 0.35 sec/pt (0.55 for >1h) bounded seek preview, with lock travel consumed. Only normal end commits seek; cancel/failed/window removal/bounds change/rotation/resign-active/source replacement cancels preview. Already submitted brightness/volume values are not rolled back.
- Slider/seek-pending/LUT-sheet conflict blocks new pan; own horizontal preview can continue. Async seek uses a generation guard to prevent stale completion clearing a newer request; source/lifetime reset invalidates pending state. Existing seek autoPlay policy retained.

## Tests and delivery boundaries

`scripts/GestureRegression.swift` compiles and executes the actual shipping AVDBAdjustmentPan in macOS CI, not a reimplementation. Covers slow-start threshold/diagonal, half/axis lock and center boundary, consumed travel, event rate equivalence, both clamp reversals, zero initial volume, horizontal preview and cancelled reset/rebegin, rotation/invalid dimensions. `scripts/test-player-gestures.py` additionally guards receiver integration and single-output architecture. Build IPA workflow runs these before the existing LUT/CoreImage/115/MediaPipe regressions and unsigned iphoneos Release build. Corrected stale build159 test expectation to the new consistent project/plist build161.

Local Linux executes source-contract and available Python fixture tests; CoreGraphics/CoreImage Swift tests require macOS and are explicitly skipped locally, then executed by CI. No new synthetic system-volume UI test is represented as real device validation. Existing unrelated Simulator poster navigation tests are not a gesture/hardware acceptance test.

No real-account writes or credential changes performed. No physical-device brightness, speaker/headphone/Bluetooth/AirPlay system volume, live playback, real PiP/background or lock-screen acceptance claimed. Those require manual device/route validation. Unsigned IPA requires user signing before installation.
