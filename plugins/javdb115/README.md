# JavDB sidecar dylib (AVDB115) v3

Standalone Objective-C dylib that adds AVDB-style **115 push/play**, **External Library**, and **HQ cover preview** to the official JavDB iOS app (`com.javdb6.com`). It does **not** change AVDB itself, and it does not hook JavDB membership, payment, or magnet APIs. JavDB’s original UI is left alone.

This folder is the only AVDB-repo addition on the isolated `ci/javdb-115-dylib` branch, together with `.github/workflows/javdb-115-dylib.yml`.

## What it does

- Floating “115” button (Flutter-safe: window / scene notifications plus delayed attach).
- Settings panel: 115 Cookie (Keychain, `ThisDeviceOnly`) and offline folder CID.
- Push magnet / ed2k the **user already copied or shared**; optional push-and-play.
- Play via 115 original URL (m115 / 115driver MIT) with HLS fallback. Playback uses AVPlayer (JavDB has no KSPlayer).
- **External database** (AVDB `ExternalLibraryClient`, not a local JSON file import):
  - Default root `http://163.47.40.207:8000` (already public in AVDB source), **disabled until the user enables it**.
  - User Token is stored only in Keychain as `X-API-Key`. Changing the server without a new token is rejected.
  - `GET /api/v1/articles/torrents?keyword=` with envelope `{data:[id,title,download_url,size_mb,seeders,chinese,uc,uhd]}`.
  - Root URL only; **all redirects are rejected**. No token in logs or UserDefaults.
  - Search / browse results in the plugin panel; magnet/ed2k can be copied or pushed to 115. The 115 Cookie is never sent to the external host.
- **HQ cover sources** in the same floating-panel menu:
  - Deterministic public URLs: DMM `awsimgsrc.dmm.co.jp` / `pics.dmm.co.jp` (Build 282 CID seed + 5/3-digit fallbacks), MGS Prestige/Jackson templates (`image.mgstage.com`).
  - Optional HTML: Avbase `https://www.avbase.net/works?q={番号}` `__NEXT_DATA__` (`image_url` preferred, then upgrade to awsimgsrc); JavBus first-party `/pics/cover/*_b.jpg` only.
  - Captcha, `driver-verify`, HTTP 403/429/503: skip the source, **no bypass**.
  - Preview + disk cache by 番号, timeout, cancel, URL dedupe, source fallback.
  - **Original-page cover replacement was investigated for v3 and is not armed.**
    JavDB 1.9.41 loads covers with Dart `Dio` + `cached_network_image` / `AppCacheManager` (`IOHttpClientAdapter`, `dart:io` `SecureSocket`). `Flutter.framework` in this IPA has **no** `NSURLSession` symbols, so a native session/UIImage hook would not see those requests. The list/detail API on `jdforrepam.com` requires `jdsignature` (unauthenticated calls return `ParameterInvalid`); request signing / TLS MITM is not implemented. Public covers are `https://c0.jdbstatic.com/covers/{xx}/{uid}.jpg` (UID only, no catalog number). The number appears only in the same card/JSON unit. A global Dart TLS MITM or uncontrolled hook is not delivered.
    The plugin panel has a **替换原页封面** switch, default on. The hook reports that it is **not active**; original home/list/detail images stay unchanged. HQ preview in the panel still works. If a rewrite were possible, it would only run when a classified cover URL and a catalog number are bound in the same unit, and would fall back to the original image on failure. Samples, logos, payment, and auth URLs are never rewritten.
    TPDB (user Bearer) and Tenhow actor mapping are not wired in this build.

Clipboard hooks only look for `magnet:` / `ed2k://` strings. Other clipboard content is ignored and never uploaded. The 115 cookie is not logged, not hardcoded, and not stored in UserDefaults (legacy UserDefaults values are migrated into Keychain and removed).

## Build (macOS + iOS SDK)

```sh
bash plugins/javdb115/scripts/build-dylib.sh dist/AVDB115-v3.dylib
```

GitHub Actions on this branch compiles `AVDB115-v3.dylib` (arm64, iphoneos, install name `@executable_path/Frameworks/AVDB115.dylib`) and uploads it with a source zip. The workflow does not run on `main` and does not start AVDB app builds.

## Inject locally (unsigned IPA)

Do **not** put a JavDB IPA in this repository (the repo is public). On your machine:

```sh
python3 plugins/javdb115/scripts/insert_dylib.py ipa /path/to/JavDB.ipa dist/AVDB115-v3.dylib \
  -o dist/JavDB-1.9.41-AVDB115-v3-unsigned.ipa
```

The script copies the dylib into `Runner.app/Frameworks`, inserts `LC_LOAD_DYLIB`, and writes an **unsigned** IPA. It will not pretend to codesign. Sideload signing is a separate step you do yourself.

## Tests

```sh
python3 plugins/javdb115/tests/test_protocol.py
python3 plugins/javdb115/tests/test_external_covers.py
python3 plugins/javdb115/tests/test_reachability.py
python3 plugins/javdb115/tests/test_page_cover.py
```

Reachability checks public DMM/MGS URLs and the default External Library root. A 401 from the torrents API without a token is expected. JavBus challenge pages and Avbase 403s are reported and not bypassed.

## Not verified

Device install, 115 login, real push, playback, External Library search with a live token, and cover preview on a physical iPhone have not been tested. AVPlayer may fail on some original 115 files; HLS is the fallback.
