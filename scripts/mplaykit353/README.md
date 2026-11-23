# mplaykit353 — Libmpv 原生构建管线（Build 353）

> ⚠️ **本仓库首跑待验证**：本管线与 AVFan 的 `scripts/mplaykit59/`
> 同源，后者在 AVFan CI run 45239463298 全绿出包
> （AVFan-unsigned-112）。AVDB 侧是第一次跑，排查方向见文末。
> 脚本风格为 Python 驱动、sha256 钉死、输出落 `Vendor/`，工具 venv
> 在脚本内自举（见下文阶段图）。

AVDB 引入 libmpv 作为可选播放内核。本目录只负责**把
Libmpv.xcframework 与空间音频解码 xcframework 构建出来**；把
xcframework 接进 App（改 `project.pbxproj`、workflow、Swift 桥接）
由协调者另行收口。App 侧链接清单见 `LINK-NOTES.md`。
CI 接入在 `.github/workflows/home-hq298.yml`：`libmpv-353` job
（编 Libmpv.xcframework，上传 artifact `AVDB-353-libmpv`）与
`spatial-353` job（编 TrueHD/DTSX xcframework，上传 artifact
`AVDB-353-spatial`），`release` 与 9 个 UI jobs 各自下载两个 artifact
到 `Vendor/` 后再编译 App。

## 用法

```sh
python3 scripts/mplaykit353/build_libmpv.py <repo-root> [--platforms device,simulator] [--force]
python3 scripts/mplaykit353/build_spatial.py <repo-root>
```

- 平台：`device` = iphoneos/arm64，`simulator` = iphonesimulator/arm64；
  最低系统版本 17.0，与 App 的 `IPHONEOS_DEPLOYMENT_TARGET` 对齐。
- 幂等：每平台每阶段在 `.cache353/build/<platform>/<stage>.stamp` 落戳，
  重跑跳过已完成阶段；`--force` 清戳重建。
- 失败：任一步 `subprocess` 非零即停（check 语义），打印阶段名与日志尾部。

## 阶段图

```
bootstrap: venv(.cache353/venv) 装 meson/ninja/jinja2 + 检查 pkg-config/xcrun/cmake
fetch:     11 个 tarball → .cache353/downloads（逐个 sha256 校验）→ 解压 .cache353/src/
           ├─ libplacebo 3rdparty 补 fast_float 8.2.2 + Vulkan-Headers
           │  （commit 74d8a6cb，均 sha256 钉死）
           └─ 给 mpv 打 patches/0001-0003（frame_output vo；见下“补丁陷阱”）
           │
           ├─ 每平台（device / simulator）依次构建到 .cache353/build/<platform>/prefix：
           │    1. xxhash      单文件编译 libxxhash.a + 手写 libxxhash.pc
           │    2. dav1d       meson cross（关 tools/tests/docs）
           │    3. freetype#1  cmake（-DFT_DISABLE_HARFBUZZ，先断循环依赖）
           │    4. harfbuzz    meson（freetype=enabled；glib/gobject/icu/cairo 关）
           │    5. freetype#2  cmake 重建（-DFT_WITH_HARFBUZZ=ON）
           │    6. fribidi     meson（关 docs/tests）
           │    7. libass      meson（fontconfig/libunibreak 关；darwin 走 CoreText）
           │    8. uchardet   cmake（静态；装 uchardet.pc 供 mpv 探测；
           │                        CMAKE_POLICY_VERSION_MINIMUM=3.5、
           │                        BUILD_BINARY=OFF，见脚本注释）
           │    9. lcms2      meson（jpeg/tiff 关；装 lcms2.pc 供 mpv 探测）
           │   10. libplacebo  meson（vulkan=disabled、opengl=disabled、xxhash=enabled；
           │                        lcms/dovi 关；无图形 API 构建，见下；代码生成需 venv 的 jinja2）
           │   11. FFmpeg      configure 交叉编译（见下）
           │   12. mpv         meson cross（-Dlibmpv=true、gl=disabled、ios-gl=disabled、
           │                        audiounit、uchardet/lcms2=enabled；
           │                        其余开关全部防御式传参，见下）
           ├─ 合并：prefix/lib 下全部 .a 用 libtool -static 合成单个二进制，
           │        组装 Libmpv.framework（二进制 + Headers/mpv/ + module.modulemap + Info.plist）
           └─ xcodebuild -create-xcframework → Vendor/Libmpv.xcframework（先删后建）

spatial:   build_spatial.py（stage D，与 libmpv 分开跑）：
           LibTrueHD / LibDTSX / AetherEngine 按钉死 commit clone，
           各自 build.sh 编出 TrueHD.xcframework / DTSX.xcframework
           → Vendor/；AetherEngine 只跑 Scripts/make-silent-atmos.swift
           生成 Vendor/mplay-silent-atmos.mp4（swift/ffmpeg 缺失时警告跳过）
```

