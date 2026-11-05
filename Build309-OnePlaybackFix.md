# Build 309 — ONE 播放修复（死主机自动换线）

User report (2026-11-05): ONE 播放失败，播放器报错
`su0220vd.3ca7yj.com · 播放：失败（原因未确定）（系统码 2）[KSPlayerErrorDomain]`。

## Diagnosis (live-verified before changing code)

Replicated the ONE protocol in Python (guest bootstrap, app-version 1.6.0),
took a current detail (`video_download` is a path, H.265 MP4, ~500 MB), and
fetched the same path from every issued CDN host group:

- `video` group hosts (46e9nz.mfpt8g.com, f86xxm.upmf83.com): **206, video/mp4, ftyp** ✓
- flutter_video_download (ftdlmk.t556wzr.com): 206 ✓
- vd.qmq85ps.com: 206 via curl (but see the fragility note below)
- vd.47d1fc4.com: **404** (host up, file not there)
- **su0220vd.3ca7yj.com (the host in the user's error): 502 Bad Gateway** — dead upstream

So the file itself is fine; the one host the player happened to start on is
dead. Two structural weaknesses in the Build 308 port made that fatal:

1. Playback used exactly one line; a failed open dead-ended on the KSPlayer
   error screen even though the same file was reachable on sibling hosts.
2. The guest session (token + CDN domain tables) was persisted forever, so
   lines kept being built from a stale domain table while hosts rotate/die.
   (The original script also documents that `vd.*` hosts only complete the
   TLS handshake under the official app's fingerprint — ffmpeg-based players
   fail on them — yet a `vd.*` host could still land first if the server
   issued it inside a preferred group.)

## Change

- `OneView.swift` — `OnePlayback` now carries the full line list + index.
  `KSChromePlayer` gets an `onPlaybackFailure` handler: on open failure (or
  the player's 30 s no-start watchdog) the cover re-presents with the next
  line until the list is exhausted; only then does the player's own error
  UI remain. Hero/play-bar taps start at line 1 with the full list; line
  rows start at the tapped line and fall forward from there.
- `OneCore.swift` — `videoHosts()` keeps the script's group order
  (video → flutter_video_download → flutter_video_play → audio_download →
  audio) but demotes any `vd.*` host behind non-`vd.*` hosts, so the first
  lines always land on the stable CDN class.
- `OneCore.swift` — the persisted session now records a save timestamp;
  `bootstrap(force: false)` re-bootstraps when the stored session is older
  than 24 h, refreshing the token and the CDN domain tables. 308-era
  sessions (no timestamp) refresh once on first use.

## Not changed

- ONE sections, classification, search, history routing, covers.
- HLS lines stay labelled fallback-only (encrypted manifests).
- Guest-only access: content the service reserves for logged-in accounts
  (e.g. full live replays) still yields preview-only lines.
