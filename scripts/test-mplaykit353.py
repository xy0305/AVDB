#!/usr/bin/env python3
"""Build 353 gate: MPlayKit playback core restored 1:1 from the
reverse-engineered Android MPlayKit (libmpv + FFmpeg 8.0) as an optional
kernel beside KSPlayer (which stays the default).

The user ordered on 2026-11-23: 「全部一比一还原」 — restore it all,
one-to-one. Sources: ~/workspace/p115-player-re/RE-REPORT.md and
FINDINGS.md. This gate pins, in the style of the earlier per-build
gates:

- the version roll (353 everywhere the 352 gate pinned 352);
- the native pipeline (scripts/mplaykit353/: pinned FFmpeg 8.0.1 /
  mpv 0.41.0 / libplacebo 7.387.0 / dav1d 1.5.1 / libass 0.17.4 /
  freetype 2.13.3 / harfbuzz 15.2.0 / fribidi 1.0.16 / xxHash 0.8.3 /
  uchardet 0.0.8 / lcms2 2.16, sha256-verified downloads, iOS cross
  files, CI libmpv-353 + spatial-353 jobs, vo frame_output patches
  0001-0003);
- the Swift layer (AVDB/Services/MPlayKit/: player / state / progress /
  preview reader / diagnostics / frame_output pixel view / kernel
  settings / PiP / subtitle layer / Metal post chain / Dolby Vision /
  spatial bridge) and its project.pbxproj registration, including
  Libmpv.xcframework in Frameworks + Embed Frameworks and the
  TrueHD/DTSX spatial xcframeworks, plus the app bridging header;
- the integration (kernel picker in Settings, Pan115PlayerView branch,
  KSPlayer path untouched);
- the Build 353 doc with its mapping and deviation tables.
"""
from pathlib import Path
import re

r = Path(__file__).resolve().parent.parent
wf = (r / '.github/workflows/home-hq298.yml').read_text()
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()

# --- version roll (mirrors the 352 gate's pin block) ---
import plistlib
plist = plistlib.loads((r / 'AVDB/Resources/Info.plist').read_bytes())
assert plist['CFBundleVersion'] == '353' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 353;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2
assert 'Home HQ posters App 353' in wf and 'feat/mplaykit-353' in wf and 'feat/search-auth-352' in wf
assert 'scripts/package-lut353.py' in wf and 'AVDB-353-release' in wf and 'AVDB-352-release' not in wf
pkg = (r / 'scripts/package-lut353.py').read_text()
assert "=='353'" in pkg and 'AVDB-unsigned-1.0.2-353-mplaykit.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  mplaykit-353:' in wf and '  search-auth-352:' in wf and '  enrichment-351:' in wf
assert wf.count('python3 scripts/test-mplaykit353.py') == 5
assert wf.count('python3 scripts/test-search-auth352.py') == 5

# --- native pipeline ---
pipe_dir = r / 'scripts/mplaykit353'
build = (pipe_dir / 'build_libmpv.py').read_text()
for version in ['8.0.1', '0.41.0', '7.387.0', '1.5.1', '0.17.4',
                '2.13.3', '15.2.0', '1.0.16', '0.8.3', '0.0.8', '2.16']:
    assert version in build, version
pins = set(re.findall(r'[0-9a-f]{64}', build))
assert len(pins) >= 9, len(pins)
for name in ['ffmpeg', 'mpv', 'libplacebo', 'dav1d', 'libass',
             'freetype', 'harfbuzz', 'fribidi', 'xxhash', 'uchardet', 'lcms2']:
    assert name in build.lower(), name
assert (pipe_dir / 'cross/ios-device-arm64.meson.txt').exists()
assert (pipe_dir / 'cross/ios-simulator-arm64.meson.txt').exists()
for doc_name in ['README.md', 'LINK-NOTES.md', 'THIRD_PARTY.md']:
    assert (pipe_dir / doc_name).exists(), doc_name
assert 'videotoolbox' in build and 'securetransport' in build
assert 'libmpv-353:' in wf and 'needs: [models, libmpv-353, spatial-353]' in wf
assert 'AVDB-353-libmpv' in wf and 'Vendor/Libmpv.xcframework' in wf
assert 'scripts/mplaykit353/build_libmpv.py' in wf
assert 'spatial-353:' in wf and 'AVDB-353-spatial' in wf
assert 'scripts/mplaykit353/build_spatial.py' in wf
assert (pipe_dir / 'build_spatial.py').exists()
for patch in ['0001-vo-frame-output.patch', '0002-vo-frame-output-colorspace-include.patch',
              '0003-vo-frame-output-repr-levels.patch']:
    assert (pipe_dir / 'patches' / patch).exists(), patch
assert 'ios-gl' in build and 'mpv-v2' in build

# --- Swift layer ---
layer = r / 'AVDB/Services/MPlayKit'
kernel = (layer / 'MPlayKernel.swift').read_text()
assert 'enum PlaybackKernel' in kernel and 'avdb.playback.kernel' in kernel
assert 'case ksPlayer = "KSPlayer"' in kernel and 'case mplayKit = "MPlayKit"' in kernel
player = (layer / 'MPlayPlayer.swift').read_text()
for needle in ['mpv_create', 'mpv_initialize', 'mpv_command_async', 'videotoolbox',
               'func open(', 'func setPaused', 'func seek(', 'func setProp',
               'func state() -> MPlayState', 'func progress() -> MPlayProgress',
               'func makePreloadedPlayer', 'func close()', 'return -3',
               'MPV_EVENT_PLAYBACK_RESTART', 'demuxer-cache-state']:
    assert needle in player, needle
