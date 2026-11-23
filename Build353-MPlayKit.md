# Build 353 — MPlayKit playback core (1:1 restoration of the reverse-engineered player kernel)

Delivered by Muse (Kai) for the AVDB project. This package is **unsigned**
(`AVDB-unsigned-1.0.2-353-mplaykit.ipa`).

## Why

The user reverse-engineering brief (2026-11-23): after the 115 player APK
(`115播放器-1.0.0-p115-fix3.apk`, host app HalalCloud Disk Manager) was
statically reverse engineered, the user ordered the player kernel restored
into AVDB: 「全部一比一还原」 — restore it all, one-to-one.

Reverse-engineering sources (read before changing anything in this build):

- `~/workspace/p115-player-re/RE-REPORT.md` — deep report: the real kernel
  is **MPlayKit** (`com.mplaykit`), an obfuscated native facade
  `com.mplaykit.N` (32 native methods n0–n31) over a statically fused
  **libmpv + FFmpeg 8.0** build in `libFFmpegKit.so`, driven through a
  generic raw-command channel (n3) and dual-Surface rendering.
- `~/workspace/p115-player-re/FINDINGS.md` — first-pass findings including
  the 2026-11-23 corrections (the "SenPlayer" name in the APK is an
  unrelated name collision with the commercial player; the kernel IS
  mpv-based, correcting the first-pass "not mpv" claim).

## What this build does

MPlayKit becomes an **optional playback kernel** inside AVDB, side by side
with the existing KSPlayer. `Pan115PlayerView` picks the kernel from a new
Settings picker （播放 → 播放内核）; **KSPlayer remains the default**. The
MPlayKit path plays the same 115 direct links with the same headers.

