# Build 299 — 首页打开搜索卡顿

## 现象
首页点「搜索番號 / 關鍵詞」→ 搜索页滑入时掉帧。录屏可见转场中途定格，随后才出现近期熱搜 / 歷史搜索与键盘。

## 原因
打开搜索时，导航 push、整页标签玻璃（FlowLayout + glassSurface 材质/阴影）、staggerAppear，以及 `onAppear` 立刻 `isSearchFocused = true` 弹出键盘叠在一起，主线程在转场中途被占满。

## 修复
- Home 预取 `SearchSuggestStore.prefetch()`（历史本机已有，热搜后台拉）
- SearchView：转场约 340ms 后再渲染热搜/历史标签云，再聚焦输入框弹键盘
- 标签改用静态 `scrolling: true` 玻璃芯片，去掉 staggerAppear / pressableGlass
- 封面 HQ / Plan A 未改

## 产物
`AVDB-unsigned-1.0.2-299-search-open.ipa`（workflow Home HQ posters App 299）
