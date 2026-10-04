# Native LUT (build 150)

Adapted from supplied `网页视频实时 LUT（v6.7.5）`, original metadata `@author You`, `@version 6.7.5`; complete unexecuted source in `THIRD_PARTY/lut-v6.7.5.txt`. No license was present in that source. Redistribution permission has not been independently verified; no license is invented for it.

The Swift port preserves scalar brightness/highlight/shadow/temperature/tint/saturation/contrast math, near-white protection, Rec.709 statistics, and 33×33×33 blue/green/red iteration. CoreImage receives RGBA Float32 (574992 bytes) and sRGB cube space. Vision replaces MediaPipe. Bounded two-pass coordinate search uses original normal/extreme-dark templates and ranges but is NOT identical to predictParams: high-match/high-highlight branches, dynamic Cr quantiles, luminance guards and parameter balancing are not yet ported. No JS is evaluated.

Normal and Pan115 share KSChromePlayer. Tap LUT to enable, reanalyse, reset, or adjust seven parameters. The first analysis uses AVPlayerItemVideoOutput while videoComposition is removed, avoiding feedback. Frame analysis is off the main actor. Subsequent rendering uses actual AVVideoComposition/CIColorCubeWithColorSpace, not a fake view overlay. Hardware KSAVPlayer remains default.

Supported scope: composable SDR AVPlayer assets (e.g. progressive MP4). HLS `.m3u8`, noncomposable streams and PQ/HLG HDR are explicitly disabled. HLS URLs without that suffix still depend on AVAsset.isComposable; this is not a native HLS renderer fork. KSMEPlayer does not expose this feature. No cloud write operations are introduced. Requires device testing for remote composition, orientation and color fidelity; CI compilation alone is not visual verification.

KSPlayer remains an external GPL-3.0 dependency: preserve its notices/license and provide corresponding source for the exact application and dependency revision with any binary distribution. GPL text copied as `THIRD_PARTY/KSPlayer-GPL-3.0.txt`; dependency attribution is not a claim that the supplied userscript has a GPL license.
