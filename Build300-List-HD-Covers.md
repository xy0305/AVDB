# Build 300 — 所有列表小图封面换高清

- MoviePosterImage / MoviePosterCard / MoviePosterGrid 默认开启可见卡片 HD 升级（之前只有首页）。
- 无 catalogue 图时只试 1 个规则候选（DMM awsimgsrc ps 竖版正面 / MGS pf_e），NOW PRINTING / 147×200 被 ImageLoader 拒绝并进短期负缓存。
- 学到的 pl 横版封套在后台线程用 Plan A 裁切取正面。
- 按格子像素×屏幕倍数降采样（≤900px），并发 2，离屏取消；小图先显示，HD 到了再叠上去。
- 推荐页模糊背景不升级。无码/FC2/欧美原图类型保持 Plan A（JavDB 封套裁切）。