**防御式传参**：meson 的 `-D` 传了不存在的选项会直接 configure 失败。
脚本的 `meson_args()` 先 grep 解压后源码的 `meson.options` /
`meson_options.txt`，只传项目真实声明的选项。mpv 需要关的：
lua、javascript、libbluray、rubberband、vapoursynth、
libarchive、dvdnav、cdda、x11、wayland、drm、gbm、egl、gl-cocoa、
cocoa、coreaudio、sdl2-audio/video/gamepad、文档类（manpage/html/pdf）、tests；
需要开的：libmpv、audiounit、uchardet、lcms2；需要明确关的另有 gl、plain-gl、
ios-gl、videotoolbox-gl、videotoolbox-pl（像素帧管线下不需要 GL 面）。
（选项名已按 mpv 0.41.0 的 meson.options 实测核对：不存在裸
`videotoolbox` / `sdl2` / `test` 选项，旧脚本里的这三个键一直被
防御式传参静默跳过，本轮已改真名。）

**cross file**：`cross/*.meson.txt` 是模板（meson cross file 不能执行
命令），`__SDK_PATH__` / `__CLANG__` 等占位符由驱动脚本运行时按
`xcrun --sdk <sdk> --show-sdk-path` / `-f <tool>` 的结果替换，落盘到
`.cache353/cross/` 后再用。SDK 路径一律 xcrun 动态取，不写死
`/Applications/Xcode.app` 路径。

## 补丁陷阱（AVFan 第 9→10 轮实证，必读）

CI 上补丁树位于仓库 checkout 内时，`git apply` 按外层仓库根解析
路径、**静默跳过全部文件且退出码 0**，`--check` 同样空洞。第 10 轮
之前所有「libmpv 成功」的构建其实都是 stock mpv、frame_output 补丁
从未打上。修法（已搬进 `build_libmpv.py` 的 `apply_patches()`，
不要绕过）：

- `git apply --directory=<rev-parse --show-prefix>` 把补丁路径重定向
  进 mpv 源码树；
- 哨兵断言：补丁落位后必须存在 `include/mpv/frame_output.h` 与
  `video/out/vo_frame_output.c`，且头补丁的反向 `--check` 通过，
  否则 assert 失败——`git apply` 的退出码本身不作证据；
- 补丁状态改动时作废 stamp：`apply_patches()` 在树变化后删除各平台
  的 `mpv*.stamp` 与 `framework-*.stamp`，防止还原缓存里的 stock
  mpv 被当成已编好。

## stamp 陷阱

stamp 是纯存在性检查。改了 mpv 选项/补丁后必须让 stage 改名或失效，
否则 CI 用还原缓存跳过重编、假装成功。本轮的对应做法：

- mpv stage 名带版本后缀：`mpv-v2`（v2 = ios-gl 关断后的重编）；
- framework stage 名带版本后缀：`framework-<platform>-v4`
  （v4 = 输入的 libmpv 已按 mpv-v2 重编）；
- 补丁变化时 `apply_patches()` 按 `mpv*.stamp` / `framework-*.stamp`
  glob 主动删戳（见上节）；
- workflow 缓存 key 同步抬版：`libmpv-353-v2-…`
  （hashFiles 本身也会随脚本改动变化，双保险）。

## 组件版本与钉死出处

全部版本与 sha256 由协调者实际下载 tarball 后计算、钉死在
`build_libmpv.py` 的 `COMPONENTS` 表中（脚本逐个校验，不符 assert 失败）：

| 组件 | 版本 | 出处 |
|---|---|---|
| FFmpeg | 8.0.1 | ffmpeg.org 官方 release tarball |
| mpv | 0.41.0 | mpv-player/mpv GitHub tag 归档 |
| libplacebo | 7.387.0 | code.videolan.org 归档 |
| dav1d | 1.5.1 | downloads.videolan.org |
| libass | 0.17.4 | libass/libass GitHub release |
| freetype | 2.13.3 | download.savannah.gnu.org |
| harfbuzz | 15.2.0 | harfbuzz/harfbuzz GitHub release |
| fribidi | 1.0.16 | fribidi/fribidi GitHub release |
| xxHash | 0.8.3 | Cyan4973/xxHash GitHub tag 归档 |
| uchardet | 0.0.8 | freedesktop.org 官方 release |
| lcms2 | 2.16 | mm2/Little-CMS GitHub release |

