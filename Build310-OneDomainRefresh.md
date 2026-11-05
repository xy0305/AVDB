# Build 310 — ONE 域名表刷新修复（时钟被普通调用重置）

User report (2026-11-06): 装了 Build 309 后 ONE 所有影片仍播不了，
播放器报错 `dlmk0129.upmf83.com · 播放：失败（原因未确定）（系统码 2）`。

## Diagnosis (live-verified before changing code)

复刻 ONE 协议（游客 bootstrap）拿到当日域名表与影片详情实测：

- 当日 `video` 组 5 台主机（46e9nz.mfpt8g.com 等）对同一影片路径全部
  **206 video/mp4** ✓；详情里的 `video_download` 全是路径式，无绝对 URL
  （扫了 86 个详情：discovery new/hot、直播搜索均无例外）。
- **`dlmk0129.upmf83.com`（用户报错的主机）不在当日域名表里**，且实测
  连接层直接失败（HTTP 000，无响应）——是已被轮换淘汰的死镜像。
- 结论：用户 app 里存的域名表是旧的，线全建在死主机上，所以「所有都看不了」，
  而列表/详情（走稳定的 api 种子域名）一切正常。
- 补充实测（ffprobe，即播放器同族的 ffmpeg 栈）：当日 6 台活主机里 curl 全部
  <1s 返回 206，但 ffprobe 打开有 3 台 25 秒超时（eruj5e、emg7wn、ftdlmk），
  另 3 台正常打开（46e9nz、f86xxm、pu63rg）。即「主机活着」≠「播放器能
  快速打开」，线路排序不能只靠域名表顺序。用户随后截图亦显示 309 的自动
  换线在工作（已走到线路 5），但其表内前几台同样不可用。

## Root cause (code)

Build 309 的 24 小时刷新是死代码：

- `bootstrap(force: false)` 用 `sessionSavedAt` 判断表龄（>24h 才刷新）；
- 但 `saveSession()` 无条件把 `sessionSavedAt` 刷成当前时间，而
  `callData` 在**每一次成功调用后**都调 `saveSession()` 存主机。

于是表龄时钟被日常调用不断清零，域名表永不刷新（只有 401 才强刷），
镜像按天轮换/死亡后，全部播放线随之失效。

## Change (OneCore.swift only, plus release wiring)

1. `saveSession(updateTimestamp:)`：只有 bootstrap 成功才盖时间戳；
   `callData` 的常规保存传 `false`，只存主机/token，不动时钟。
2. 域名表 TTL 24h → **1h**：镜像在一天内就会轮换死亡，1 小时足够新。
3. `videoHosts()` 的脆弱主机降序从 `vd.*` 扩到 **`dlmk*`** 编号镜像
   （与 vd 同类：轮换快、死得快），永远排在稳定主机之后。
4. 详情打开时**并发预探测**全部 MP4 线路（1 字节 Range、单台 4 秒超时）：
   能答 200/206 的按原顺序排前面，死/慢的沉到后面给自动换线兜底；
   全部探测失败则原样返回，不改变既有行为。
5. 每部片的同文件线路 5 条 → **8 条**，换线有更长的跑道。

其余行为不变：309 的失败自动换线、线路构成、界面均未动。

## Immediate workaround for Build 309 users

删除应用后重装，首次打开 ONE 会全新 bootstrap 拿到当日域名表即可播放
（不清数据重装不行，会话存在应用数据里）。310 发布后直接覆盖装即可，
首次进 ONE 若表龄 >1h 会自动刷新，不需要删应用。
