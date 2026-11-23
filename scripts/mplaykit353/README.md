# mplaykit353 — Libmpv 原生构建管线（Build 353）

> ⚠️ **待 CI 首跑验证**：本管线在 Linux 上编写，本机没有 Xcode，
> 从未端到端跑通。首次在 CI（macos-26 runner）上运行必然可能翻车，
> 排查方向见文末。脚本风格参照 `scripts/live289/fetch_live289.py`
> （Python 驱动、sha256 钉死、输出落 `Vendor/`），工具 venv 参照
> `scripts/live287/` 的用法。

AVDB 引入 libmpv 作为可选播放内核。本目录只负责**把 Libmpv.xcframework
构建出来**；把 xcframework 接进 App（改 `project.pbxproj`、workflow、
Swift 桥接）由协调者另行收口。App 侧链接清单见 `LINK-NOTES.md`。

## 用法

```sh
python3 scripts/mplaykit353/build_libmpv.py <repo-root> [--platforms device,simulator] [--force]
```

- 平台：`device` = iphoneos/arm64，`simulator` = iphonesimulator/arm64；
  最低系统版本 17.0，与 App 的 `IPHONEOS_DEPLOYMENT_TARGET` 对齐。
- 幂等：每平台每阶段在 `.cache353/build/<platform>/<stage>.stamp` 落戳，
  重跑跳过已完成阶段；`--force` 清戳重建。
- 失败：任一步 `subprocess` 非零即停（check 语义），打印阶段名与日志尾部。

## 阶段图

```
bootstrap: venv(.cache353/venv) 装 meson/ninja/jinja2 + 检查 pkg-config/xcrun/cmake
fetch:     9 个 tarball → .cache353/downloads（逐个 sha256 校验）→ 解压 .cache353/src/
           │
           ├─ 每平台（device / simulator）依次构建到 .cache353/build/<platform>/prefix：
           │    1. xxhash      单文件编译 libxxhash.a + 手写 libxxhash.pc
           │    2. dav1d       meson cross（关 tools/tests/docs）
           │    3. freetype#1  cmake（-DFT_DISABLE_HARFBUZZ，先断循环依赖）
           │    4. harfbuzz    meson（freetype=enabled；glib/gobject/icu/cairo 关）
           │    5. freetype#2  cmake 重建（-DFT_WITH_HARFBUZZ=ON）
           │    6. fribidi     meson（关 docs/tests）
           │    7. libass      meson（fontconfig/libunibreak 关；darwin 走 CoreText）
           │    8. libplacebo  meson（vulkan=disabled、opengl=enabled、xxhash=enabled；
           │                        lcms/dovi 关；代码生成需 venv 的 jinja2）
           │    9. FFmpeg      configure 交叉编译（见下）
           │   10. mpv         meson cross（-Dlibmpv=true、plain-gl、audiounit；
           │                        其余开关全部防御式传参，见下）
           ├─ 合并：prefix/lib 下全部 .a 用 libtool -static 合成单个二进制，
           │        组装 Libmpv.framework（二进制 + Headers + module.modulemap + Info.plist）
           └─ xcodebuild -create-xcframework → Vendor/Libmpv.xcframework（先删后建）
```

**防御式传参**：meson 的 `-D` 传了不存在的选项会直接 configure 失败。
脚本的 `meson_args()` 先 grep 解压后源码的 `meson.options` /
`meson_options.txt`，只传项目真实声明的选项。mpv 需要关的：
lua、javascript、libbluray、uchardet、rubberband、vapoursynth、
libarchive、dvdnav、cdda、x11、wayland、drm、gbm、egl、gl-cocoa、
cocoa、coreaudio、sdl2、文档类（manpage/html/pdf）、tests；
需要开的：libmpv、plain-gl、audiounit（auto 亦可）、videotoolbox。

**cross file**：`cross/*.meson.txt` 是模板（meson cross file 不能执行
命令），`__SDK_PATH__` / `__CLANG__` 等占位符由驱动脚本运行时按
`xcrun --sdk <sdk> --show-sdk-path` / `-f <tool>` 的结果替换，落盘到
`.cache353/cross/` 后再用。SDK 路径一律 xcrun 动态取，不写死
`/Applications/Xcode.app` 路径。

## 组件版本与钉死出处

全部版本与 sha256 由协调者实际下载 tarball 后计算、钉死在
`build_libmpv.py` 的 `COMPONENTS` 表中（脚本逐个校验，不符 assert 失败）：

| 组件 | 版本 | 出处 |
|---|---|---|
| FFmpeg | 8.0.1 | ffmpeg.org 官方 release tarball |
| mpv | 0.42.0 | mpv-player/mpv GitHub tag 归档 |
| libplacebo | 7.387.0 | code.videolan.org 归档 |
| dav1d | 1.5.1 | downloads.videolan.org |
| libass | 0.17.4 | libass/libass GitHub release |
| freetype | 2.13.3 | download.savannah.gnu.org |
| harfbuzz | 15.2.0 | harfbuzz/harfbuzz GitHub release |
| fribidi | 1.0.16 | fribidi/fribidi GitHub release |
| xxHash | 0.8.3 | Cyan4973/xxHash GitHub tag 归档 |

