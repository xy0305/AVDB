
## MissAV 新增排行（1.0.2 build 175）

保留原 AVDB 全部排行榜及 JAV Ranking 入口，在「排行榜」新增「MissAV 日 / 周 / 月排行」。MissAV 仅提供排行、原站封面标题与番号，不替换 AVDB 数据源、不注入上传 JS、不新增播放系统。

点击 MissAV 条目 → 按完整番号搜索现有 AVDB/JavDB 数据源 → 唯一精确匹配进入原生影片详情 → 在真实磁链列表选择资源推送 115。继续使用「我的」已配置的 115 Cookie 和目录、原生离线界面；无匹配时提供该番号原生搜索结果供手动核对，绝不自动选择无关第一条。

实站对照确认 missav.ws 的新旧 UA 均遇 Cloudflare 403，参考 JS 的 missav.fans / missav.media 原生 GET 返回真实 200 列表。build175 对齐标准浏览器头、隔离站点会话 Cookie，修复正常被动 Cloudflare JS 被误判验证及规范化分页路径；默认采用已验证 missav.fans，不自动切镜像，保留已保存来源。若已保存 missav.ws，可在 MissAV 设置恢复默认后保存。真正的 challenge 仍明确提示重试/浏览器核对，不绕过验证码、不导入浏览器 Cookie、不声称真机连通。详见 [诊断、实测与验收边界](Build175-MissAV.md)。

## 免责声明

本项目仅供学习研究使用。使用本软件产生的任何后果由使用者自行承担。请遵守当地法律法规，尊重知识产权。

## License

仅供学习研究，请勿用于商业用途。