1. **Native pipeline** (`scripts/mplaykit353/`, CI job `libmpv-353`):
   builds `Vendor/Libmpv.xcframework` (arm64 device + simulator) from
   sha256-pinned sources — FFmpeg **8.0.1**, mpv **0.42.0**, libplacebo
   **7.387.0** (mpv 0.42's hard floor), dav1d **1.5.1**, libass **0.17.4**,
   freetype **2.13.3**, harfbuzz **15.2.0**, fribidi **1.0.16** (matches
   the original build), xxHash **0.8.3**. FFmpeg is configured as a
   decode-only player core (no encoders/muxers/network servers), with the
   tonemap/scale/subtitles filter families the original ships, dav1d for
   AV1, libass for subtitles, and VideoToolbox hardware decoding in place
   of Android's MediaCodec. **待 CI 首跑验证** — this Linux VM cannot
   compile iOS libraries; the pipeline follows mature cross-compile
   practice and its first real run is the `libmpv-353` CI job.
2. **Swift layer** (`AVDB/Services/MPlayKit/`): a libmpv-C-API
   implementation of the MPlayKit interface shape — `MPlayPlayer`
   (handle wrapper, per-instance serial queue ≙ the original's
   single-thread ExecutorService), the raw-command channel with named
   `open`/`select`/`subtitles`/`media` equivalents, `setProp`, async
   seek, State/Progress snapshots aligned to the original's named
   fields and JSON keys, `MPlayPreviewReader` (independent frame-grab
   pipeline ≙ PreviewReader/Still), `MPlayDiagnostics` (structured
   `event=name k=v` log bridge with a ring buffer), and the OpenGL
   render view (`MPlayVideoView`, mpv render API).
3. **Integration**: kernel picker in Settings (UserView), `Pan115PlayerView`
   branches to `MPlayKitPlayerView` when MPlayKit is selected (KSPlayer
   path byte-identical), subtitles render inside mpv via libass.

## MPlayKit → iOS mapping

| Original (Android MPlayKit) | iOS restoration (this build) |
|---|---|
| `System.loadLibrary("FFmpegKit")` fused libmpv+FFmpeg 8.0 `.so` | `Vendor/Libmpv.xcframework`, CI-built, module `Libmpv` |
| `Player` handle + single-thread ExecutorService | `MPlayPlayer` + per-instance serial `DispatchQueue` |
| n5 createPlayer(two Surfaces, options Map, shared ctx) | `MPlayPlayer(options:sharedContext:)` + `MPlayVideoView` (single `CAEAGLLayer`) |
| Creation options (`hwdec=mediacodec`, …) | Same Map shape; `hwdec=videotoolbox` on iOS |
| n30 shared render-context handle | `MPlayRenderContext` (shared `EAGLContext`) |
| n4 derived preload instance | `makePreloadedPlayer()` (warm instance sharing the GL context — see deviations) |
| n3 rawCommand channel | `command(_:)` over `mpv_command` / `mpv_command_async` |
| `open` command (url/start/flags/headers Map) | `open(url:startSeconds:headers:autoplay:completion:)` |
| `select` command | `selectTrack(kind:id:)` → `vid`/`aid`/`sid`/`secondary-sid` |
| `subtitles` command (dual external subs) | `addSubtitle(url:title:language:select:auto:)` via `sub-add` (identifiable subset — see deviations) |
| `media` command (track/codec JSON) | `mediaJSON()` from `track-list` properties |
| n9 pause | `setPaused(_:)` |
| n16 seek + CompletableFuture | `seek(to:completion:)` completing on `MPV_EVENT_PLAYBACK_RESTART` |
| n7 setProp | `setProp(_:_:)` → `mpv_set_property_string` |
| n14 State snapshot (long[23]/double[3]/String[7]) | `state()` (`MPlayState`, named fields) + `stateRaw()` (`MPlayStateRaw`, index-equivalent slots) |
| n15 Progress (JSON keys) | `progress()` (`MPlayProgress` + `jsonObject()`, same key names) |
| n21–n26 PreviewReader / Still | `MPlayPreviewReader` (own mpv core, offscreen FBO, `glReadPixels`) |
| n27–n29 Diagnostics bridge | `MPlayDiagnostics` (ring buffer, `onEntry`, mpv log forwarding) |
| n12 setOutputSize | No explicit API: render size follows the view (`layoutSubviews`) |
| Handle 0 → Java returns −3 | Closed player: mutating calls return `MPlayPlayer.invalidHandleCode` (−3) |

## Deviations （偏差表）

A 1:1 restoration of the *interface and behavior*; the items below are
platform-forced or evidence-forced and are **not** faked as 1:1.

1. **Dual-Surface subtitle plane （双 Surface）.** The original renders
   subtitles on a second Android Surface with its own fp16/HDR strategy
   (vendor options `surface-filter`, `android-subtitle-fp16`). iOS has
   no equivalent dual-Surface concept. Substitute: subtitles are
   rendered by mpv/libass into the same frame as the video on the
   single `CAEAGLLayer`. The two vendor options are not reproduced.
2. **MediaCodec → VideoToolbox.** `hwdec=mediacodec` becomes
   `hwdec=videotoolbox`; `hwdec-software-fallback=yes` keeps its name
   and meaning. TLS likewise: OpenSSL → SecureTransport
   (`--enable-securetransport`), the platform equivalent.
3. **n0 / n8 / n10 / n13 / n18 — not reproduced.** Zero call sites in
   both dexes; semantics unknowable from the binary (RE report §4.1).
   Inventing behavior for them would not be a restoration.
4. **n11 / n17 / n20 / n22 / n27 — no standalone equivalents.**
   Signatures known, semantics unproven (state-poll helper, one-shot
   native action, timebase helper, log-clock helper). Their plausible
   roles are covered by Swift-side mechanisms (`state()` polling,
   `Date`-based log timestamps in `MPlayDiagnostics`).
5. **Unnamed State fields.** Only 9 of the 23 long / 3 double / 7
   string slots were ever named by the Android Bridge. `MPlayStateRaw`
   keeps the slots index-equivalent （只做下标等价）; unnamed slots stay
   zero/empty and are not given invented names or meanings.
6. **`subtitles` command marshalling.** The original marshals 13
   strings + 28 doubles whose per-field layout was not fully named.
   `addSubtitle` implements the identifiable subset (add + select/auto
   flags); the fine numeric fields (delays/scales) are not reproduced
   in the original layout.
7. **Preload derivation (n4).** libmpv has no cross-instance media
   context; `makePreloadedPlayer()` shares only the GL render context
   and warms its own core. Media-context sharing is not reproduced.
8. **Cache maintenance (n2) / string→double helper (n1) /
   `subtitleConversionAvailable` probe / `runtimePermit` command.**
   mpv manages its demuxer cache itself; `Double(_:)` is native in
   Swift; libass is compiled in unconditionally so the capability
   probe is constant; `runtimePermit` is a licensing/quota channel
   with unproven semantics and no place in a self-use app. None are
   reproduced.
9. **Resume/history parity.** The MPlayKit path does not yet wire
   `PlaybackResume` or watch history (the KSPlayer path is untouched);
   `Pan115PlayerView` starts MPlayKit playback at 0. Follow-up work,
   recorded here rather than hidden.
10. **PreviewReader `dolbyProfile`.** No per-frame Dolby Vision profile
    property exists on the mpv side; `MPlayStill.dolbyProfile` is
    always nil. Rotation, duration and cover-art extraction are real.
11. **ncnn.** Present in the original `.so` with no visible purpose in
    the evidence; not introduced.
12. **mpv `avfoundation` AO disabled — UNRESOLVED difference, not an
    accepted deviation.** The original's embedded meson string has
    `-Davfoundation=enabled` and the original fork's ao code compiles
    on iOS; stock mpv 0.42.0's does not (0.41.0 and 0.42.0 alike,
    sources verified): the feature is `auto`, autodetects ON against
    the iOS SDK, and then `ao_avfoundation.m` calls
    `setAudioOutputDeviceUniqueID:`, `API_UNAVAILABLE` on iOS, while
    `HAVE_AVFOUNDATION` un-guards the macOS-only `AudioDeviceID` /
    `AudioStreamID` declarations in `ao_coreaudio_utils.h` /
    `ao_coreaudio_chmap.h`, which `ao_audiounit.m` includes
    unconditionally (CI round 6: 11 errors, all in the
    ao_avfoundation translation unit and its included headers).
    The build therefore sets `-Davfoundation=disabled` explicitly as
    the only currently viable route to a compiling stock mpv;
    `coreaudio` was already disabled, and `audiounit` — the iOS AO —
    stays enabled: everything it calls from the shared headers is
    declared outside that guard, and the shared utils/chmap sources
    compile with both guards off. This item stays open: effect-level
    equivalence (audio output path and perceived sound) is to be
    judged by a same-title on-device A/B against the original
    player, and if it falls short, the iOS-usable parts of the
    original's ao are to be ported following its symbol surface.

