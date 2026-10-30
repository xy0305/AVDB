#!/usr/bin/env python3
"""Build 289 vendor + model fetch (CI; checksums pinned).
  Vendor/SherpaOnnxC.xcframework        sherpa-onnx v2.0.1 iOS (dynamic framework, onnxruntime static) — Apache-2.0 / MIT
  Vendor/sherpa-onnx-macos.xcframework  macOS dylib build, bench only
  <LiveModels>/sensevoice-small-int8/   SenseVoice-Small int8 ONNX (sherpa-onnx export 2024-07-17) — FunASR Model License 1.1
Also removes Whisper turbo from <LiveModels> (289: downloaded on demand; tokenizer-large-v3 stays bundled).
Usage: fetch_live289.py <repo-root> <LiveModels dir> [--keep-turbo]"""
import hashlib, json, shutil, subprocess, sys, tarfile, urllib.request
from pathlib import Path
REL = "https://github.com/k2-fsa/sherpa-onnx/releases/download"
FILES = {
    "ios": (f"{REL}/xcframework/sherpa-onnx-v2.0.1-ios-shared-onnxruntime-static.xcframework.zip",
            "fc4c665e694322ced5393aafafaae6bb3e0a7449d98d5db60bc220ac7ac4cbc9"),
    "macos": (f"{REL}/xcframework/sherpa-onnx-v2.0.1-macos-shared-onnxruntime-static.xcframework.zip",
              "b431898285d65ca9f2a4a7dcc9da412579f6dd4541c86e0bca8b5c02003c9535"),
    "sensevoice": (f"{REL}/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2",
                   "7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e"),
}
root = Path(sys.argv[1]).resolve(); models = Path(sys.argv[2]).resolve()
cache = root / ".cache289"; cache.mkdir(exist_ok=True)
def get(key):
    url, sha = FILES[key]
    dst = cache / url.rsplit("/", 1)[1]
    if not dst.exists() or hashlib.sha256(dst.read_bytes()).hexdigest() != sha:
        print("download", url, flush=True)
        urllib.request.urlretrieve(url, dst)
    got = hashlib.sha256(dst.read_bytes()).hexdigest()
    assert got == sha, (key, got)
    return dst
vendor = root / "Vendor"; vendor.mkdir(exist_ok=True)
for key, name, inner in [("ios", "SherpaOnnxC.xcframework", "SherpaOnnxC.xcframework"), ("macos", "sherpa-onnx-macos.xcframework", "sherpa-onnx.xcframework")]:
    out = vendor / name
    if not out.exists():
        tmp = cache / ("x-" + key); shutil.rmtree(tmp, ignore_errors=True)
        tmp.mkdir(parents=True); subprocess.run(["unzip", "-q", str(get(key)), "-d", str(tmp)], check=True)   # keeps modes/symlinks
        src = next(tmp.rglob(inner))
        shutil.move(str(src), out)
    print("vendor", out)
sv = models / "sensevoice-small-int8"
if not (sv / "model.int8.onnx").exists():
    sv.mkdir(parents=True, exist_ok=True)
    with tarfile.open(get("sensevoice")) as t:
        for m in t.getmembers():
            n = m.name.split("/", 1)[-1]
            if n in ("model.int8.onnx", "tokens.txt"):
                m.name = n; t.extract(m, sv)
    shutil.copy(Path(__file__).parent / "FUNASR_MODEL_LICENSE.txt", sv / "MODEL_LICENSE.txt")
    (sv / "README.md").write_text("SenseVoice-Small (FunAudioLLM / Alibaba Group, https://github.com/FunAudioLLM/SenseVoice), "
                                  "int8 ONNX export by k2-fsa/sherpa-onnx (2024-07-17). Licensed under the FunASR Model Open Source "
                                  "License v1.1 (MODEL_LICENSE.txt): attribution kept, model name retained.\n")
if "--keep-turbo" not in sys.argv:
    shutil.rmtree(models / "openai_whisper-large-v3-v20240930_turbo_632MB", ignore_errors=True)
sizes = {p.name: sum(f.stat().st_size for f in p.rglob("*") if f.is_file()) for p in models.iterdir() if p.is_dir()}
(models / "MODELS289.json").write_text(json.dumps({"sizes_bytes": sizes, "sensevoice_sha256": FILES["sensevoice"][1],
    "sherpa_onnx": "2.0.1", "turbo_bundled": (models / "openai_whisper-large-v3-v20240930_turbo_632MB").exists()}, indent=2))
print(json.dumps(sizes, indent=1))
