# Build 353 — Libmpv third-party components

Every component below is downloaded by `build_libmpv.py`, verified
against the pinned sha256 (the pins live in the script's `COMPONENTS`
table and were re-verified against the actual tarballs on 2026-11-23),
and statically linked into `Vendor/Libmpv.xcframework`. No component is
vendored into this repository as source.

| Component | Version | Source | License |
|---|---|---|---|
| FFmpeg | 8.0.1 | https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz | LGPL-2.1-or-later (configured without `--enable-gpl`; decode-only) |
| mpv | 0.41.0 | https://github.com/mpv-player/mpv/archive/refs/tags/v0.41.0.tar.gz | GPL-2.0-or-later |
| libplacebo | 7.387.0 | https://code.videolan.org/videolan/libplacebo/-/archive/v7.387.0/libplacebo-v7.387.0.tar.gz | LGPL-2.1-or-later |
| dav1d | 1.5.1 | https://downloads.videolan.org/pub/videolan/dav1d/1.5.1/dav1d-1.5.1.tar.xz | BSD-2-Clause |
| libass | 0.17.4 | https://github.com/libass/libass/releases/download/0.17.4/libass-0.17.4.tar.xz | ISC |
| freetype | 2.13.3 | https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.xz | FreeType License (FTL) |
| harfbuzz | 15.2.0 | https://github.com/harfbuzz/harfbuzz/releases/download/15.2.0/harfbuzz-15.2.0.tar.xz | MIT (Old MIT) |
| fribidi | 1.0.16 | https://github.com/fribidi/fribidi/releases/download/v1.0.16/fribidi-1.0.16.tar.xz | LGPL-2.1-or-later |
| xxHash | 0.8.3 | https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.3.tar.gz | BSD-2-Clause |
| uchardet | 0.0.8 | https://www.freedesktop.org/software/uchardet/releases/uchardet-0.0.8.tar.xz | LGPL-2.1-or-later |
| Little CMS (lcms2) | 2.16 | https://github.com/mm2/Little-CMS/releases/download/lcms2.16/lcms2-2.16.tar.gz | MIT |

Notes:

- mpv is pinned to 0.41.0 on direct evidence: the original iOS
  binary embeds the string `mpv v0.41.0` (IOS-FINDINGS §5). The
  earlier 0.42.0 pin came from the Android profile, which carries no
  version string.
- libplacebo 7.387.0 exceeds mpv 0.41.0's minimum
  (`dependency('libplacebo', version: '>= 6.338.2')` in mpv's
  meson.build; 7.387.0 was the 0.42-era floor) and is kept: meson
  only sets a minimum. It is newer than the libplacebo generation
  visible in the Android RE profile, which does not pin a version.
- uchardet and lcms2 are built because the original iOS binary's
  embedded meson parameters enable both (`-Duchardet=enabled`,
  `-Dlcms2=enabled`, IOS-FINDINGS §3.1); mpv 0.41 requires
  lcms2 >= 2.6, satisfied by 2.16.
- fribidi 1.0.16 matches the FriBidi version identified in the
  original `libFFmpegKit.so` string table (RE-REPORT §3).
- FFmpeg 8.0.1's library versions (libavformat 62.x, libavcodec 62.x)
  match the FFmpeg 8.0 series identified in the original build.
- Because mpv is GPL, the combined `Libmpv.xcframework` is
  distributed under GPL terms, consistent with the app's existing
  KSPlayer core (`THIRD_PARTY/KSPlayer-GPL-3.0.txt` in this repo).

## Spatial audio components (Build 353 full restoration, stage D)

Fetched and built by `build_spatial.py` at the exact commits the
original's `FFmpegKit.bundle/NOTICE.md` pins (IOS-FINDINGS §2.4/§4);
provenance for the vendored headers is in
`AVDB/Services/MPlayKit/Spatial/UPSTREAM.md`. These are NOT part
of Libmpv.xcframework: LibTrueHD ships as `Vendor/TrueHD.xcframework`
(static library, linked only), LibDTSX as `Vendor/DTSX.xcframework`
(dynamic framework, linked and embedded — its upstream build
deliberately ships dynamic-only for LGPL §6 replaceability).

| Component | Pinned commit | Source | License |
|---|---|---|---|
| LibTrueHD | `3eab2e7c10ff1b3c2078afbab138471f2511859b` | https://github.com/superuser404notfound/LibTrueHD | wrapper MIT; upstream truehd decoder Apache-2.0 |
| LibDTSX | `6f0b321e560ea6911db3d1c797ada1ac08293320` | https://github.com/superuser404notfound/LibDTSX | wrapper Apache-2.0; contains an FFmpeg-LGPL-2.1-or-later-derived dca decoder, so the built library distributes under LGPL-3.0-or-later |
| AetherEngine | `fc6b412e7abdd19488fc439e225b83ab512b5d50` | https://github.com/superuser404notfound/AetherEngine | LGPL-3.0 + App Store exception. **Reference only**: AVDB does not link this package (its dependency graph — a prebuilt FFmpeg, an SMB client — is not taken on); its renderer/APAC/HLS/activator roles are implemented in our own Swift (`MPlaySpatialRender.swift`), and only its `Scripts/make-silent-atmos.swift` is executed by the CI stage to generate the silent Atmos sample |

LGPL note (mirrors the original NOTICE's own warning): static
distribution of LGPL components requires corresponding source and
relink means; license texts alone do not satisfy it. This is a
personal-sideload build; the pinned sources above are the
corresponding source.
