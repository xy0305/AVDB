# Build 280：续播 + 追更提醒 + LUT 预设 / 按住看原图

Base: Build 279 (`9a75de7`). CFBundleVersion 280. Workflow `lut4-online280.yml` (279 workflow → `workflow_dispatch`), packager `scripts/package-lut280.py`.
No CloudKit, no APNs remote push. Everything below works on a sideloaded / self-signed install.

## 1. 从历史直接续播

- **Resume key = 来源 + 番号** (`PlaybackResumeKey.make`, e.g. `missav|IPX-697`; full-width / `_` / spaces normalised). Stored per account scope (same scope as 观看历史) in `avdb.play.resume.v1.<scope>`; capacity 600; position + length + time only (no URL / headers / cookie / token).
- **Policy** (`PlaybackResumePolicy`): resume only when position ≥ 5 s, ≤ 95 % watched and not within the last 15 s; otherwise start from the beginning.
- **Player** (`KSChromePlayer`): after `readyToPlay` (once per URL) it seeks to the stored point, then shows the toast **「从 12:30 继续播放」 [从头]** for 6 s. 从头 seeks to 0 and remembers 0. Saving runs on the 5 s time tick (throttled) and is forced on pause / end / exit / background. It never writes while the resume seek is pending or before playback starts, so a loading item cannot overwrite the stored point with 0 s. Legacy `PlaybackProgressStore(progressID)` is still the fallback (115 / 糖心 entries from ≤279).
- **Sources**:
  - 115: key `115|番号`.
  - Online MissAV / Jable / 123AV / MemoJav / JavDay: key `<source>|番号`. Online session ids change every time, so 续播 re-queries **the same source only** (the user explicitly tapped 续播), picks the line with the same 番号 (`OnlineResumeLinePolicy`), resolves it through the normal validated pipeline and then seeks. If that fails, a banner offers 「手动选择」, which opens the normal online sheet.
  - JavDB catalog player: key `javdb|<movieID>`. This player is not launched from any screen in the current app, so JavDB history entries open the detail page.
- **观看历史**: a tap resumes on the recorded source (via the detail page, which auto-launches 115 or the re-resolved online line). The long-press menu has **续播 mm:ss / 从头播放 / 查看详情 / 删除**. 删除 also clears that 番号's resume keys. 糖心 entries open the 糖心 detail, whose player already resumes by progressID.
- **Detail page**: when 观看历史 has a resumable point on 115 or an online source, the play button reads **「续播 12:30 · MissAV」**. A long press offers 续播 / 从头播放 / 播放 115 原画. Entries from before Build 280 seed the per-source book from the history position the first time they are used.

## 2. 追更提醒

