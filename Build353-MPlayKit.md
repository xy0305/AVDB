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
- `~/workspace/p115-player-re/IOS-FINDINGS.md` — the iOS SenPlayer
  (6.4.0) symbol-level findings: the original iOS binary is mpv
  **0.41.0** (`-Dgl=disabled`, uchardet, lcms2, `avfoundation=enabled`),
  displayed through a self-built `frame_output` vo pixel-frame pipeline
  (CVPixelBuffer → CMSampleBuffer → AVSampleBufferDisplayLayer, no GL),
  with a Metal post chain and a spatial-audio line.

**Sync note (2026-11-24):** the Swift layer in this build is synced from
the AVFan Build 59 full-restoration layer, which is the same restoration
verified end to end — AVFan CI run 45239463298 all green, artifact
`AVFan-unsigned-112` (14,612,310 bytes, valid to 2026-12-08 02:55 CST).
Apart from the renames listed in §"Sync from AVFan Build 59", the layer
is copied verbatim; no logic was re-derived here. AVDB keeps its
dual-kernel switch (KSPlayer default, MPlayKit optional); AVFan is a
hard kernel swap, so the AVFan chrome/integration was **not** copied —
only the App-independent layer under `AVDB/Services/MPlayKit/`.

## What this build does

MPlayKit becomes an **optional playback kernel** inside AVDB, side by side
with the existing KSPlayer. `Pan115PlayerView` picks the kernel from a new
Settings picker （播放 → 播放内核）; **KSPlayer remains the default**. The
MPlayKit path plays the same 115 direct links with the same headers.

1. **Native pipeline** (`scripts/mplaykit353/`, CI jobs `libmpv-353` /
   `spatial-353`, synced by the pipeline lane): builds
   `Vendor/Libmpv.xcframework` (arm64 device + simulator) from
   sha256-pinned sources — FFmpeg **8.0.1**, mpv **0.41.0** (the original
   iOS binary's version string, direct evidence; an earlier revision of
   this pipeline pinned 0.42.0), libplacebo **7.387.0**, dav1d **1.5.1**,
   libass **0.17.4**, freetype **2.13.3**, harfbuzz **15.2.0**, fribidi
   **1.0.16**, xxHash **0.8.3**, uchardet **0.0.8**, lcms2 **2.16**.
   FFmpeg is configured as a decode-only player core (no
   encoders/muxers/network servers), with the tonemap/scale/subtitles
   filter families the original ships, dav1d for AV1, libass for
   subtitles, and VideoToolbox hardware decoding in place of Android's
   MediaCodec. GL is fully off (`-Dgl=disabled`, matching the original):
   a vendored patch adds the private `frame_output` vo
   (`patches/0001-vo-frame-output.patch` + colorspace/repr-levels
   follow-ups); libplacebo keeps no graphics API backend
   (`-Dvulkan=disabled -Dopengl=disabled`, Vulkan-Headers vendored
   because `stubs.c` still includes `vulkan.h`). **待 CI 首跑验证** —
   this Linux VM cannot compile iOS libraries; the pipeline follows
   mature cross-compile practice and its first real run is the
   `libmpv-353` CI job. The spatial job (`scripts/mplaykit353/
   build_spatial.py`) additionally produces `Vendor/TrueHD.xcframework`
   (static, link-only) and `Vendor/DTSX.xcframework` (dynamic, link +
   embed) from the pinned LibTrueHD / LibDTSX commits.
