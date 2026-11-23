# Spatial 目录的上游来源（Build 353 全量还原，阶段 D）

> 注：本文件自 AVFan Build 59 原样同步；AVDB 的空间音频构建脚本由管线同步一路落位在 scripts/mplaykit353/。

本目录的两个头文件是上游钉版仓库的**原文拷贝**（未改一字），构建脚本
`scripts/mplaykit353/build_spatial.py` 会按同一钉版重新拉取校验；
`MPlaySpatialBridge.h/.c` 是我方代码（MPlayNative 风格改名转发层）。

| 文件 | 上游仓库 | 钉版 commit | 许可证 |
|---|---|---|---|
| `truehd_atmos.h` | https://github.com/superuser404notfound/LibTrueHD | `3eab2e7c10ff1b3c2078afbab138471f2511859b` | 本仓 MIT；上游 truehd 解码器 Apache-2.0 |
| `dtsx.h` | https://github.com/superuser404notfound/LibDTSX | `6f0b321e560ea6911db3d1c797ada1ac08293320` | 本仓 Apache-2.0；内含 FFmpeg LGPL-2.1-or-later 移植的 dca 解码器，构建产物整体按 LGPL-3.0-or-later 分发，且上游明确只以**动态框架**出货（LGPL §6 可替换要求），我方照此嵌入 DTSX.xcframework，不做静态化 |

渲染层参考的上游（未 vendor 其代码，我方以 Swift 等价实现其角色；
其钉版与许可证记录在此与 `scripts/mplaykit353/THIRD_PARTY.md`）：

| 组件 | 上游仓库 | 钉版 commit | 许可证 |
|---|---|---|---|
| AetherEngine（渲染器/APAC/HLS 角色的参考实现） | https://github.com/superuser404notfound/AetherEngine | `fc6b412e7abdd19488fc439e225b83ab512b5d50` | LGPL-3.0 + 自拟 App Store 例外 |

钉版依据：原版 SenPlayer.app 的 `FFmpegKit.bundle/NOTICE.md`
（IOS-FINDINGS §2.4）。静默 Atmos 样本的生成脚本
`Scripts/make-silent-atmos.swift` 在 AetherEngine 钉版仓内，
由 `build_spatial.py` 在 CI 上尝试生成（需 runner 有 swift + ffmpeg）。
