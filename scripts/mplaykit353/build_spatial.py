#!/usr/bin/env python3
"""
build_spatial.py — Build 353 full restoration, stage D: fetch and
build the pinned spatial-audio decoder xcframeworks into
<repo>/Vendor/.

Components (pins from the original's FFmpegKit.bundle/NOTICE.md,
IOS-FINDINGS §2.4; see AVDB/Services/MPlayKit/Spatial/UPSTREAM.md):

  LibTrueHD    superuser404notfound/LibTrueHD    @ 3eab2e7c10ff1b3c2078afbab138471f2511859b
  LibDTSX      superuser404notfound/LibDTSX      @ 6f0b321e560ea6911db3d1c797ada1ac08293320
  AetherEngine superuser404notfound/AetherEngine @ fc6b412e7abdd19488fc439e225b83ab512b5d50
               (only its Scripts/make-silent-atmos.swift is used,
               to generate the silent Atmos keep-alive sample)

Each decoder repo carries its own build.sh, which builds its
xcframework with cargo under the repo's pinned rust-toolchain.toml
(LibTrueHD 1.98.1, LibDTSX 1.99.0 — rustup selects per directory).
LibDTSX's build.sh deliberately produces a DYNAMIC framework
("never a static library", its LGPL §6 reasoning); we ship it that
way and embed it.  LibTrueHD's produces a static library inside a
framework wrapper; we link it, no embed.

Fallback: if cargo/rustup is unavailable, the xcframework checked
into each pinned repo is used instead and a loud warning is
printed (the checked-in artifacts are the repos' own release
builds at those commits; building from source is preferred for
LGPL corresponding-source hygiene).

The silent-Atmos generation needs `swift` and `ffmpeg` on the
runner; when either is missing, or the script does not produce
the file, the step warns and continues — AtmosOutputActivator is
inert without the asset.  The generated file lands in
Vendor/mplay-silent-atmos.mp4 as a build artifact; bundling it
into the app requires a Resources entry once generation has been
verified on a real CI run (recorded in Build353-MPlayKit.md).

Usage: python3 build_spatial.py <repo-root>
Cache: <repo>/.cache353/spatial/ (clones + stamps), same cache root
as build_libmpv.py so the workflow's cache step covers both.
"""

import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

PINS = {
    "LibTrueHD": (
        "https://github.com/superuser404notfound/LibTrueHD",
        "3eab2e7c10ff1b3c2078afbab138471f2511859b",
        "TrueHD.xcframework",
    ),
    "LibDTSX": (
        "https://github.com/superuser404notfound/LibDTSX",
        "6f0b321e560ea6911db3d1c797ada1ac08293320",
        "DTSX.xcframework",
    ),
    "AetherEngine": (
        "https://github.com/superuser404notfound/AetherEngine",
        "fc6b412e7abdd19488fc439e225b83ab512b5d50",
        None,
    ),
}


def run(cmd, cwd=None, label=""):
    print("+", " ".join(str(c) for c in cmd), flush=True)
    result = subprocess.run([str(c) for c in cmd], cwd=cwd)
    assert result.returncode == 0, f"{label or cmd[0]} failed rc={result.returncode}"


def clone_pinned(name, url, commit, dest):
    if not dest.exists():
        run(["git", "clone", "--no-checkout", url, dest], label=f"clone-{name}")
    run(["git", "-C", dest, "fetch", "origin", commit], label=f"fetch-{name}")
    run(["git", "-C", dest, "checkout", "--detach", commit], label=f"checkout-{name}")
    head = subprocess.run(["git", "-C", dest, "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    assert head == commit, f"{name}: HEAD {head} != pinned {commit}"
    print(f"{name}: pinned at {commit}", flush=True)


def build_decoder(name, src, xcframework_name, vendor):
    target = vendor / xcframework_name
    built = src / xcframework_name
    if shutil.which("cargo") and (shutil.which("rustup") or shutil.which("rustc")):
        print(f"{name}: building from source via build.sh (pinned toolchain)", flush=True)
        run(["bash", "build.sh"], cwd=src, label=f"build-{name}")
    else:
        print(f"WARNING: {name}: cargo/rustup not found; using the "
              f"xcframework checked into the pinned repo", flush=True)
    assert built.is_dir(), f"{name}: {xcframework_name} not produced at {built}"
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(built, target)
    print(f"{name}: -> {target}", flush=True)


def generate_silent_atmos(src, vendor):
    script = src / "Scripts" / "make-silent-atmos.swift"
    produced = src / "Sources" / "AetherEngine" / "Resources" / "silent-atmos.mp4"
    target = vendor / "mplay-silent-atmos.mp4"
    if not script.exists():
        print("WARNING: make-silent-atmos.swift not found in pinned AetherEngine; skipping", flush=True)
        return
    if not shutil.which("swift") or not shutil.which("ffmpeg"):
        print("WARNING: swift/ffmpeg missing; silent-atmos generation skipped "
              "(AtmosOutputActivator will be inert)", flush=True)
        return
    result = subprocess.run(["swift", str(script)], cwd=src)
    if result.returncode != 0 or not produced.exists():
        print("WARNING: silent-atmos generation did not produce "
              f"{produced}; activator will be inert", flush=True)
        return
    shutil.copy2(produced, target)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    print(f"silent-atmos: -> {target} sha256={digest}", flush=True)


def main():
    assert len(sys.argv) == 2, "usage: build_spatial.py <repo-root>"
    root = Path(sys.argv[1]).resolve()
    cache = root / ".cache353" / "spatial"
    cache.mkdir(parents=True, exist_ok=True)
    vendor = root / "Vendor"
    vendor.mkdir(parents=True, exist_ok=True)

    for name, (url, commit, xcframework_name) in PINS.items():
        src = cache / name
        clone_pinned(name, url, commit, src)
        if xcframework_name:
            build_decoder(name, src, xcframework_name, vendor)
        else:
            generate_silent_atmos(src, vendor)
    print("spatial build complete", flush=True)


if __name__ == "__main__":
    main()