- **关注**: 女优 page (the existing 关注 button now follows locally and works signed-out; when signed in it still syncs JavDB's server 关注), 系列 and 片商 pages (bell button in the toolbar). 我的 › **关注管理** lists, opens and unfollows them.
- **Checks** (`FollowUpdateChecker`) use the existing JavDB API with the current session (no login is started): `actorMovies` / `seriesMovies` / `makerMovies`, newest 12.
  - When: on app foreground (3 s after login restore, at most every 15 min app-wide), in `BGAppRefreshTask` `org.avdb.follow.refresh` (earliest 4 h after scheduling; rescheduled on background and after each run), and by manual pull-to-refresh / 「立即检查」.
  - Rate limits: each follow is requested at most once per 6 h (manual bypasses this). Each run is capped (background 8, foreground 20, manual 40 follows), with 1.2 s between requests. A run aborts after 3 consecutive failures.
  - The first check of a new follow only records a baseline, so nothing is notified for existing works. After that, only movie ids that were not known before count as new. The feed dedupes by movie id, so one movie reached through both 女优 and 系列 appears once. The feed is capped at 300.
- **Notifications**: `UNUserNotificationCenter` local notifications. Permission is requested on the first follow. Up to 3 new works get individual notifications (identifier `avdb.follow.<movieID>`, so iOS replaces rather than duplicates); more than 3 get one summary. The app icon badge shows the unread count.
- **In-app feed**: 我的 › **关注更新** with an unread badge (marked read 1.5 s after opening). It shows the last check time and the notification permission state.
- Not done: the optional 收藏/想看 「已可在线播放」 check. Online sources are third parties, and the app's privacy rule is to query them only after an explicit tap, so a background check would need a separate opt-in.

## 3. LUT 预设 + 按住看原图

- Presets **关 / 自然 / 标准 / 增强** (segmented picker 「LUT 风格」 in the LUT panel, persisted in `avdb.lut.preset.v1`). A non-off style turns the LUT on automatically when the next video is ready. 开启/关闭 LUT toggles between 关 and the last style.
- JS engine (`OriginalLUT.setPreset`, used by both the JavaScriptCore native path and the Metal/HLS surface parameters):
  - 标准 = Build 279 exactly (`{scale:1,safety:{}}`).
  - 自然 = 6.7.8 params ×0.75 after the 279 safety gate, then the gate runs again.
  - 增强 = the 279 gate with only aesthetic limits relaxed: skin rotation allowance 7→12°, haze floor 0.93→0.90, highlight recovery floor −15→−18. Black-point, white anchor, magenta and high-key limits are unchanged.
  - Overrides are scoped (`withPresetSafety`, restored in `finally`).
- **按住看原图**: press and hold the LUT (滤镜) button in the top bar for ≥0.35 s. Online / Metal shows the full-frame original through `LUTRevealState.setHold`, even while paused. File playback swaps back to the untouched video composition. Release restores the LUT. The button sits in the top chrome, which the UIKit gesture receiver already excludes (`excludedTop`), so it never competes with pan-seek, brightness / volume, double-tap, seek preview or progress tap. A completed hold does not also open the panel.

### Benchmark (whos.tv held-out, 3887 source frames, same harness as 278/279)

Strength = mean ΔRGB (overall / skin) relative to 6.7.8. Fail = per-frame safety classes on the whole frame.

| preset | strength ΔRGB | skin | params = 6.7.8 | any fail | lifted black | grey white | magenta | high-key over | haze | pink skin |
|---|---|---|---|---|---|---|---|---|---|---|
| 6.7.8 | 1.000 | 1.000 | — | 93.0 % | 10.6 % | 15.7 % | 48.4 % | 22.4 % | 14.0 % | 70.5 % |
| 276 | 0.598 | 0.520 | 1.6 % | 48.8 % | 1.1 % | 31.2 % | 1.0 % | 3.0 % | 25.4 % | 1.2 % |
| **自然** (×0.75) | 0.561 | 0.607 | 0 % | 1.0 % | 0 | 0 | 0 | 0.23 % | 0.44 % | 0 |
| **标准** (=279) | 0.716 | 0.775 | 9.6 % | 1.85 % | 0.03 % | 0 | 0 | 0.36 % | 0.72 % | 0.21 % |
| **增强** | 0.751 | 0.806 | 12.9 % | 46.1 % | 0.03 % | 0 | 0 | 0.36 % | 1.23 % | 44.6 % |

On the 488 frames where 6.7.8 fails nothing but "pink skin", strength is: 自然 0.695, 标准 0.896, 增强 0.929.

增强's any-fail is almost entirely the "pink skin" class, which is the warmer 6.7.8 skin rotation that 增强 deliberately allows. Its black / white / magenta / high-key numbers equal 标准.

Rejected variants:
- A first 增强 that also relaxed the high-key limits reached 0.797 / 0.863 strength, but brightened 18.7 % of high-key frames (the 279 grey/haze complaint), so it was dropped.
- 自然 at ×0.6 was 0.446 / 0.481, weaker than the requested ≈276.

## Tests

- `scripts/test-resume-follow280.py`: swiftc execution of the pure resume / follow policies (key, 5 s / 95 % / tail, toast, book throttle / seed / cap / per-番号 delete, routing, line re-pick; follow due / caps / baseline / merge / dedupe / feed cap / notification plan) plus source contracts for all wiring, plist BG keys, pbxproj and version.
- `scripts/test-native-lut.py`: each preset on the 5 safety scenes passes toe / shoulder / white-anchor / magenta / lift / haze / grey-white / high-key contracts. 自然 is milder than 标准, 增强 is not weaker, safety overrides are restored, and an invalid name maps to 标准. Preset cases join the JavaScriptCore vs Node differential, with `setPreset` called before `predictParams`.
- Version asserts bumped to 280 in `test-watch-history277.py` / `test-playback-history.py`. `test-player-regressions.py` now follows the LUT button's hold-aware action.

## Limitations

- **Background refresh is not guaranteed**: iOS decides whether `BGAppRefreshTask` runs, based on usage, battery, Low Power Mode and Background App Refresh settings. With sideloaded / free-certificate installs it may rarely run or not at all, and it stops when the certificate expires (7 days for a free Apple ID). The foreground check and the in-app feed are the reliable path. Tapping a notification just opens the app.
- 115 multi-episode items share one resume key per 番号 (same as the previous progressID behaviour).
- Online 续播 needs the same source to still list the same 番号. Otherwise you get the manual sheet.
- File-mode hold swaps the composition, so it can take one frame to apply. Online / Metal is immediate.