关键约束：**mpv 钉 0.41.0 的依据是 iOS 原版二进制内的 `mpv v0.41.0`
版本串直证**（IOS-FINDINGS §5；旧钉 0.42.0 来自无版本串的安卓画像）。
mpv 0.41.0 的 meson.build 对 libplacebo 的下限是 >= 6.338.2
（0.42 才抬到 >= 7.387.0）；meson 只设下限，故 libplacebo 7.387.0
保留不动、仍满足。mpv 0.41 与 0.42 的选项集经逐项 diff 仅差
0.42 新增的 amf/dvda/libcurl/subrandr 四项，我们传的开关无一被
改名/改型/改默认值。mpv 对 libavformat/libavcodec 的下限很低，
FFmpeg 8.0.1（Lavf 62.12 / Lavc 62.28）满足。

**ios-gl 关断的依据**（mpv 0.41.0 `meson.build:1426-1430` 实测）：
`ios_gl` 的门控只有 `darwin` + `OpenGLES/ES3/glext.h` 里
`GL_RGB32F` 符号探测，不要求 `gl`——`gl=disabled` 时 `ios-gl`
auto 仍会打开，随后编进的 `video/out/hwdec/hwdec_ios_gl.m` 引用
`ra_gl_get` / `ra_create_wrapped_tex` 等 `ra_gl` 符号，而 `gl`
关掉后 `ra_gl` 根本没编，App 链接报 undefined `_ra_*`（AVFan
第 15 轮）。故 `-Dios-gl=disabled` 必须显式传。

## 与逆向画像的对应关系

对照 `~/workspace/p115-player-re/RE-REPORT.md` 第三节（Android 版
SenPlayer / mplaykit 内嵌 `libFFmpegKit.so` 的 FFmpeg 构建画像），
并叠加 `~/workspace/p115-player-re/IOS-FINDINGS.md` §3/§5 的 iOS 版
画像（主二进制内嵌 mpv 版本串与 meson 构建参数原文，符号级证据）：

| 画像项（Android 实测） | 本管线（iOS） | 说明 |
|---|---|---|
| FFmpeg 8.0 系列（Lavf 62.12 / Lavc 62.28） | FFmpeg 8.0.1 | 同系列对齐；iOS 二进制的 Lavf/Lavc 版本串与安卓逐字一致（IOS-FINDINGS §5） |
| libmpv 与 FFmpeg 静态融合 | libmpv 0.41.0 + 全部依赖合并为单个静态 framework 二进制 | 版本依据 iOS 二进制 `mpv v0.41.0` 直证；同形态 |
| iOS 原版 meson 参数：`-Duchardet=enabled -Dlcms2=enabled`（原文直证） | uchardet 0.0.8 + lcms2 2.16 补构建进 prefix，mpv 侧两开关打开 | 本轮对齐项（IOS-FINDINGS §3.1/§3.3） |
| iOS 原版 meson 参数：`-Dgl=disabled`（原文直证） | **已对齐**（全量还原轮）：`-Dgl=disabled`，plain-gl / ios-gl / videotoolbox-gl / videotoolbox-pl 一并关 | 显示层已换成与原版同构的像素帧管线：patches/0001-vo-frame-output.patch 给 mpv 加自研 vo `frame_output`（VT 帧零拷贝、软解帧打包为 CVPixelBuffer、字幕走独立通道），宿主侧 FrameStore/Scheduler + AVSampleBufferDisplayLayer 承载。见 Build353-MPlayKit.md |
| iOS 原版 meson 参数：`-Dlibavdevice=enabled -Davfoundation=enabled` | **差异（已申报）**：不开 | 无设备/光盘输入源需求，暂不补，记录在案（IOS-FINDINGS §3.3）；avfoundation 另有 stock 源码在 iOS 上编不过的问题，见 Build353-MPlayKit.md deviation 12 |
| dav1d（AV1 软解，强证据） | dav1d 1.5.1，`--enable-libdav1d` | 对齐 |
| libass 全家：libass + FriBidi 1.0.16 + HarfBuzz + FreeType | libass 0.17.4 + fribidi 1.0.16 + harfbuzz 15.2.0 + freetype 2.13.3，`--enable-libass` | 对齐；FriBidi 版本与画像横幅 `FriBidi 1.0.16` 严格一致 |
| fontconfig 未链接（仅回退日志） | libass `-Dfontconfig=disabled`，darwin 走 CoreText | 对齐 |
| 播放型构建：无 x264/x265/vpx/svt-av1/fdk-aac 等编码库 | `--disable-encoders --disable-muxers`（仅保留 null muxer），不引入任何外部编码库 | 对齐 |
| 滤镜 tonemap / scale / subtitles / format / fps / aresample（强证据） | 不裁剪滤镜集（只 `--disable-devices`），以上滤镜都在 FFmpeg 默认集内 | 对齐 |
| OpenSSL（TLS） | **差异**：`--enable-securetransport`，用 iOS 系统 SecureTransport | 平台等价替换：iOS 不带 OpenSSL 系统库，SecureTransport 是 FFmpeg 在 darwin 上的原生 TLS 实现 |
| MediaCodec 硬解 | **差异**：`--enable-videotoolbox` + VideoToolbox hwaccel 全开（h264/hevc/mpeg2/mpeg4/vp9/prores），另开 audiotoolbox | 平台等价替换：iOS 的硬件解码面就是 VideoToolbox |
| libplacebo 0 命中（Android 构建未见） | **差异**：libplacebo 7.387.0 必带，但无图形 API 构建（vulkan/opengl 均关） | mpv 0.41 的 meson 对 libplacebo 是硬依赖（dependency 无 required:false），删不掉；iOS 原版二进制亦编入 libplacebo 但运行时不走（IOS-FINDINGS §3.2/§5）。上游 libplacebo 明确支持无图形 API 构建（src/meson.build 仅 warning），保留其 dummy/着色器生成部分。版本下限 mpv 0.41 只要求 >= 6.338.2，7.387.0 是满足下限的保留钉版 |
| 渲染经 EGL/ANativeWindow、音频经 AudioTrack | 渲染走 frame_output 像素帧管线（CVPixelBuffer → AVSampleBufferDisplayLayer），音频走 audiounit | 平台等价替换；`-Dvulkan=disabled` 合法（mpv 的 vulkan 选项是 require libplacebo-vulkan 的条件项），libplacebo 无图形 API 构建，免去 glslang/shaderc |
| 空间音频（原版 FFmpegKit.bundle/NOTICE.md 钉死三组件） | stage D：LibTrueHD @ 3eab2e7c、LibDTSX @ 6f0b321e、AetherEngine @ fc6b412e（仅 silent-Atmos 生成脚本） | 见 `THIRD_PARTY.md` 空间音频一节与 `AVDB/Services/MPlayKit/Spatial/UPSTREAM.md` |