关键约束：**mpv 0.42 的 meson.build 硬性要求 libplacebo >= 7.387.0**，
低了直接报错——这是 libplacebo 钉在 7.387.0 的原因，不是随手选的最新版。
mpv 0.42 对 libavformat/libavcodec 的下限很低，FFmpeg 8.0.1
（Lavf 62.12 / Lavc 62.28）满足。

## 与逆向画像的对应关系

对照 `~/workspace/p115-player-re/RE-REPORT.md` 第三节（Android 版
SenPlayer / mplaykit 内嵌 `libFFmpegKit.so` 的 FFmpeg 构建画像）：

| 画像项（Android 实测） | 本管线（iOS） | 说明 |
|---|---|---|
| FFmpeg 8.0 系列（Lavf 62.12 / Lavc 62.28） | FFmpeg 8.0.1 | 同系列对齐 |
| libmpv 与 FFmpeg 静态融合 | libmpv 0.42 + 全部依赖合并为单个静态 framework 二进制 | 同形态 |
| dav1d（AV1 软解，强证据） | dav1d 1.5.1，`--enable-libdav1d` | 对齐 |
| libass 全家：libass + FriBidi 1.0.16 + HarfBuzz + FreeType | libass 0.17.4 + fribidi 1.0.16 + harfbuzz 15.2.0 + freetype 2.13.3，`--enable-libass` | 对齐；FriBidi 版本与画像横幅 `FriBidi 1.0.16` 严格一致 |
| fontconfig 未链接（仅回退日志） | libass `-Dfontconfig=disabled`，darwin 走 CoreText | 对齐 |
| 播放型构建：无 x264/x265/vpx/svt-av1/fdk-aac 等编码库 | `--disable-encoders --disable-muxers`（仅保留 null muxer），不引入任何外部编码库 | 对齐 |
| 滤镜 tonemap / scale / subtitles / format / fps / aresample（强证据） | 不裁剪滤镜集（只 `--disable-devices`），以上滤镜都在 FFmpeg 默认集内 | 对齐 |
| OpenSSL（TLS） | **差异**：`--enable-securetransport`，用 iOS 系统 SecureTransport | 平台等价替换：iOS 不带 OpenSSL 系统库，SecureTransport 是 FFmpeg 在 darwin 上的原生 TLS 实现 |
| MediaCodec 硬解 | **差异**：`--enable-videotoolbox` + VideoToolbox hwaccel 全开（h264/hevc/mpeg2/mpeg4/vp9/prores），另开 audiotoolbox | 平台等价替换：iOS 的硬件解码面就是 VideoToolbox |
| libplacebo 0 命中（Android 构建未见） | **差异**：libplacebo 7.387.0 必带 | iOS 侧必需：mpv 0.42 的 gpu-next 依赖 libplacebo 且有 >= 7.387.0 的硬下限；Android 画像无字符串只能说明其构建未暴露/未带，不能推 iOS 侧可省 |
| 渲染经 EGL/ANativeWindow、音频经 AudioTrack | 渲染走 plain-gl（宿主经 libmpv render API 提供 GLES 上下文）、音频走 audiounit | 平台等价替换；`-Dvulkan=disabled` 合法（mpv 的 vulkan 选项是 require libplacebo-vulkan 的条件项），libplacebo 相应只开 OpenGL 后端，免去 glslang/shaderc |

## 首跑最可能失败的三个点（排查方向）

1. **libplacebo 的 meson configure / 代码生成**
   症状候选：找不到 xxhash、jinja2 import 失败、或 OpenGL 探测失败。
   排查：确认 venv 的 `bin/` 在 PATH 最前（jinja2 供其 python 代码生成用）；
   确认 xxhash 阶段已把 `libxxhash.pc` 写进本平台 `prefix/lib/pkgconfig`
   且 `PKG_CONFIG_PATH` 指向它；确认 cross file 替换后的 `-isysroot`
   是 simulator/device 对应的 SDK（两者串了会让 GL 头探测全军覆没）。

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
   libplacebo 版本下限（钉死版本已满足，若报错说明 pkg-config 读到了
   系统里另一份 libplacebo）、plain-gl 未置 `features['gl']`（多半是
   libplacebo 的 opengl 没开成，连带 mpv 侧 GL 探测失败）、或
   videotoolbox 选项名在 0.42 与脚本开关表不一致（grep 解压后
   `meson.options` 里 `videotoolbox` / `audiounit` 的实际拼写）。
   排查顺序：先看 mpv 阶段日志里 `(skip -D...: not an option ...)` 的
   打印——被跳过的关键开关（plain-gl / libmpv / audiounit）就是线索。
