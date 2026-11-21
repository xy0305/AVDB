# JavDB 115 sidecar dylib (AVDB115)

Standalone Objective-C dylib that adds AVDB-style 115 offline **push** and **playback** to the official JavDB iOS app (`com.javdb6.com`). It does **not** change AVDB itself, and it does not hook JavDB membership, payment, or magnet APIs.

This folder is the only AVDB-repo addition on the isolated `ci/javdb-115-dylib` branch, together with `.github/workflows/javdb-115-dylib.yml`.

## What it does

- Floating “115” button (Flutter-safe: window / scene notifications plus delayed attach).
- Settings panel: 115 Cookie (Keychain, `ThisDeviceOnly`) and offline folder CID.
- Push magnet / ed2k the **user already copied or shared**; optional push-and-play.
- Play via 115 original URL (m115 / 115driver MIT) with HLS fallback. Playback uses AVPlayer (JavDB has no KSPlayer).

Clipboard hooks only look for `magnet:` / `ed2k://` strings. Other clipboard content is ignored and never uploaded. Cookie is not logged, not hardcoded, and not stored in UserDefaults (legacy UserDefaults values are migrated into Keychain and removed).

## Build (macOS + iOS SDK)

```sh
bash plugins/javdb115/scripts/build-dylib.sh dist/AVDB115.dylib
```

GitHub Actions on this branch compiles `AVDB115.dylib` (arm64, iphoneos, install name `@executable_path/Frameworks/AVDB115.dylib`) and uploads it with a source zip. The workflow does not run on `main` and does not start AVDB app builds.

## Inject locally (unsigned IPA)

Do **not** put a JavDB IPA in this repository (the repo is public). On your machine:

```sh
python3 plugins/javdb115/scripts/insert_dylib.py ipa /path/to/JavDB.ipa dist/AVDB115.dylib \
  -o dist/JavDB-AVDB115-unsigned.ipa
```

The script copies the dylib into `Runner.app/Frameworks`, inserts `LC_LOAD_DYLIB`, and writes an **unsigned** IPA. It will not pretend to codesign. Sideload signing is a separate step you do yourself.

## Not verified

Device install, 115 login, real push, and playback have not been tested on a physical iPhone. AVPlayer may fail on some original 115 files; HLS is the fallback.