## 首跑最可能失败的三个点（排查方向）

1. **libplacebo 的 meson configure / 代码生成**
   症状候选：找不到 xxhash、jinja2 import 失败。
   排查：确认 venv 的 `bin/` 在 PATH 最前（jinja2 供其 python 代码生成用）；
   确认 xxhash 阶段已把 `libxxhash.pc` 写进本平台 `prefix/lib/pkgconfig`
   且 `PKG_CONFIG_PATH` 指向它；确认 cross file 替换后的 `-isysroot`
   是 simulator/device 对应的 SDK（两者串了会让头文件探测全军覆没）。

2. **FFmpeg configure 的交叉编译探测**
   症状候选：`C compiler test failed`、pkg-config 找不到 libdav1d/libass、
   或 `--enable-hwaccels` 在该 configure 上不存在。
   排查：先单独看 `.cache353/build/<platform>/ffmpeg/ffbuild/config.log`
   尾部（脚本打印的日志尾部就含它）；脚本已用 `--pkg-config-flags=--static`
   并优先探测 `--enable-hwaccels` 总开关、没有才逐个
   `--enable-hwaccel=<codec>_videotoolbox`；若死在 securetransport，
   核对 FFmpeg 8.0.1 的 configure 里该选项名与 SDK 的 Security.framework。

3. **mpv 的 meson configure 选项/依赖收敛**
   症状候选：防御式传参已挡掉“未知选项”类失败，剩下的是依赖类——
   libplacebo 版本下限（0.41 要求 >= 6.338.2，钉死版本已满足，若报错
   说明 pkg-config 读到了系统里另一份 libplacebo）、uchardet/lcms2
   的 .pc 是否真落进本平台 prefix（新 stage，首跑重点看）、frame_output
   补丁未生效（fetch 阶段应打印 `mpv patches applied`，没有就是补丁
   没打上，vo 会在运行时报 `frame_output` 不存在；补丁的哨兵断言若
   触发，日志里会直接看到 `frame_output.h` / `vo_frame_output.c`
   缺失的 assert）、或 audiounit 的实际拼写与开关表不一致（grep 解压后
   `meson.options` 核对）。
   排查顺序：先看 mpv 阶段日志里 `(skip -D...: not an option ...)` 的
   打印——被跳过的关键开关（gl / ios-gl / libmpv / audiounit /
   uchardet / lcms2）就是线索；再看 `video/out/hwdec/hwdec_ios_gl.m`
   是否出现在编译行里——出现即 ios-gl 没关住（mpv stage 应为 `mpv-v2`）。

4. **缓存/stamp 把旧产物当成新产物**
   症状候选：脚本改了、CI 日志却显示 `skip (stamped)` 跳过 mpv /
   framework 阶段，或 cache 精确命中后产物仍是旧版。
   排查：确认 workflow 缓存 key 是 `libmpv-353-v2-…`（v1 是 0.42.0
   旧管线的 key）；确认日志里 mpv 阶段名是 `mpv-v2`、framework 阶段
   名是 `framework-<platform>-v4`；若怀疑缓存被污染，`--force`
   或在 workflow 里临时把 key 抬到 v3 重跑。
