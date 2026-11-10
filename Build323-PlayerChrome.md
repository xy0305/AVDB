# Build 323 — 播放页样式（参考截图）

Base: Build 322 / 7d0af2a, `feat/zzt-ranking-322` (unmerged). MARKETING 1.0.2, build 323.

Player chrome (`KSChromePlayer.chromeOverlay` / `progressBar`, `LiveSubtitleMenuButton` label) restyled after the
reference screenshot — thin white line icons and plain white text over a light top/bottom scrim; no capsules,
glass or dark fills. Only AVDB's own functions are shown.

- Top: ✕, one-line truncated title, then 在线字幕 / LUT（按住看原图）/ 画面与方向 icons. LUT-on is a small dot under the icon.
  Not copied: home, AirPlay, 弹幕, folder, clapper, rotate, audio tracks, comments, headphones, logo, watermark.
- Download speed (top-right) only from real `AVPlayerItem.accessLog()` `numberOfBytesTransferred` deltas over a 2 s
  window (`PlaybackThroughputSampler`); hidden for KSMEPlayer / local files / no log. Never encoded or indicated bitrate.
- Progress: `01:02` — thin 3 pt track with a small dot — `2:36:31`; no glass capsule wrapper. The native Slider stays on top
  (near-transparent) so drag, tap-to-seek, seek preview, accessibility and `player.progress` are unchanged.
- Bottom-left: play/pause only. The dedicated +10 s button is removed (double-tap skip stays). No fake next button.
- Bottom-right plain text: 实时字幕 menu, online quality status, 播放源 (e.g. 1080P), 选集, 倍速.
- New 倍速 menu 0.5/0.75/1.0/1.25/1.5/2.0 → `coordinator.playerLayer?.player.playbackRate`, id `player.playback.rate`;
  re-applied on readyToPlay and each tick so a replaced item keeps the session choice.
- Identifiers, 48 pt LUT target, `chromeOverlay.zIndex(10)`, gesture exclusions (top +80 / bottom +116) unchanged.
- `glassButton` / `capsuleButton` helpers removed; `scripts/test-progress-tap277.py` now splits at `applyFillMode`.

Tests: `scripts/test-player-chrome323.py` (static; executes the sampler on macOS); version asserts → 323;
`scripts/package-lut323.py` → `AVDB-unsigned-1.0.2-323-player-chrome.ipa`; workflow artifacts `AVDB-323-*`.
