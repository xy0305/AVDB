# AVDB for Windows 11

原生 WPF 桌面应用（`WinExe`，无控制台、无浏览器套壳）。

## 运行

从 [Releases](https://github.com/xy0305/AVDB/releases) 下载 `AVDB-win-x64.zip`，解压后双击 `AVDB.exe`。自包含 .NET 8，Win11 x64 不需要另装运行时。请把整个文件夹一起放，不要只拷贝 exe。

- 左侧导航：首页 / 最新上架 / 近期磁链 / 搜索
- 登录 token 保存在 `%AppData%\AVDB\token.txt`
- 封面自动解密 JAVDB CDN

## 本地构建

```bat
dotnet publish win\AVDB.Win\AVDB.Win.csproj -c Release -r win-x64 --self-contained true -o win\publish
```
