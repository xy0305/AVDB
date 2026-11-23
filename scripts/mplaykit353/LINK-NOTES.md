# LINK-NOTES — App 侧链接 Libmpv.xcframework 需要的系统框架/库（Build 353）

> 状态：**本仓库首跑待验证**（管线本身在 AVFan CI run 45239463298
> 已验证出包）。本清单供协调者改 `project.pbxproj` 时照单添加；
> 以首跑后真机链接的实际报错为准增删。

`Vendor/Libmpv.xcframework` 是一个静态 framework：`libtool -static` 把
libmpv / FFmpeg（libavformat、libavcodec、libavfilter、libavutil、
libswscale、libswresample）/ libplacebo / libass / libdav1d / libfreetype /
libharfbuzz / libfribidi / libxxhash / libuchardet / liblcms2 全部合并成
单个 `Libmpv` 二进制。
这些第三方库**不需要**在 Xcode 里再单独链接；需要的是它们引用的
**系统框架与系统库**，如下。

## 1. 已在 module.modulemap 里声明 `link` 的部分

`Libmpv.framework/Modules/module.modulemap` 里已写：

| 类别 | 条目 |
|---|---|
| 系统框架 | `AVFoundation`、`AudioToolbox`、`CoreMedia`、`CoreVideo`、`VideoToolbox`、`Security`、`Foundation`、`CoreFoundation` |
| 系统库 | `c++`（libc++）、`z`（libz）、`iconv`（libiconv）、`bz2`（libbz2） |

Clang module 的 `link framework` / `link` 声明会让 Swift/Clang 在
**启用了 modules 且经 `import Libmpv` 引入**时自动把这些传给链接器
（autolink）。理论上 App target 只需把 `Libmpv.xcframework` 加进
target 的 Frameworks 即可，不必再逐个添加上面这批。
（注意：modulemap 里**没有** `OpenGLES`——旧 0.42.0 管线编 plain-gl
时才需要；新管线 `-Dgl=disabled`，已随脚本去掉。也**没有**
`Metal` / `QuartzCore`，那是宿主 Metal 后链自己的依赖，见 §3。）

## 2. 仍建议在 Xcode target 里显式添加的部分

autolink 有两个已知不可靠点，所以协调者在 pbxproj 里请**显式**添加：

1. **全部 8 个系统框架**（同上表）显式加进 App target 的
   “Link Binary With Libraries”。理由：xcframework 里 framework 的
   modulemap autolink 在某些 Xcode 版本下对纯 Swift target、或经
   `OTHER_LDFLAGS` 混排时不生效；显式添加无副作用（重复链接会被去重）。
2. **4 个系统库** `libc++`、`libz`、`libiconv`、`libbz2` 同样显式添加
   （以 `.tbd` 形式：`libc++.tbd`、`libz.tbd`、`libiconv.tbd`、
   `libbz2.tbd`）。其中 `libc++` 是必需的硬依赖：libplacebo / harfbuzz /
   dav1d 含 C++ 代码，缺了会先报 C++ 标准库符号未定义。
3. **`UIKit`**：mpv 本体不直接依赖，但宿主 App 的显示视图与
   audiounit 输出经 AVAudioSession 都要用——App target 本来就链接
   UIKit，这里列出只是提醒它属于**间接依赖**，不要在精简 target
   依赖时误删。libmpv render API 只剩 PreviewReader 的软件渲染在用
   （MPV_RENDER_API_TYPE_SW，不需要任何 GL 框架）。

## 3. 对照表（来源 → 需要它的组件）

| 系统框架/库 | 被谁引用 |
|---|---|
| AVFoundation | mpv audiounit / 宿主播放会话（间接） |
| AudioToolbox | mpv `ao_audiounit` |
| CoreMedia | FFmpeg VideoToolbox hwaccel（CMTime/CMFormatDescription） |
| CoreVideo | FFmpeg VideoToolbox（CVPixelBuffer）、frame_output vo 的帧交接、宿主帧管线 |
| Metal / QuartzCore | 宿主 Metal 后链（阶段 C）与 AVSampleBufferDisplayLayer 显示层（阶段 A） |
| VideoToolbox | FFmpeg `--enable-videotoolbox` 硬解 |
| Security | FFmpeg SecureTransport TLS（`--enable-securetransport`） |
| Foundation | mpv/libass 的 darwin 代码（CoreText 路径等） |
| CoreFoundation | libass CoreText、FFmpeg darwin 代码 |
| UIKit | 间接：宿主 App 的显示视图与音频会话 |
| libc++ | libplacebo、harfbuzz、dav1d 的 C++ 部分 |
| libz | FFmpeg `--enable-zlib` |
| libiconv | FFmpeg `--enable-iconv` |
| libbz2 | FFmpeg `--enable-bzlib`、freetype（已关内部 bzip2，仍保留链接兜底） |

注：**不需要** Metal / Vulkan 相关框架——libplacebo 无图形 API 构建
（`-Dvulkan=disabled -Dopengl=disabled`），mpv 侧 `-Dvulkan=disabled`；
也**不需要** CoreAudio（iOS 无此框架，音频走 audiounit）、fontconfig、
OpenSSL（TLS 用系统 SecureTransport 替代）、OpenGLES（GL 全关）。

## 4. 空间音频 xcframework（stage D，不在 Libmpv 内）

`spatial-353` job 另产两个 xcframework，进 `Vendor/`：

| 产物 | 链接方式 |
|---|---|
| `TrueHD.xcframework`（静态库套 framework 壳） | 只链接（link），不 embed |
| `DTSX.xcframework`（动态 framework，上游有意只出动态版，LGPL §6 可替换性） | 链接 + embed |

两个都由 `build_spatial.py` 按钉死 commit 编出（见 `THIRD_PARTY.md`
空间音频一节）；App target 加进 Frameworks 时按上表区分 embed。
`Vendor/mplay-silent-atmos.mp4`（静默 Atmos 样本）是否打进 App 包，
待生成在真机 CI 上验证后再由 Resources 入口决定（见
Build353-MPlayKit.md）。