2. **Swift layer** (`AVDB/Services/MPlayKit/`, 24 files +
   `Spatial/`): a libmpv-C-API implementation of the MPlayKit interface
   shape, in four stages — **A** pixel-frame display pipeline
   (`MPlayFrameOutput`, `MPlayVideoView` on `AVSampleBufferDisplayLayer`,
   independent subtitle layer `MPlaySubtitleLayer`), **B** picture-in-
   picture (`MPlayPictureInPicture`), **C** Metal post chain + Dolby
   Vision (`MPlayPostChain.metal/.swift`, `MPlayDolbyVision`), **D**
   spatial audio + preload takeover + cache policy (`MPlaySpatial`,
   `MPlaySpatialRender`, `Spatial/MPlaySpatialBridge.c/.h`,
   `MPlayCachePolicy`) — plus the core (`MPlayPlayer`,
   `MPlayPlayerExtras` for the original Player's 99-method surface,
   `MPlayState`, `MPlayDiagnostics`, `MPlayPreviewReader`,
   `MPlayStreamProtocol` + `MPlayStreamBridge.c/.h`,
   `MPlaySubtitles`, `MPlayNowPlaying`, `MPlayDisc`,
   `MPlayAudioPolicy`, `MPlayCapture`), a bridging header
   (`AVDB/AVDB-Bridging-Header.h`, the app's only bridging surface,
   exposing the two C bridges to Swift), and the dual-kernel descriptor
   (`MPlayKernel.swift`, AVDB's own version — see below). The old GL
   render view (`MPlayVideoView` on `CAEAGLLayer`) and
   `MPlayRenderContext` (shared `EAGLContext`) are **deleted**; there
   is no GL anywhere in the display chain anymore.
3. **Integration**: kernel picker in Settings (UserView), `Pan115PlayerView`
   branches to `MPlayKitPlayerView` when MPlayKit is selected (KSPlayer
   path byte-identical), subtitles render inside mpv via libass. The
   MPlayKit chrome is minimal (top close + title, bottom play/pause +
   seek); PiP / NowPlaying / post-chain switches / preload / subtitle
   UI are **not** wired to it yet — the layer exposes them, the chrome
   does not (see "Differences from the AVFan verified build").

## Sync from AVFan Build 59

Source: `~/workspace/avfan-work/AVFan/Services/MPlayKit/` (24 files +
`Spatial/`), as verified by AVFan run 45239463298. What changed on the
way into AVDB — and nothing else:

- `MPlayKernel.swift` **not** copied. AVDB keeps its own dual-kernel
  version (`PlaybackKernel.ksPlayer` default + `.mplayKit` optional,
  `PlaybackKernelSettings.defaultsKey = "avdb.playback.kernel"`).
  AVFan's file is a single-case descriptor (no switch at all).
- File headers: `AVFan` → `AVDB`, `Build 59` → `Build 353`
  (provenance stays in this document and in four in-body notes
  marked "AVFan Build 59 扩展，已同步").
- Queue labels `avfan.mplaykit.*` → `avdb.mplaykit.*`; UserDefaults
  keys `avfan.mplaykit.post.*` → `avdb.mplaykit.post.*`;
  `frameSinkName` prefix `avfan-` → `avdb-`.
- Two comment rewordings where AVFan named a host type AVDB does not
  have in that role: `MPlayChromeCoordinator` → the AVDB chrome/view
  wording (`MPlayVideoView.pictureInPictureController`,
  `promotePreloadedPlayback`); `PlaybackAudioLease` ownership is
  noted as the KSPlayer path's lease, not the MPlayKit path's.
- `Spatial/truehd_atmos.h` / `dtsx.h` copied byte-identical (vendored
  upstream headers, unmodified); `Spatial/UPSTREAM.md` repointed from
  `scripts/mplaykit59/` to `scripts/mplaykit353/`.
- `AVDB/AVDB-Bridging-Header.h` added (AVFan's
  `AVFan-Bridging-Header.h` adapted): the C bridges need it — without
  it Swift cannot see any `mplay_*` function. Set as
  `SWIFT_OBJC_BRIDGING_HEADER` in both Debug and Release configs.
- pbxproj: 26 new fileRefs (`MPLAY353…0074`–`…0099`), 21 new buildFiles
  (`…0100`–`…0120`), `Spatial` group (`…0121`); `MPlayRenderContext`
  fileRef/buildFile removed; TrueHD link-only, DTSX link + embed
  (AVFan pattern, see `scripts/mplaykit353/LINK-NOTES.md` §4).
  Verified by script (parenthesis balance, no duplicate IDs, every new
  fileRef has its buildFile, group children and Sources phase complete).
- Verification done on this Linux VM (no Xcode/Swift toolchain):
  every symbol `MPlayKitPlayerView` / `Pan115PlayerView` calls exists
  in the new layer with a compatible signature
  (`MPlayPlayer()` default init, `open(url:startSeconds:headers:
  autoplay:completion:)`, `setPaused`, `seek(to:)`, `close()`,
  `state()`, `progress()`, `MPlayVideoView.attach(player:)` /
  `detach()`); every `MPlay*` / `mplay_*` token used in the layer's
  code is defined in the layer, in the two C bridges (exposed via the
  bridging header), or in AVDB's own `MPlayKernel.swift`; no top-level
  type in the layer collides with an existing AVDB type; no
  `MPlayRenderContext` / `vo=libmpv` / GL reference remains in code
  (one historical note in `MPlayVideoView.swift`'s header, marked as
  retired). Compilation itself is **待 CI 首跑验证**.

## MPlayKit → iOS mapping

| Original (Android MPlayKit / iOS SenPlayer) | iOS restoration (this build) |
|---|---|
| `System.loadLibrary("FFmpegKit")` fused libmpv+FFmpeg 8.0 `.so` | `Vendor/Libmpv.xcframework`, CI-built, module `Libmpv` (mpv 0.41.0) |
| `Player` handle + single-thread ExecutorService | `MPlayPlayer` + per-instance serial `DispatchQueue` |
| n5 createPlayer(two Surfaces, options Map, shared ctx) | `MPlayPlayer(options:cachePolicy:)`; no shared ctx (see deviations) |
| Creation options (`hwdec=mediacodec`, …) | Same Map shape; `hwdec=videotoolbox` on iOS |
| n30 shared render-context handle | **No equivalent**: frame_output sink routes frames by name (`frameSinkName`); instances share no render state |
| n4 derived preload instance | Full-instance takeover: `promotePreloadedPlayback` + view/PiP rebind (stage D) |
| n3 rawCommand channel | `command(_:)` over `mpv_command` / `mpv_command_async` |
| `open` command (url/start/flags/headers Map) | `open(url:startSeconds:headers:autoplay:completion:)` |
| `select` command | `selectTrack(kind:id:)` → `vid`/`aid`/`sid`/`secondary-sid` |
| `subtitles` command (dual external subs) | `subtitles(primary:secondary:)` / `addSubtitle` via `sub-add` (identifiable subset — see deviations) |
| `media` command (track/codec JSON) | `mediaJSON()` from `track-list` properties |
| n9 pause | `setPaused(_:)` |
| n16 seek + CompletableFuture | `seek(to:completion:)` completing on `MPV_EVENT_PLAYBACK_RESTART` |
| n7 setProp | `setProp(_:_:)` → `mpv_set_property_string` |
| n14 State snapshot (long[23]/double[3]/String[7]) | `state()` (`MPlayState`, named fields) + `stateRaw()` (`MPlayStateRaw`, index-equivalent slots) |
| n15 Progress (JSON keys) | `progress()` (`MPlayProgress` + `jsonObject()`, same key names) |
| n21–n26 PreviewReader / Still | `MPlayPreviewReader` (own mpv core, SW render API, `MPlayPreviewReaderConfiguration`, `metadata()`, real `dolbyProfile`) |
| n27–n29 Diagnostics bridge | `MPlayDiagnostics` (ring buffer, `onEntry`, mpv log forwarding, single-message `log(_:)` overload) |
| n12 setOutputSize | No explicit API: render size follows the view; display matching is iOS `CADisplayLink` frame-rate range (see deviations) |
| Frame output vo (`frame_output`, original iOS) | Vendored mpv patch + `MPlayFrameOutput` (FrameStore / scheduler, video + subtitle channels) + `AVSampleBufferDisplayLayer` view |
| Dual-Surface subtitle plane | Independent subtitle `CALayer` (`MPlaySubtitleLayer`), render size decoupled from video size |
| PiP (original iOS, SampleBuffer chain) | `MPlayPictureInPicture` (content source, playback + controller delegates, audio-interruption recovery, PiP subtitle render size) |
| Metal post chain (SDR→HDR / upscaling / interpolation / DV P5) | `MPlayPostChain.metal` + `.swift` (own shaders — architecture/positions match, shader contents are ours, see deviations) |
| Dolby Vision RPU / Profile 5 | `MPlayDolbyVision` (`MPlayDoviRPU` per FFmpeg 8.0.1 `dovi_rpudec.c`; P5 constants are public BT.2124 IPT matrices, not the original's baked constants) |
| Spatial audio (TrueHD / DTS:X object audio, APAC → AVPlayer) | `MPlaySpatial` + `MPlaySpatialRender` + `Spatial/` bridge to pinned LibTrueHD / LibDTSX; APAC gated iOS 26 (see deviations) |
| `registerStreamProtocol` | `MPlayStreamProtocol` + `MPlayStreamBridge.c/.h` (`mpv_stream_cb_add_ro`) |
| Subtitle translation / live subtitles | Pipeline + API landed (`MPlaySubtitles`); **no translation backend ships** — without an injected provider the entry points return -18 |
| NowPlaying / remote control | `MPlayNowPlaying` (layer only — not wired to AVDB chrome yet) |
| VideoToolbox fault switching | `beginDecoderSwitch` / `recoverVideoToolbox` (result judged observationally via `hwdec-current`) |
| Disc playback | `MPlayDisc` API landed; body blocked (libbluray/dvdnav not in the pipeline) |
| Capture / screenshot | `MPlayCapture` on `MPlayVideoView` (frame store is the view's, not the Player's) |
| Player 99 public methods | `MPlayPlayerExtras` (transport/open/property/state/track/subtitle/post-chain/PiP/preview families; CoreOption/CoreProperty/CoreCommand/CoreCustom vocabularies not mirrored) |
| Handle 0 → Java returns −3 | Closed player: mutating calls return `MPlayPlayer.invalidHandleCode` (−3) |

## Deviations （偏差表）

A 1:1 restoration of the *interface and behavior*; the items below are
platform-forced or evidence-forced and are **not** faked as 1:1. Status
words follow the AVFan Build 59对照表： **landed** = 代码落地；
**partial** = 主体落地但有明示缺口；**blocked** = 做不到且证据在案。
Items marked "AVDB:" are AVDB-specific; the rest are shared with the
AVFan verified build.

1. **Dual-Surface subtitle plane （双 Surface）— superseded.**
   The original renders subtitles on a second Android Surface with its
   own fp16/HDR strategy (vendor options `surface-filter`,
   `android-subtitle-fp16`). iOS has no equivalent dual-Surface
   concept. The restoration does **not** fake one: subtitles travel
   the vo subtitle channel as libass bitmaps and are composited on an
   independent `CALayer` (`MPlaySubtitleLayer`, stage A) with its own
   render size. The two vendor options are not reproduced.
2. **MediaCodec → VideoToolbox.** `hwdec=mediacodec` becomes
   `hwdec=videotoolbox`; `hwdec-software-fallback=yes` keeps its name
   and meaning. TLS likewise: OpenSSL → SecureTransport
   (`--enable-securetransport`), the platform equivalent.
3. **n0 / n18 — not reproduced.** Zero call sites in both dexes;
   semantics unknowable from the binary (RE report §4.1). Inventing
   behavior for them would not be a restoration. (Old wording that
   also listed n8/n10/n13 here is **withdrawn**: those three now have
   formal iOS counterparts — the property family in
   `MPlayPlayerExtras`, `intProperty` / `doubleProperty` /
   `stringProperty` / `setOption` / `configure`.)
4. **n11 / n17 / n20 / n22 — no standalone equivalents.** Signatures
   known, semantics unproven (state-poll helper, one-shot native
   action, timebase helper). Their plausible roles are covered by
   Swift-side mechanisms (`state()` polling, `Date`-based log
   timestamps in `MPlayDiagnostics`). n27 **is** reproduced — it is
   the diagnostics bridge (`MPlayDiagnostics`), not an orphan.
5. **Unnamed State fields.** Only 9 of the 23 long / 3 double / 7
   string slots were ever named by the Android Bridge. `MPlayStateRaw`
   keeps the slots index-equivalent （只做下标等价）; unnamed slots stay
   zero/empty and are not given invented names or meanings.
   `MPlayProgress` gains the verified `cacheSpeed` field (mpv
   `cache-speed`); a 0 reading hides the throughput label, as before.
6. **`subtitles` command marshalling.** The original marshals 13
   strings + 28 doubles whose per-field layout was not fully named.
   `addSubtitle` / `subtitles(primary:secondary:)` implement the
   identifiable subset (add + select/auto flags, `sid` /
   `secondary-sid`, `sub-delay` / `secondary-sub-delay`); the fine
   numeric fields (delays/scales) are not reproduced in the original
   layout. Secondary-track styling has no mpv property — recorded
   only. Subtitle edge processing (AVKit text-style concept) has no
   libass equivalent — recorded + logged only (**blocked**).
7. **Preload derivation (n4) — superseded.** Full-instance takeover
   is landed (`promotePreloadedPlayback` + view/PiP rebind, stage D);
   what is **not** reproduced is media-context sharing — libmpv has
   no cross-instance media context. **AVDB:** no caller wires a
   preload target yet; the layer API exists, the chrome does not use
   it.
8. **Cache policy (n2) — landed with our own numbers.**
   `MPlayCachePolicy` reproduces the original's field names verbatim
   (capacity/directory/prefetchBytes/seconds/segmentBytes/segments);
   the values (96×4MiB=384MiB / 32MiB / 120s) are ours — the original's
   numbers are code constants and unrecoverable, not impersonated.
   `runtimePermit` is a licensing/quota channel with unproven
   semantics and no place in a self-use app — not reproduced.
   `subtitleConversionAvailable` is constant (libass is compiled in).
9. **Resume/history parity — still open (AVDB).** The MPlayKit path
   does not yet wire `PlaybackResume` or watch history (the KSPlayer
   path is untouched). The layer itself now supports it:
   `open(startSeconds:)` applies mpv's `start` property, and
   `MPlayKitPlayerView` forwards its `startSeconds`; `Pan115PlayerView`
   currently passes the default 0 because no resume position is
   computed at that call site. Wiring it is follow-up work, recorded
   here rather than hidden.
10. **PreviewReader `dolbyProfile` — landed (old "always nil" withdrawn).**
    `MPlayStill.dolbyProfile` is now a real `Int` (0 = non-DV), read
    from the track-list `dolby-vision-profile` sub-property (mpv 0.41
    `player/command.c` direct evidence). Rotation, duration and
    cover-art extraction are real. The SW-render path reads top-down;
    no row flip is needed.
11. **ncnn.** Present in the original `.so` with no visible purpose in
    the evidence; not introduced.
12. **mpv `avfoundation` AO disabled — UNRESOLVED difference, not an
    accepted deviation.** The original's embedded meson string has
    `-Davfoundation=enabled` and the original fork's ao code compiles
    on iOS; stock mpv 0.41.0's does not (0.41.0 and 0.42.0 alike,
    sources verified): the feature is `auto`, autodetects ON against
    the iOS SDK, and then `ao_avfoundation.m` calls
    `setAudioOutputDeviceUniqueID:`, `API_UNAVAILABLE` on iOS, while
    `HAVE_AVFOUNDATION` un-guards the macOS-only `AudioDeviceID` /
    `AudioStreamID` declarations in `ao_coreaudio_utils.h` /
    `ao_coreaudio_chmap.h`, which `ao_audiounit.m` includes
    unconditionally (AVDB CI round 6: 11 errors; AVFan CI round 6: 10
    errors, all in the `ao_audiounit.m` translation unit and its
    included headers). The build therefore sets
    `-Davfoundation=disabled` explicitly as the only currently viable
    route to a compiling stock mpv; `coreaudio` was already disabled,
    and `audiounit` — the iOS AO — stays enabled: everything it calls
    from the shared headers is declared outside that guard, and the
    shared utils/chmap sources compile with both guards off. This item
    stays open: effect-level equivalence (audio output path and
    perceived sound) is to be judged by a same-title on-device A/B
    against the original player, and if it falls short, the iOS-usable
    parts of the original's ao are to be ported following its symbol
    surface.
13. **Metal post chain — landed (architecture-equivalent, effects not
    claimed identical).** SDR→HDR, spatial upscaling (Lanczos-2),
    frame interpolation (block-matching motion estimation) and the P5
    kernel are our own shaders in the original's pass positions; the
    original's compiled `sdr-hdr-*.metallib` was never decompiled.
    HDRVivid is **partial** (switch surface in place, no independent
    Vivid curve). Deinterlacer / MetalPreviewScaler are **blocked**
    (no interlaced source path; PreviewReader uses mpv's SW scaler).
14. **FEL dual-layer composition — blocked.** The original fork has
    `demux/dovi_split.c` / `f_dovi_rpu` / BSF dependencies, and its own
    logs show fallback to base-layer rendering when the BSF is
    unavailable; stock mpv 0.41 + stock FFmpeg have no such chain.
    FEL *marking* is landed (`dovi-fel` flags, `setDolbyVisionFELHardwareDecode`).
    DV RPU parsing is a landed component (`MPlayDoviRPU`, checked field
    by field against FFmpeg 8.0.1 `libavcodec/dovi_rpudec.c`), but the
    player does not feed raw RPU bytes — the mpv client API does not
    export them; the parser consumes host-supplied RPU data.
    P5 correction constants are public BT.2124 IPT matrices, **not**
    the original's baked constants (unextracted, needs disassembly).
15. **Spatial audio live feed — blocked (gap stated plainly).**
    Decoders (TrueHD / DTS:X via the pinned libs), object rendering
    (our own nearest-three-speakers model, not claimed equal to the
    original's panner), APAC encoding → in-process HLS → AVPlayer
    (iOS 26 gate) are all landed and callable, but **no live mpv
    playback feeds them**: that needs the original's self-built
    `audio_relay` ao-level component, which stock mpv does not have.
    The 7.1 PCM fallback (`MPlayAudioRelay`) is in place. Silent-Atmos
    keep-alive is **partial** (activator landed but lazy: the silent
    sample is generated CI-side from the pinned AetherEngine repo and
    is inert when absent from the bundle). **AVDB:** `MPlaySpatial*`
    is linked (TrueHD/DTSX in Frameworks/Embed) but no playback path
    feeds it yet.
16. **Subtitle translation — partial.** Pipeline and API are landed
    (SRT per-cue translation, translated file `sub-add`, translation
    track registry, live-subtitle snapshot with simplified/traditional
    handling); **no translation backend or credential ships in AVDB**,
    so without an injected provider the entry points return -18.
    File-based tracks only (the actual shape of AVDB online subtitles);
    embedded tracks cannot be translated this way. Simplified/
    traditional conversion uses a compact table (~140 pairs, spot-
    checked) — **not** a full OpenCC dictionary, partial by
    construction.
17. **Disc playback — partial (body blocked).** `MPlayDisc` session API
    + `mediaInfo` disc block are real; the body is blocked because the
    pipeline does not bring in libbluray/dvdnav — a disc source fails
    inside mpv and the failure surfaces through completion honestly.
18. **Display matching — partial.** State surface + generation
    invalidation are landed; the applied form is iOS's `CADisplayLink`
    `preferredFrameRateRange` (ProMotion) — tvOS's `AVDisplayCriteria`
    has no iOS counterpart. Color handling relies on the system's
    treatment of the display layer.
19. **PiP details — partial.** Entry/exit/sync/transfer are landed;
    subtitle *migration* is render-size migration only (sample-buffer
    PiP hands the app no host view); `preparePictureInPictureForExit`
    / `invalidatePictureInPicturePlaybackState` /
    `resetPictureInPictureController` /
    `restorePictureInPictureAfterForeground` have no four independent
    methods — their semantics are covered by stop/unbind/rebind and
    the interruption-recovery path. **AVDB:** the PiP controller exists
    in `MPlayVideoView`, but the minimal chrome has no PiP button, so
    PiP is not reachable from the UI yet.
20. **Player 99-method surface — landed except the vocabulary types.**
    `CoreOption` / `CoreProperty` / `CoreCommand` / `CoreCustom` are
    code-generated full vocabularies in the original; they are
    **blocked** (not mirrored) — the layer is a hand-written subset
    plus the generic `setProp` / `command` channels, functionally
    reachable. `stopRendering` / `restoreDisplayFrame` are **partial**
    (render stop = view detach; restore has no corresponding state and
    returns false, documented). `configureManagedTracks` /
    `setPreloadedTrackOptionsProvider` are **partial** (cache re-apply
    landed; no standalone API landing).
21. **No-landing items (evidence on file, not reproduced).**
    `AppleSession` (only handle + fileAccess ivars, role undetermined);
    `CoreRenderView` (role undetermined from the symbol surface);
    `runtimePermit` (no such symbol on the iOS side at all);
    libavdevice input (original meson enabled, ours not — no
    device/disc source demand).

## Differences from the AVFan verified build

| Aspect | AVFan Build 59 (verified) | AVDB Build 353 (this build) |
|---|---|---|
| Kernel selection | Hard swap: MPlayKit is the only kernel, no switch | Dual kernel: KSPlayer default, MPlayKit optional via Settings （播放 → 播放内核）; `MPlayKernel.swift` kept as the AVDB dual-kernel descriptor |
| Chrome | `MPlayChromePlayer` (full chrome: resume/speed/PiP/subtitles/NowPlaying wired) | `MPlayKitPlayerView` minimal chrome (close + title, play/pause + seek); PiP, NowPlaying, post-chain switches, preload, subtitle UI not wired |
| Resume | Chrome resolves resume and passes `startSeconds` | Layer supports `startSeconds`; `Pan115PlayerView` passes default 0 — see deviation 9 |
| Playback entry points | Pan115 / WatchOnline / Trailer all on MPlayKit | Only the 115 path (`Pan115PlayerView`) branches to MPlayKit |
| Settings keys | `avfan.mplaykit.post.*` | `avdb.mplaykit.post.*` (fresh keys, no migration) |
| Queue labels / frame sink | `avfan.*` | `avdb.*` |
| Pipeline | `scripts/mplaykit59/`, mpv 0.41.0 | `scripts/mplaykit353/`, mpv 0.41.0 (same pins; synced by the pipeline lane) |
| Everything else | — | Layer code identical apart from the renames in §"Sync from AVFan Build 59" |

## System frameworks the new layer needs (not added — for the coordinator)

The new layer imports AVFoundation, AudioToolbox, CoreMedia, CoreVideo,
VideoToolbox, Metal, MediaPlayer, AVKit, Network, CoreImage,
CoreGraphics, QuartzCore, UIKit, simd (plus `Libmpv`). The AVDB target
already links AVFoundation / AudioToolbox / CoreMedia / CoreVideo /
VideoToolbox / Security / Foundation / CoreFoundation + the 4 `.tbd`
libs explicitly (per `scripts/mplaykit353/LINK-NOTES.md` §1–§2), and
`OpenGLES` is still in the link list (harmless leftover from the GL
era; the modulemap no longer declares it). **Not** explicitly linked in
the AVDB target: **Metal, MediaPlayer, AVKit, Network, CoreImage,
CoreGraphics, QuartzCore** (UIKit/Foundation are implicit; `simd`
needs no framework link). This sync deliberately did **not** add them:
AVDB already imports AVKit, MediaPlayer, MetalKit and WebKit in other
files with no explicit pbxproj links, so the same module-autolink
mechanism the rest of the app relies on should cover the new layer —
but that is **待 CI 首跑验证**: if the link step reports undefined
symbols for any of the seven, add exactly those to "Link Binary With
Libraries" (the AVFan verified build links MediaPlayer explicitly and
carries Metal/QuartzCore in its Libmpv modulemap; AVDB's modulemap
declares neither).

## CI first-run checklist （待 CI 首跑验证）

- [ ] `libmpv-353` job: cold build finishes within the 240-minute
      timeout; warm run restores `Vendor/Libmpv.xcframework` from cache
      and skips the build. vo patches apply cleanly to pristine mpv
      0.41.0; `frame_output.h` ships in the xcframework headers.
- [ ] `spatial-353` job: `Vendor/TrueHD.xcframework` +
      `Vendor/DTSX.xcframework` produced from the pinned commits;
      silent-Atmos sample generation attempted (inert if absent).
- [ ] Release job links `Libmpv` + `TrueHD` (Frameworks only) +
      `DTSX` (Frameworks + Embed) and `xcodebuild` passes: Swift layer
      compiles against the libmpv C API (module `Libmpv`), the bridging
      header exposes both C bridges, both `.c` files compile,
      `MPlayPostChain.metal` builds into the default library.
- [ ] `test-mplaykit353.py` green; full regression failure set identical
      to the Build 352 baseline (51 pre-existing environment failures,
      no new ones).
- [ ] Device: switch Settings → 播放内核 to MPlayKit; a 115 direct link
      plays with headers applied; pause/seek/track switching work;
      embedded and external subtitles render via libass; a failing
      stream surfaces through the existing `vm.failed()` fallback;
      switching back to KSPlayer behaves exactly as before.
- [ ] Device (layer surfaces, chrome not yet wired): PiP entry/exit and
      subtitle render size in PiP; NowPlaying info + remote commands;
      post-chain SDR→HDR / upscaling / interpolation / P5 toggles and
      their visible effect vs the original (judge by look, then tune);
      DV file profile readback; `MPlayPreviewReader` stills (rotation
      sources, `dolbyProfile` readback) and `metadata()`.
- [ ] `MPlayStreamProtocol`, `MPlayDisc`, `MPlaySpatial` live feed and
      the translation pipeline have no UI entry point yet (layer first,
      per the restoration brief); verify via logs when first wired.

## License note

mpv is GPL-2.0-or-later; FFmpeg in this pipeline is configured
**without** `--enable-gpl` (LGPL core, decode-only), libplacebo is
LGPL-2.1-or-later, and the combined player core is treated as GPL for
distribution purposes — same posture as the existing KSPlayer core
(see `KSPlayer-GPL-3.0.txt` in the repo). Source pins and build
scripts for every native dependency live in `scripts/mplaykit353/`
(`THIRD_PARTY.md` there lists each component, version, source URL,
sha256 and license). Spatial: LibTrueHD is MIT (its TrueHD decoder
Apache-2.0); LibDTSX is Apache-2.0 with an LGPL-2.1-or-later FFmpeg
dca-decoder port, shipped as a **dynamic** framework only (LGPL §6
substitutability) — see `Spatial/UPSTREAM.md` and
`scripts/mplaykit353/THIRD_PARTY.md`.
