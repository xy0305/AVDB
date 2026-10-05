# 原版 MediaPipe FaceLandmarker 接入

- 原版 `THIRD_PARTY/lut-v6.7.5.txt`：JS Tasks Vision 0.10.14，GPU，VIDEO，numFaces=1，detection/presence=0.3；tracking 默认0.5，blendshapes/transformation 默认关闭。
- 原生依赖：官方 CocoaPods `MediaPipeTasksVision` 0.10.14 + `MediaPipeTasksCommon` 0.10.14（Apache-2.0）。官方 podspec 支持 iOS12；本工程 iOS17。SDK 上游 https://github.com/google-ai-edge/mediapipe ，固定发布 https://dl.google.com/cpdc/20240510-090346/MediaPipeTasksVision-0.10.14.tar.gz 。使用 `pod install` 后 `AVDB.xcworkspace` 构建，不再直接构建 project。
- 本地打包模型： https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task ，float16/1，3,758,596 bytes，SHA256 `64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff`。运行时没有网络请求、没有 Vision 替代算法。MediaPipe 模型来自官方发布；相关源码及 SDK Apache-2.0 许可全文 `MediaPipe-Apache-2.0.txt`。不能把原 LUT 用户脚本推定为 Apache 许可，其原来源信息另保留。

## 算法契约

1. 长边恒为640，包括小输入上采样；短边 JS Math.round（正数 floor(x+.5)），至少1。两轴独立伸缩至整数尺寸。
2. 抽取一份sRGB RGBA8，CGImage/MPImage与原版sampleFrame使用同一份字节。原生无 Vision 人脸矩形请求。
3. VIDEO实例串行复用，单调系统时钟毫秒时间戳，对应原版 performance.now 而非视频播放进度。GPU 不悄悄降级 CPU。
4. 仅取 `faceLandmarks.first`，所有关键点 x/y min/max；expand=1.0；保持原脚本中心/半径运算次序；左上 floor/max(0)，右下 ceil/min(width,height)，不添加额外裁剪。
5. 无人脸或推理异常，原脚本中央50%采样。异常状态明确显示，不声称已检测人脸；仍执行原版低于150肤色像素则拒绝更新，不额外再退回中央。

## 验证与边界

`python3 scripts/test-mediapipe-parity.py`：从独立原文本提取采样 oracle，而不是拿移植版自比；16组完整 sampleFrame 返回（全部 pixels/high_rb/high_pixels/global ratio/regionName），覆盖奇数尺寸、横竖图、无脸、全框、局部框、空框，确定性RGBA随机输入。macOS还执行实际Swift ROI函数与JS独立oracle的5组差分：first-face/minmax/小数 floor ceil/越界/空脸/退化。

原生Metal GPU和浏览器WebGL GPU浮点实现、VIDEO追踪历史/毫秒时间戳、AVFoundation解码/色彩管理、CI缩放与Canvas2D插值可能不同；同版本模型不意味着跨后端landmarks逐浮点相等。这里只能验证相同landmarks输入的ROI规则及相同RGBA+ROI的sampleFrame精确一致。原生模型推理尚需要实体iOS运行验证；Linux iSH不能运行Xcode或Metal，不以Node采样测试冒充原生推理成功。未测量设备延迟/功耗。