## CI first-run checklist （待 CI 首跑验证）

- [ ] `libmpv-353` job: cold build finishes within the 240-minute
      timeout; warm run restores `Vendor/Libmpv.xcframework` from cache
      and skips the build.
- [ ] Release job links `Libmpv.xcframework` (Frameworks + Embed) and
      `xcodebuild` passes: Swift layer compiles against the libmpv C
      API (module `Libmpv`), including the render view and the
      `mpv_node` cache-state parsing.
- [ ] `test-mplaykit353.py` green; full regression failure set identical
      to the Build 352 baseline (51 pre-existing environment failures,
      no new ones).
- [ ] Device: switch Settings → 播放内核 to MPlayKit; a 115 direct link
      plays with headers applied; pause/seek/track switching work;
      embedded and external subtitles render via libass; a failing
      stream surfaces through the existing `vm.failed()` fallback;
      switching back to KSPlayer behaves exactly as before.
- [ ] `MPlayPreviewReader` / `MPlayDiagnostics` have no UI entry point
      yet (layer first, per the restoration brief); verify via logs
      when first wired.

## License note

mpv is GPL-2.0-or-later; FFmpeg in this pipeline is configured
**without** `--enable-gpl` (LGPL core, decode-only), libplacebo is
LGPL-2.1-or-later, and the combined player core is treated as GPL for
distribution purposes — same posture as the existing KSPlayer core
(see `KSPlayer-GPL-3.0.txt` in the repo). Source pins and build
scripts for every native dependency live in `scripts/mplaykit353/`
(`THIRD_PARTY.md` there lists each component, version, source URL,
sha256 and license).
