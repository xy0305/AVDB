# Build 290 — AI 增强封面走云端（Cloudflare R2 + Worker），手机不长期保存

## Flow (`AICoverEnhanceModel`)
1. Local bounded cache first: in-memory NSCache (≤ 12 images / 96 MB) + disk LRU `Caches/AICover` (excluded from backup).
2. Cloud: `GET https://covers.xy0305.kdns.fr/v1/cover/nomos1/{番号}_{W}x{H}.jpg` with `X-AVDB-Key`, **2.5 s total budget** across
   primary → fallback `https://avdb-covers.yxu83821.workers.dev` (fallback only on transport/5xx errors, never on 404).
   The original cover is already on screen; the chip shows 「云端加载中」 meanwhile. Hit → decode off-main, show, keep in the LRU.
3. Miss / offline / 401 / 5xx / timeout / no key → silent local enhancement (unchanged 4xNomosWebPhoto Core ML), show, then
   encode (JPEG q 0.9, HEIC at the same quality if smaller; quality steps down / raster ×0.8 until ≤ 3 MiB), store in the LRU,
   and upload in the background.
- Object name: `{番号}_{nativeW}x{nativeH}` (sanitized to `[A-Za-z0-9._-]`, ≤ 80); without a 番号 `h{sha40}_{W}x{H}`.
  The native size is part of the name because different sources of one title (800px jacket crop, MGS pf_e, JavDB) produce
  different results. Prefix `nomos1` = model `4xNomosWebPhoto_esrgan-x4-t128-fp16-v1`; **bump it if the model/params change**
  (keys are immutable, cached 1 year at the edge). Always stored under `.jpg`; the body may be HEIC (Worker returns the uploaded type).
- HTTP: one ephemeral URLSession with `urlCache = nil` (nothing persisted by the HTTP layer).

## Upload queue (`AICoverUploadQueue`)
Serial, utility/background priority, retry with backoff 2 / 8 / 32 / 128 / 300 s (5 attempts), no re-upload of names already
known in the cloud, 「仅 Wi‑Fi 上传」 (default off) skips on cellular/expensive paths (NWPathMonitor), 云端增强图 off → nothing.
**507** → uploads paused for 24 h, settings shows 「云端空间将满（507），已暂停上传」; reads continue. 400/401/413/415 → dropped.

## Local cache & migration
- Default cap 200 MB (50 / 100 / 200 / 500 MB / 1 GB in settings), oldest-used first. 清除缓存 shows current usage.
- The 285–289 cache (≤ 300 MB, files named by an opaque hash, no 番号) is migrated opportunistically: when a detail page resolves
  a cover that is in the local cache and not known in the cloud, it is uploaded (Wi‑Fi only, background priority). To give that a
  chance, pre-290 files are protected from LRU eviction for a 30-day grace window (not counted toward the cap), then trimmed.
  Files never reopened within 30 days are simply trimmed (not uploaded) — there is no 番号 to name them by.

## Settings (设置 → AI 画质增强)
云端增强图（默认开）· 仅 Wi‑Fi 上传（默认关）· 本地缓存上限 · 本地缓存用量 + 清除缓存 · 云端 命中/未命中/上传（字节）·
507 note · 复制云端诊断信息 (endpoints, prefix, key present yes/no — never the key, cache usage, counters, last error).
Footer no longer says 「不上传图片」; it explains the cloud read/upload.

## App key
- Info.plist `AVDBCoversKey = $(AVDB_COVERS_KEY)`; CI exports the `AVDB_COVERS_KEY` Actions secret into the xcodebuild
  environment (environment variables are build settings), the package step asserts the built plist equals the secret and the
  manifest records only presence/length/sha256[:8]. The key is not in git (test-cloud290.py greps tree + history).
- The repository is **public**: the key is extractable from any IPA (light gate by design; rotate per r2cover README). Workflow
  artifacts of a public repo are downloadable by any signed-in GitHub user, so the keyed IPA artifact is equally exposed.
- Without the secret the IPA is local-only (settings shows 「此版本未配置云端密钥，仅本机增强」) and the real-Worker e2e is skipped.

## Tests
- `scripts/test-cloud290.py`: wiring; Swift unit tests with a mock transport (hit, miss, 401, offline, primary-down fallback,
  5xx fallback, hung server → timeout, no key, PUT ok, 507, >3 MiB, queue 507 stop, retry/backoff, no duplicate upload,
  Wi‑Fi-only, cloud off, defaults, LRU, migration grace); the same client over URLSession against `scripts/cloud290/mock_worker.py`;
  and, with the secret, e2e against the real Worker (both endpoints) under `ci/`.
- `scripts/test-ai-ui290.py`: simulator UI e2e + screenshots against local mock Workers (cloud hit, slow cloud → 「云端加载中」,
  miss → local enhancement → background PUT verified in the mock log; settings incl. 507 note and cap menu).

## Not verified
- On-device network behaviour (cellular detection, background suspension during upload), real Worker latency from Japan/China.
- HEIC vs JPEG choice uses the same quality number, not a perceptual metric.