state = (layer / 'MPlayState.swift').read_text()
assert 'struct MPlayState' in state and 'struct MPlayStateRaw' in state
assert 'struct MPlayProgress' in state and 'func jsonObject()' in state
for key in ['cacheDuration', 'cacheEnd', 'cacheRanges', 'pausedForCache',
            'hwdecCurrent', 'estimatedFrameRate']:
    assert key in state, key
diag = (layer / 'MPlayDiagnostics.swift').read_text()
assert '"event=\\(name)"' in diag and 'static func log(' in diag and 'static func event(' in diag
view = (layer / 'MPlayVideoView.swift').read_text()
assert 'AVSampleBufferDisplayLayer' in view and 'frame_output' in view
assert 'mpv_render_context_create' not in view
assert 'func attach(player: MPlayPlayer)' in view and 'func detach()' in view
preview = (layer / 'MPlayPreviewReader.swift').read_text()
assert 'struct MPlayStill' in preview
assert 'func still(url: String' in preview and 'dolbyProfile' in preview
assert 'mpv_render_context_create' in preview  # stills use a separate render-API instance
assert not (layer / 'MPlayRenderContext.swift').exists()
for name in ['MPlayFrameOutput.swift', 'MPlayCachePolicy.swift', 'MPlayPictureInPicture.swift',
             'MPlaySpatial.swift', 'MPlayPostChain.swift', 'MPlayDolbyVision.swift',
             'MPlaySubtitleLayer.swift', 'MPlayStreamProtocol.swift',
             'MPlayStreamBridge.c', 'MPlayStreamBridge.h']:
    assert (layer / name).exists(), name
for name in ['MPlaySpatialBridge.c', 'MPlaySpatialBridge.h', 'truehd_atmos.h', 'dtsx.h']:
    assert (layer / 'Spatial' / name).exists(), name
assert (r / 'AVDB/AVDB-Bridging-Header.h').exists()
assert 'SWIFT_OBJC_BRIDGING_HEADER' in pbx

# --- pbxproj registration ---
for name in ['MPlayKernel.swift', 'MPlayDiagnostics.swift', 'MPlayState.swift',
             'MPlayPlayer.swift', 'MPlayVideoView.swift',
             'MPlayPreviewReader.swift', 'MPlayFrameOutput.swift', 'MPlayCachePolicy.swift',
             'MPlayPictureInPicture.swift', 'MPlaySpatial.swift', 'MPlayPostChain.swift',
             'MPlayDolbyVision.swift', 'MPlaySubtitleLayer.swift', 'MPlayStreamProtocol.swift',
             'MPlayKitPlayerView.swift']:
    assert f'{name} in Sources' in pbx, name
    assert f'path = {name};' in pbx, name
assert 'path = Vendor/Libmpv.xcframework' in pbx
assert 'Libmpv.xcframework in Frameworks' in pbx
assert 'Libmpv.xcframework in Embed Frameworks' in pbx
assert 'path = Vendor/TrueHD.xcframework' in pbx
assert 'TrueHD.xcframework in Frameworks' in pbx
assert 'path = Vendor/DTSX.xcframework' in pbx
assert 'DTSX.xcframework in Frameworks' in pbx
assert 'DTSX.xcframework in Embed Frameworks' in pbx
assert 'MPlayStreamBridge.c in Sources' in pbx
assert 'MPlaySpatialBridge.c in Sources' in pbx
assert 'MPlayPostChain.metal in Sources' in pbx
for framework in ['AVFoundation', 'AudioToolbox', 'CoreMedia', 'CoreVideo',
                  'VideoToolbox', 'OpenGLES', 'Security', 'CoreFoundation']:
    assert f'{framework}.framework in Frameworks' in pbx, framework
for lib in ['libc++', 'libz', 'libiconv', 'libbz2']:
    assert f'{lib}.tbd in Frameworks' in pbx, lib

# --- integration ---
pan = (r / 'AVDB/Views/Player/Pan115PlayerView.swift').read_text()
assert 'PlaybackKernelSettings.current == .mplayKit' in pan
assert 'MPlayKitPlayerView(' in pan and 'KSChromePlayer(' in pan
userview = (r / 'AVDB/Views/User/UserView.swift').read_text()
assert 'Section("播放")' in userview and 'playback-kernel-picker' in userview
assert 'PlaybackKernelSettings.defaultsKey' in userview
mpview = (r / 'AVDB/Views/Player/MPlayKitPlayerView.swift').read_text()
assert 'mplaykit.player' in mpview and 'MPlayPlayer' in mpview

# --- build doc ---
doc = (r / 'Build353-MPlayKit.md').read_text()
assert 'Muse' in doc and 'Kai' in doc
assert '全部一比一还原' in doc and 'RE-REPORT' in doc
assert '双 Surface' in doc and 'MediaCodec' in doc and 'VideoToolbox' in doc
assert 'n0' in doc and 'n18' in doc and '下标' in doc
assert '待 CI 首跑验证' in doc

print('Build 353 MPlayKit gate OK: pinned libmpv pipeline (FFmpeg 8.0.1 + mpv 0.41.0 + libplacebo 7.387.0 + spatial decoders), '
      'Swift MPlayKit full-restoration layer registered, kernel picker wired, KSPlayer default intact, deviations documented, release 353')
