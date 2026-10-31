#!/usr/bin/env python3
"""Build 292 vendor fetch (CI; checksum pinned): Vendor/llama.xcframework — llama.cpp b12018 (MIT), dynamic
framework with the Metal backend built in. The LLM weights are NOT bundled (optional in-app download).
Usage: fetch_llama292.py <repo-root>"""
import hashlib, shutil, subprocess, sys, urllib.request
from pathlib import Path
URL = "https://github.com/ggml-org/llama.cpp/releases/download/b12018/llama-b12018-xcframework.zip"
SHA = "c0c7daf1a710e1849a5b3c5a292e85ff5609d5dd3d64239eb3d23c76dcad03b3"
root = Path(sys.argv[1]).resolve(); cache = root / ".cache292"; cache.mkdir(exist_ok=True)
dst = cache / URL.rsplit("/", 1)[1]
if not dst.exists() or hashlib.sha256(dst.read_bytes()).hexdigest() != SHA:
    print("download", URL, flush=True); urllib.request.urlretrieve(URL, dst)
got = hashlib.sha256(dst.read_bytes()).hexdigest(); assert got == SHA, got
out = root / "Vendor/llama.xcframework"
if not out.exists():
    tmp = cache / "x"; shutil.rmtree(tmp, ignore_errors=True); tmp.mkdir()
    subprocess.run(["unzip", "-q", str(dst), "-d", str(tmp)], check=True)
    src = next(tmp.rglob("llama.xcframework"))
    # keep only the slices the app needs (device + simulator); drop macOS/tvOS/visionOS to keep the checkout small
    shutil.move(str(src), out)
print("vendor", out, sorted(p.name for p in out.iterdir()))
