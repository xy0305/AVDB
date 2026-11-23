# Build 353 — Libmpv third-party components

Every component below is downloaded by `build_libmpv.py`, verified
against the pinned sha256 (the pins live in the script's `COMPONENTS`
table and were re-verified against the actual tarballs on 2026-11-23),
and statically linked into `Vendor/Libmpv.xcframework`. No component is
vendored into this repository as source.

| Component | Version | Source | License |
|---|---|---|---|
| FFmpeg | 8.0.1 | https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz | LGPL-2.1-or-later (configured without `--enable-gpl`; decode-only) |
| mpv | 0.42.0 | https://github.com/mpv-player/mpv/archive/refs/tags/v0.42.0.tar.gz | GPL-2.0-or-later |
| libplacebo | 7.387.0 | https://code.videolan.org/videolan/libplacebo/-/archive/v7.387.0/libplacebo-v7.387.0.tar.gz | LGPL-2.1-or-later |
| dav1d | 1.5.1 | https://downloads.videolan.org/pub/videolan/dav1d/1.5.1/dav1d-1.5.1.tar.xz | BSD-2-Clause |
| libass | 0.17.4 | https://github.com/libass/libass/releases/download/0.17.4/libass-0.17.4.tar.gz | ISC |
| freetype | 2.13.3 | https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.xz | FreeType License (FTL) |
| harfbuzz | 15.2.0 | https://github.com/harfbuzz/harfbuzz/releases/download/15.2.0/harfbuzz-15.2.0.tar.xz | MIT (Old MIT) |
| fribidi | 1.0.16 | https://github.com/fribidi/fribidi/releases/download/v1.0.16/fribidi-1.0.16.tar.xz | LGPL-2.1-or-later |
| xxHash | 0.8.3 | https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.3.tar.gz | BSD-2-Clause |

Notes:

- libplacebo 7.387.0 is mpv 0.42.0's hard minimum
  (`dependency('libplacebo', version: '>= 7.387.0')` in mpv's
  meson.build); it is newer than the libplacebo generation visible in
  the Android RE profile, which does not pin a version.
- fribidi 1.0.16 matches the FriBidi version identified in the
  original `libFFmpegKit.so` string table (RE-REPORT §3).
- FFmpeg 8.0.1's library versions (libavformat 62.x, libavcodec 62.x)
  match the FFmpeg 8.0 series identified in the original build.
- Because mpv is GPL, the combined `Libmpv.xcframework` is
  distributed under GPL terms, consistent with the app's existing
  KSPlayer core (`KSPlayer-GPL-3.0.txt` at the repo root).
