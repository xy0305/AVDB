#!/usr/bin/env python3
"""Build 353 — Libmpv native build pipeline for AVDB (CI only).

Ported verbatim (modulo the AVDB naming below) from AVFan's
scripts/mplaykit59/build_libmpv.py, which is verified green in AVFan
CI run 45239463298 (AVFan-unsigned-112).  This repo's first run is
still 待验证 — see README.md for the first-run failure points.
CI round numbers cited in comments below are that shared pipeline's
history (the AVFan rounds where each fix was proven), not AVDB's own
run numbering.

Builds a single static Libmpv.xcframework (device + simulator, arm64,
iOS 17.0 minimum) from pinned upstream tarballs:

  FFmpeg / mpv / libplacebo / dav1d / libass / freetype / harfbuzz /
  fribidi / xxHash / uchardet / lcms2 — versions and sha256 are pinned
  in COMPONENTS below (verified by actual download; do not bump without
  re-pinning the hashes).

Output:  <repo-root>/Vendor/Libmpv.xcframework
Cache:   <repo-root>/.cache353/{downloads,src,build,cross,venv}
         One <stage>.stamp per (platform, stage); re-runs skip finished
         stages.  --force clears the stamps (and per-platform build dirs).

Usage:
  python3 scripts/mplaykit353/build_libmpv.py <repo-root> \
      [--platforms device,simulator] [--force]

Version basis (IOS-FINDINGS §3/§5): the original iOS binary embeds
`mpv v0.41.0` and its full meson configure string, so mpv is pinned to
0.41.0 (an earlier revision of this pipeline pinned 0.42.0 from the
Android profile, which carries no version string).  The original's
meson parameters vs. ours, item by item:

  original: -Dgl=disabled -Dlibmpv=true -Dcplayer=false -Dgpl=false
            -Diconv=enabled -Dlcms2=enabled -Dlibavdevice=enabled
            -Duchardet=enabled -Dzlib=enabled -Daudiounit=enabled
            -Davfoundation=enabled -Dlua=disabled
            -Dauto_features=disabled -Ddefault_library=static
  ours:     lcms2=enabled and uchardet=enabled now match (both
            components are built below); lua/audiounit/libmpv/static
            already matched.  Since the full-restoration round
            (Build 353 stage A), GL matches too: the display pipeline
            is now the original's pixel-frame design, so mpv is built
            -Dgl=disabled and a vendored patch adds the private
            frame_output vo (patches/0001-vo-frame-output.patch,
            applied to the extracted mpv tree by fetch_all()).
            Remaining deliberate divergences:
            * libavdevice (FFmpeg device input) stays off: no
              device/disc input sources are needed (recorded in
              Build353-MPlayKit.md).
            * mpv's avfoundation AO is explicitly disabled — an
              UNRESOLVED difference (not an accepted deviation),
              forced by stock mpv for now: the feature is `auto`
              and autodetects ON against the iOS SDK, and stock
              ao_avfoundation.m cannot compile there
              (setAudioOutputDeviceUniqueID: is API_UNAVAILABLE on
              iOS); worse, HAVE_AVFOUNDATION un-guards the macOS-only
              AudioDeviceID/AudioStreamID declarations in
              ao_coreaudio_utils.h / ao_coreaudio_chmap.h, which
              ao_audiounit.m includes unconditionally, so the iOS AO
              itself fails (CI round 6: 10 errors in ao_audiounit.m).
              The original fork's ao code compiles on iOS, stock
              does not.  With coreaudio and avfoundation both off,
              audiounit stays enabled and everything it calls from
              those headers is declared outside the guard.  Whether
              the audio output path and perceived sound match the
              original's is to be judged by a same-title device A/B
              against the original player; if they fall short, the
              iOS-usable parts of that ao are to be ported following
              the original's symbol surface.  Recorded in
              Build353-MPlayKit.md as deviation 12.
            * -Dauto_features stays unset; instead every unwanted
              feature is disabled explicitly in build_mpv().
            * libplacebo is still built (it is a hard dependency of
              mpv 0.41 — meson.build declares it without required:
              false), but with vulkan=disabled and opengl=disabled:
              upstream libplacebo explicitly supports a
              no-graphics-API build (src/meson.build only warns), and
              in the pixel-frame design nothing consumes a GPU
              backend at runtime — the original's iOS build likewise
              carries libplacebo compiled-but-unused (IOS-FINDINGS
              §3.2).  Our Metal post chain (stage C) replaces its
              tone-mapping role in the frame-after domain.

Platform notes (verified against the mpv 0.41.0 / 0.42.0 sources by
direct diff, not guessed):
  * Option sets are identical between 0.41 and 0.42 except four options
    added in 0.42 (amf, dvda, libcurl, subrandr); no option we pass was
    removed, renamed, or changed type/default.  There is no plain
    `videotoolbox`, `sdl2`, or `test` option in either version — the
    real names are videotoolbox-gl / videotoolbox-pl, sdl2-{audio,
    video,gamepad} (all default-disabled), and `tests`.
  * mpv 0.41 requires libplacebo >= 6.338.2 (0.42 raised the floor to
    >= 7.387.0).  The pinned libplacebo 7.387.0 satisfies both floors
    (meson only sets a minimum), so it is kept unchanged.
  * mpv finds uchardet and lcms2 via pkg-config dependencies
    (`dependency('uchardet')`, `dependency('lcms2', version: '>= 2.6')`);
    both are built into the per-platform prefix below.
  * -Dvulkan=disabled is legal for mpv: the vulkan option is
    get_option('vulkan').require(libplacebo-has-vulkan).  libplacebo is
    therefore built -Dvulkan=disabled -Dopengl=enabled (the OpenGL backend
    needs neither glslang nor shaderc).
  * GL is fully disabled (stage A): -Dgl=disabled also turns off
    plain-gl / videotoolbox-gl / videotoolbox-pl (all are .require()
    chains on gl or libplacebo in mpv's meson logic, and meson_args()
    passes them as disabled explicitly so the intent is visible in
    the configure log).  The libmpv render API is still available in
    its software form (MPV_RENDER_API_TYPE_SW), which is what
    MPlayPreviewReader uses for offscreen still capture; the main
    display path does not use the render API at all.
  * ao_audiounit (audiounit) only requires darwin and works on iOS;
    coreaudio does not exist on iOS.
  * Every optional mpv/libplacebo/libass/... -D flag goes through
    meson_args(), which greps the extracted meson.options /
    meson_options.txt first and only passes options that actually exist,
    so an unknown option can never fail the configure step.
  * pkg-config supply (ported from the AVDB pipeline fix): PKG_CONFIG_
    LIBDIR is pinned to the vendored prefix, so the SDK's system zlib —
    named in freetype2.pc's Requires.private — is described by a
    hand-written zlib.pc (write_system_pcs), and the cross files set
    no sys_root, because meson would export it as PKG_CONFIG_SYSROOT_
    DIR and pkg-config would relocate the prefix's own absolute paths
    into the SDK, breaking every vendored .pc lookup.

This script is written on Linux and has never run end-to-end in this
repo: the identical pipeline is verified green in AVFan CI (run
45239463298, AVFan-unsigned-112).  See README.md for the first-run
failure points.
"""
import argparse, hashlib, os, re, shutil, subprocess, sys, tarfile
from pathlib import Path

# ---------------------------------------------------------------- pinned ---
# name, version, url, sha256 — coordinator downloaded each tarball and
# computed the sha256 by hand.  Copy verbatim; changing a version without
# changing its hash (or vice versa) must fail the assert in fetch().
COMPONENTS = [
    ("ffmpeg",    "8.0.1",
     "https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz",
     "05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41"),
    ("mpv",       "0.41.0",     # IOS-FINDINGS §5: original iOS binary is mpv v0.41.0
     "https://github.com/mpv-player/mpv/archive/refs/tags/v0.41.0.tar.gz",
     "ee21092a5ee427353392360929dc64645c54479aefdb5babc5cfbb5fad626209"),
    ("libplacebo", "7.387.0",   # mpv 0.41 floor is >= 6.338.2; meson sets
                                # only a minimum, so the 7.387.0 pin (the
                                # old 0.42 floor) still satisfies it — kept.
     "https://code.videolan.org/videolan/libplacebo/-/archive/v7.387.0/libplacebo-v7.387.0.tar.gz",
     "3bf5d72786682c194387c33d563872f6bfe202a9816f9dde6535a31a9b2e0d74"),
    ("dav1d",     "1.5.1",
     "https://downloads.videolan.org/pub/videolan/dav1d/1.5.1/dav1d-1.5.1.tar.xz",
     "401813f1f89fa8fd4295805aa5284d9aed9bc7fc1fdbe554af4292f64cbabe21"),
    ("libass",    "0.17.4",
     "https://github.com/libass/libass/releases/download/0.17.4/libass-0.17.4.tar.xz",
     "78f1179b838d025e9c26e8fef33f8092f65611444ffa1bfc0cfac6a33511a05a"),
    ("freetype",  "2.13.3",
     "https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.xz",
     "0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289"),
    ("harfbuzz",  "15.2.0",
     "https://github.com/harfbuzz/harfbuzz/releases/download/15.2.0/harfbuzz-15.2.0.tar.xz",
     "e2ec49090744383cdbe7df808c1cedaafba06a97be8dc4211fe546ba585f12cb"),
    ("fribidi",   "1.0.16",     # matches FriBidi 1.0.16 in the Android profile
     "https://github.com/fribidi/fribidi/releases/download/v1.0.16/fribidi-1.0.16.tar.xz",
     "1b1cde5b235d40479e91be2f0e88a309e3214c8ab470ec8a2744d82a5a9ea05c"),
    ("xxhash",    "0.8.3",
     "https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.3.tar.gz",
     "aae608dfe8213dfd05d909a57718ef82f30722c392344583d3f39050c7f29a80"),
    ("uchardet",  "0.0.8",      # IOS-FINDINGS §3.1: original has -Duchardet=enabled
     "https://www.freedesktop.org/software/uchardet/releases/uchardet-0.0.8.tar.xz",
     "e97a60cfc00a1c147a674b097bb1422abd9fa78a2d9ce3f3fdcc2e78a34ac5f0"),
    ("lcms2",     "2.16",       # IOS-FINDINGS §3.1: original has -Dlcms2=enabled;
                                # mpv 0.41 requires lcms2 >= 2.6 via pkg-config
     "https://github.com/mm2/Little-CMS/releases/download/lcms2.16/lcms2-2.16.tar.gz",
     "d873d34ad8b9b4cea010631f1a6228d2087475e4dc5e763eb81acc23d9d45a51"),
]
BY_NAME = {c[0]: c for c in COMPONENTS}
MIN_IOS = "17.0"  # == IPHONEOS_DEPLOYMENT_TARGET in AVDB.xcodeproj

PLATFORMS = {
    # name: (sdk name for xcrun, -m<os>-version-min flag stem)
    "device":    ("iphoneos",        "ios"),
    "simulator": ("iphonesimulator", "ios-simulator"),
}
HERE = Path(__file__).resolve().parent

# ------------------------------------------------------------ small utils ---
def run(cmd, stage, env=None, cwd=None):
    """subprocess with check=True ('set -e' semantics); on failure print the
    stage name and the tail of the captured output, then re-raise."""
    print("+", " ".join(str(c) for c in cmd), flush=True)
    p = subprocess.run([str(c) for c in cmd], env=env, cwd=cwd,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True)
    if p.stdout:
        print(p.stdout[-8000:] if p.returncode else p.stdout, flush=True)
    if p.returncode != 0:
        tail = "\n".join((p.stdout or "").splitlines()[-40:])
        print(f"FAILED stage={stage}\n--- log tail ---\n{tail}", flush=True)
        raise subprocess.CalledProcessError(p.returncode, cmd)
    return p

def out(cmd, stage="probe"):
    return run(cmd, stage).stdout.strip()

def sha256_of(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def stamped(build_dir, stage):
    return (build_dir / f"{stage}.stamp").exists()

def stamp(build_dir, stage):
    (build_dir / f"{stage}.stamp").write_text("ok\n")
    print("done", stage, flush=True)

def skip_if_stamped(build_dir, stage):
    if stamped(build_dir, stage):
        print("skip (stamped)", stage, flush=True)
        return True
    return False

# ------------------------------------------------------------- bootstrap ----
def bootstrap(cache):
    """venv with meson/ninja/jinja2/glad2 (libplacebo codegen needs
    jinja2 on PATH via the venv python, and its OpenGL backend probes
    for a Python module named `glad` >= 2.0); host must provide
    pkg-config, xcrun, cmake (freetype and uchardet are built with
    cmake)."""
    for tool in ("pkg-config", "xcrun", "cmake"):
        assert shutil.which(tool), f"missing host tool: {tool}"
    venv = cache / "venv"
    py = venv / "bin" / "python3"
    if not py.exists():
        run([sys.executable, "-m", "venv", venv], "bootstrap-venv")
    # glad2 is the PyPI distribution of upstream Dav1dde/glad 2.x: it
    # installs the importable module `glad` (__version__ 2.0.8, verified
    # locally) that libplacebo's src/opengl/include/glad/meson.build
    # probes via `import glad; print(glad.__version__)` and later runs
    # as `python -m glad`.  The PyPI package literally named `glad` is
    # only the old 0.1.x line and must NOT be used here.  (This profile
    # builds libplacebo with OpenGL disabled, so the glad probe is not
    # live here; the bootstrap is kept parallel with AVFan's.)
    run([py, "-m", "pip", "install", "--upgrade",
         "meson", "ninja", "jinja2", "glad2==2.0.8"], "bootstrap-pip")
    env = dict(os.environ)
    env["PATH"] = f"{venv / 'bin'}:{env.get('PATH', '')}"
    # meson/ninja resolve to the venv copies; python3 too (jinja2 import).
    return env

def sdk_path(sdk):
    # Never hard-code /Applications/Xcode.app/... — always ask xcrun.
    return out(["xcrun", "--sdk", sdk, "--show-sdk-path"], "sdk-path")

def tool_path(name, sdk):
    return out(["xcrun", "--sdk", sdk, "-f", name], "tool-path")

# ------------------------------------------------------------ fetch/src ----
# Fallback download URLs, verified byte-identical to the pinned sha256
# (downloaded and hashed by hand on 2026-11-23).  Only freetype has one:
# the GitHub release asset 404s, ftp.gnu.org/kernel.org don't mirror
# freetype, and the GitHub/GitLab archives of libplacebo/dav1d hash
# differently from their release tarballs — those stay retry-only.
FALLBACK_URLS = {
    "freetype": [
        "https://download-mirror.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.xz",
    ],
}


def download_with_retries(urls, dst, attempts=4):
    """Download dst, trying each URL in order.  Savannah (freetype's host)
    answered HTTP 504 twice in CI on 2026-11-23 and the old code died on
    the first failure with no retry.  5xx and connection errors are
    retried with exponential back-off (2/4/8 s); 4xx is not retryable on
    the same URL.  A partial file is deleted before every retry, and
    fetch_all() still verifies the sha256 afterwards."""
    import time
    import urllib.error
    import urllib.request
    last_err = None
    for url in urls:
        for i in range(attempts):
            try:
                print(f"download {url} (try {i + 1}/{attempts})", flush=True)
                urllib.request.urlretrieve(url, dst)
                return
            except urllib.error.HTTPError as e:
                last_err = e
                if e.code < 500:
                    break
                print(f"download {url}: HTTP {e.code}, retrying", flush=True)
            except (urllib.error.URLError, TimeoutError, ConnectionError,
                    OSError) as e:
                last_err = e
                print(f"download {url}: {e}, retrying", flush=True)
            if dst.exists():
                dst.unlink()
            time.sleep(2 ** (i + 1))
        print(f"download {url}: exhausted retries", flush=True)
    raise last_err


# libplacebo's release tarball omits its git submodules: the extracted
# tree contains empty 3rdparty/ directories.  Two of those are needed
# even in this pipeline's configuration: fast_float (below) and
# Vulkan-Headers (further below).  fast_float: src/convert.cc prefers
# <fast_float/fast_float.h> and only falls back to std::from_chars
# where the toolchain provides the floating-point overloads, so relying
# on the fallback makes the build toolchain-dependent.  The v7.387.0
# gitlink for 3rdparty/fast_float is commit
# 97b54ca9e75f5303507699d27c6b4f4efe4641a1, which is exactly the
# v8.2.2 tag; vendor that tag's include/ tree (sha256 pinned, verified
# locally on 2026-11-23) into the extracted libplacebo tree.
FAST_FLOAT_URL = ("https://github.com/fastfloat/fast_float/archive/"
                  "refs/tags/v8.2.2.tar.gz")
FAST_FLOAT_SHA256 = ("e64b5fff88e04959154adbd5fb83331d91f2e04ac0645467"
                     "1cdfcbdff172b158")


def vendor_libplacebo_fast_float(cache, libplacebo_src):
    header = (libplacebo_src / "3rdparty" / "fast_float" / "include"
              / "fast_float" / "fast_float.h")
    if header.exists():
        return
    (cache / "downloads").mkdir(parents=True, exist_ok=True)
    (cache / "src").mkdir(parents=True, exist_ok=True)
    dl = cache / "downloads" / "fast_float-v8.2.2.tar.gz"
    if not dl.exists() or sha256_of(dl) != FAST_FLOAT_SHA256:
        download_with_retries([FAST_FLOAT_URL], dl)
    got = sha256_of(dl)
    assert got == FAST_FLOAT_SHA256, ("fast_float", got)
    dest = cache / "src" / "fast_float-8.2.2"
    if not dest.exists():
        print("extract", dl.name, "->", dest, flush=True)
        with tarfile.open(dl) as t:
            t.extractall(cache / "src")
        assert dest.is_dir(), dest
    target = libplacebo_src / "3rdparty" / "fast_float"
    target.mkdir(parents=True, exist_ok=True)
    shutil.copytree(dest / "include", target / "include",
                    dirs_exist_ok=True)
    assert header.exists(), header
    print("vendored fast_float 8.2.2 into libplacebo 3rdparty", flush=True)


# Vulkan-Headers is needed even with -Dvulkan=disabled: the disabled
# branch of src/vulkan/meson.build still compiles src/vulkan/stubs.c,
# which includes the public <libplacebo/vulkan.h>, and that header
# includes <vulkan/vulkan.h> unconditionally (CI round 5 died there:
# 'vulkan/vulkan.h' file not found while compiling vulkan_stubs.c.o).
# meson adds the headers dependency to build_deps unconditionally and
# prefers 3rdparty/Vulkan-Headers whenever its include/ exists
# (src/vulkan/meson.build:8-14), so vendoring the headers is the
# upstream-intended supply route; the vulkan feature itself stays
# disabled — only the headers are provided.  The v7.387.0 gitlink for
# 3rdparty/Vulkan-Headers is commit
# 74d8a6cb930c68ef617b202c3ff3c59d919e086b; vendor that commit's
# include/ + registry/ trees (sha256 pinned, verified locally on
# 2026-11-23) into the extracted libplacebo tree.
VULKAN_HEADERS_COMMIT = "74d8a6cb930c68ef617b202c3ff3c59d919e086b"
VULKAN_HEADERS_URL = ("https://github.com/KhronosGroup/Vulkan-Headers/"
                      f"archive/{VULKAN_HEADERS_COMMIT}.tar.gz")
VULKAN_HEADERS_SHA256 = ("75967a8288ff16044a86d1af462b96d2e75c435937efb75f2"
                         "bb4102ab0382f29")


def vendor_libplacebo_vulkan_headers(cache, libplacebo_src):
    header = (libplacebo_src / "3rdparty" / "Vulkan-Headers" / "include"
              / "vulkan" / "vulkan.h")
    if header.exists():
        return
    (cache / "downloads").mkdir(parents=True, exist_ok=True)
    (cache / "src").mkdir(parents=True, exist_ok=True)
    dl = cache / "downloads" / f"Vulkan-Headers-{VULKAN_HEADERS_COMMIT}.tar.gz"
    if not dl.exists() or sha256_of(dl) != VULKAN_HEADERS_SHA256:
        download_with_retries([VULKAN_HEADERS_URL], dl)
    got = sha256_of(dl)
    assert got == VULKAN_HEADERS_SHA256, ("Vulkan-Headers", got)
    dest = cache / "src" / f"Vulkan-Headers-{VULKAN_HEADERS_COMMIT}"
    if not dest.exists():
        print("extract", dl.name, "->", dest, flush=True)
        with tarfile.open(dl) as t:
            t.extractall(cache / "src")
        assert dest.is_dir(), dest
    target = libplacebo_src / "3rdparty" / "Vulkan-Headers"
    target.mkdir(parents=True, exist_ok=True)
    for sub in ("include", "registry"):
        shutil.copytree(dest / sub, target / sub, dirs_exist_ok=True)
    assert header.exists(), header
    assert (target / "registry" / "vk.xml").exists()
    print("vendored Vulkan-Headers", VULKAN_HEADERS_COMMIT,
          "into libplacebo 3rdparty", flush=True)


def fetch_all(cache):
    import urllib.request
    dl, src_root = cache / "downloads", cache / "src"
    dl.mkdir(parents=True, exist_ok=True); src_root.mkdir(parents=True, exist_ok=True)
    srcs = {}
    for name, ver, url, sha in COMPONENTS:
        dst = dl / url.rsplit("/", 1)[1]
        if not dst.exists() or sha256_of(dst) != sha:
            download_with_retries([url] + FALLBACK_URLS.get(name, []), dst)
        got = sha256_of(dst)
        assert got == sha, (name, got, sha)
        dest = src_root / f"{name}-{ver}"
        if not dest.exists():
            print("extract", dst.name, "->", dest, flush=True)
            with tarfile.open(dst) as t:
                t.extractall(src_root)
            # GitHub/Videolan archives unpack to <name>-<version> (libplacebo:
            # libplacebo-v7.387.0); normalise whatever single top dir appeared.
            if not dest.exists():
                cands = [p for p in src_root.iterdir()
                         if p.is_dir() and p.name.startswith(name)]
                assert len(cands) == 1, (name, cands)
                cands[0].rename(dest)
        assert dest.is_dir(), dest
        srcs[name] = dest
    vendor_libplacebo_fast_float(cache, srcs["libplacebo"])
    vendor_libplacebo_vulkan_headers(cache, srcs["libplacebo"])
    apply_patches(srcs["mpv"])
    return srcs

# -------------------------------------------------------------- patches ----
def _git_apply_dir_args(mpv_src):
    """Extra git-apply arguments that make patch paths land inside
    mpv_src even when the tree sits inside an enclosing git repository
    (the CI layout: .cache353/src/mpv-0.41.0 inside the AVDB checkout).
    git apply resolves patch paths against the enclosing repo's root
    and silently SKIPS every file outside the current directory's
    prefix — exit code 0, nothing applied, --check equally vacuous.
    Through CI round 9 that meant the frame_output patch never landed
    on the runner at all and libmpv was quietly built stock.
    rev-parse --show-prefix gives the tree's path relative to the repo
    root; feeding it back as --directory re-roots the patch paths into
    the tree.  Outside a repo there is no prefix and plain git apply
    already resolves against the tree itself."""
    p = subprocess.run(["git", "-C", str(mpv_src), "rev-parse",
                        "--show-prefix"], capture_output=True, text=True)
    if p.returncode == 0 and p.stdout.strip():
        return ["--directory=" + p.stdout.strip()]
    return []

def apply_patches(mpv_src):
    """Apply the vendored patch series (scripts/mplaykit353/patches/*.patch)
    to the extracted mpv tree.  Idempotent across cached re-runs: a
    marker file inside the (cache-local) source tree records success,
    and a reverse --check recognises an already-applied tree if the
    marker was lost.  A patch that neither applies nor is already
    applied is a hard failure — silently building unpatched mpv would
    remove the frame_output vo the whole display pipeline rests on.

    The digest marker alone is NOT accepted as proof the patches
    landed: git apply can skip every file and still exit 0 (see
    _git_apply_dir_args), and exactly that left a valid-looking marker
    on an unpatched tree in CI.  The skip path therefore also requires
    the series' signature file in the tree and a passing reverse
    --check of the series' head patch.

    Applied-state accounting is by prefix digest: the marker records
    the digest of the series as it stood when last applied here, and
    the series only ever grows by appending, so a marker equal to the
    digest of the first k patches means exactly those k are in the
    tree and only the rest need applying.  (Per-patch reverse --check
    cannot detect this state: it fails the moment a later patch
    touches a file an earlier one created — the normal stacked state,
    which killed the first version of this accounting in round 12.)"""
    patch_dir = HERE / "patches"
    patches = sorted(patch_dir.glob("*.patch"))
    if not patches:
        return
    prefix_digests = []
    running = hashlib.sha256()
    for patch in patches:
        running.update(patch.read_bytes())
        prefix_digests.append(running.hexdigest())
    want = prefix_digests[-1]
    marker = mpv_src / ".mplaykit353-patches.stamp"
    sentinel = mpv_src / "include" / "mpv" / "frame_output.h"
    recorded = (marker.read_text().strip() if marker.exists() else None)
    args = _git_apply_dir_args(mpv_src)

    def head_is_applied():
        rev = subprocess.run(["git", "-C", str(mpv_src), "apply", *args,
                              "--reverse", "--check", str(patches[-1])],
                             capture_output=True, text=True)
        return rev.returncode == 0

    if recorded == want and sentinel.is_file() and head_is_applied():
        print("skip (marker) mpv patches", flush=True)
        return
    applied = 0
    if recorded is not None:
        for k, d in enumerate(prefix_digests[:-1], start=1):
            if recorded == d:
                applied = k
                break
    if applied and not sentinel.is_file():
        # The marker claims early patches are in, but the series'
        # signature file is absent — the marker is lying (the
        # git-apply skip era wrote exactly such markers onto pristine
        # trees).  Recount from zero; the forward checks below sort
        # out what is really there.
        print("patch marker inconsistent with tree (no sentinel); "
              "recounting from zero", flush=True)
        applied = 0
    applied_any = False
    for patch in patches[applied:]:
        fwd = subprocess.run(["git", "-C", str(mpv_src), "apply", *args,
                              "--check", str(patch)],
                             capture_output=True, text=True)
        assert fwd.returncode == 0, (
            f"patch {patch.name} does not apply and the marker does "
            f"not account for it (recorded series digest: {recorded}); "
            f"the series is append-only — if a patch file was edited "
            f"after being applied, delete .cache353/src and re-run:\n"
            f"{fwd.stdout}\n{fwd.stderr}")
        run(["git", "-C", str(mpv_src), "apply", *args, str(patch)],
            f"patch-{patch.name}")
        applied_any = True
    # git apply's exit code is not evidence (it skips silently, above):
    # verify the series' signature files are really in the tree and
    # the head patch's postimage really holds.
    assert sentinel.is_file(), (
        f"patches reported applied but {sentinel} is missing — "
        f"git apply must have skipped them (see _git_apply_dir_args)")
    assert (mpv_src / "video" / "out" / "vo_frame_output.c").is_file(), (
        "patches reported applied but vo_frame_output.c is missing")
    assert head_is_applied(), (
        "patches reported applied but the head patch's postimage "
        "does not hold in the tree")
    marker.write_text(want + "\n")
    print("mpv patches applied:", ", ".join(p.name for p in patches),
          flush=True)
    if applied_any:
        # The tree changed under already-stamped build stages — a
        # restored cache can hold a stock mpv stamped as done.  Drop
        # the mpv and framework stamps for every platform so the
        # patched tree is what actually gets built and assembled.
        cache = mpv_src.parents[1]
        for platform in PLATFORMS:
            build_dir = cache / "build" / platform
            for stamp_file in build_dir.glob("mpv*.stamp"):
                stamp_file.unlink()
            for stamp_file in build_dir.glob("framework-*.stamp"):
                stamp_file.unlink()
        print("invalidated mpv/framework stamps (patch state changed)",
              flush=True)

# --------------------------------------------------------- meson helpers ----
def meson_option_names(src):
    """Option names declared by a source tree (meson.options is the modern
    spelling, meson_options.txt the legacy one)."""
    names = set()
    for fn in ("meson.options", "meson_options.txt"):
        f = src / fn
        if f.exists():
            names |= set(re.findall(r"option\(\s*'([^']+)'", f.read_text()))
            names |= set(re.findall(r'option\(\s*"([^"]+)"', f.read_text()))
    return names

def meson_args(src, wanted):
    """Defensive -D passing: only forward options the project declares.
    `wanted` is an ordered dict name -> value (str/bool)."""
    have = meson_option_names(src)
    args = []
    for k, v in wanted.items():
        if k not in have:
            print(f"  (skip -D{k}: not an option of {src.name})", flush=True)
            continue
        if isinstance(v, bool):
            v = "true" if v else "false"
        args.append(f"-D{k}={v}")
    return args

def write_cross_file(cache, platform, env):
    sdk_name, stem = PLATFORMS[platform]
    tpl_name = ("ios-device-arm64.meson.txt" if platform == "device"
                else "ios-simulator-arm64.meson.txt")
    tpl = (HERE / "cross" / tpl_name).read_text()
    sdk = sdk_path(sdk_name)
    text = (tpl.replace("__SDK_PATH__", sdk)
               .replace("__SDK_NAME__", sdk_name)
               .replace("__CLANG__", tool_path("clang", sdk_name))
               .replace("__CLANGXX__", tool_path("clang++", sdk_name))
               .replace("__AR__", tool_path("ar", sdk_name))
               .replace("__RANLIB__", tool_path("ranlib", sdk_name))
               .replace("__STRIP__", tool_path("strip", sdk_name))
               .replace("__MIN_FLAG__", f"-m{stem}-version-min={MIN_IOS}"))
    dest_dir = cache / "cross"; dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / tpl_name
    dest.write_text(text)
    assert "__" not in dest.read_text().replace("__", "", 0) or \
        not re.search(r"__[A-Z_]+__", dest.read_text()), dest
    return dest, sdk

def meson_build(src, bdir, prefix, cross, env, wanted, stage, extra=None):
    if bdir.exists():
        shutil.rmtree(bdir)
    args = [env_meson(env), "setup", bdir, src,
            f"--prefix={prefix}", "--cross-file", cross,
            "--buildtype=release", "--default-library=static"]
    args += meson_args(src, wanted)
    args += extra or []
    run(args, stage, env=env)
    run([env_meson(env), "compile", "-C", bdir], stage, env=env)
    run([env_meson(env), "install", "-C", bdir], stage, env=env)

def env_meson(env):
    return str(Path(env["PATH"].split(":")[0]) / "meson")

def pkg_env(prefix, env):
    e = dict(env)
    pc = str(prefix / "lib" / "pkgconfig")
    e["PKG_CONFIG_PATH"] = pc + (":" + e["PKG_CONFIG_PATH"]
                                 if e.get("PKG_CONFIG_PATH") else "")
    e["PKG_CONFIG_LIBDIR"] = pc
    return e

def write_system_pcs(prefix, sdk):
    """Hand-written .pc files for system libraries that chain members
    resolve through pkg-config (same pattern as libxxhash.pc below).

    pkg_env() pins PKG_CONFIG_LIBDIR to the vendored prefix, which
    hides the SDK's own pkg-config files entirely — so when an
    installed .pc names a system library in Requires.private
    (freetype2.pc -> zlib: freetype is built FT_WITH_ZLIB=ON against
    the SDK's libz), pkg-config fails the whole lookup ("Package
    'zlib', required by 'freetype2', not found") and meson reports the
    *consumer's* dependency as missing — that is what killed the
    harfbuzz stage in AVDB's first CI run of this same pipeline.
    mpv's dependency('zlib') (required, both 0.41 and 0.42) and
    FFmpeg's check_pkg_config(zlib) hit the same wall.  Describe the
    SDK's system zlib with absolute paths (the cross files
    deliberately set no sys_root, so nothing relocates them).
    Written unconditionally at platform start so a cached prefix from
    an earlier, failed run picks the file up without --force."""
    pc_dir = prefix / "lib" / "pkgconfig"
    pc_dir.mkdir(parents=True, exist_ok=True)
    (pc_dir / "zlib.pc").write_text(
        f"prefix={sdk}/usr\nlibdir=${{prefix}}/lib\n"
        f"includedir=${{prefix}}/include\n\n"
        f"Name: zlib\n"
        f"Description: zlib compression library (system library from "
        f"the iOS SDK)\n"
        # == version CMake's FindZLIB reports for the SDK's libz.tbd.
        f"Version: 1.2.12\n"
        f"Libs: -L${{libdir}} -lz\nCflags: -I${{includedir}}\n")

# ------------------------------------------------------------- stages -------
def build_xxhash(src, build_dir, prefix, platform, env):
    """xxHash is a single C file: compile libxxhash.a directly and write
    the libxxhash.pc that libplacebo (-Dxxhash=enabled) looks up."""
    stage = "xxhash"
    if skip_if_stamped(build_dir, stage): return
    sdk_name, stem = PLATFORMS[platform]
    sdk = sdk_path(sdk_name)
    cc = tool_path("clang", sdk_name)
    work = build_dir / "xxhash"; work.mkdir(parents=True, exist_ok=True)
    cflags = ["-arch", "arm64", f"-m{stem}-version-min={MIN_IOS}",
              "-isysroot", sdk, "-O2", "-fPIC", "-DXXH_INLINE_ALL=0"]
    run([cc, *cflags, "-I", src, "-c", src / "xxhash.c",
         "-o", work / "xxhash.o"], stage, env=env)
    libdir = prefix / "lib"; libdir.mkdir(parents=True, exist_ok=True)
    run([tool_path("ar", sdk_name), "rcs", libdir / "libxxhash.a",
         work / "xxhash.o"], stage, env=env)
    run([tool_path("ranlib", sdk_name), libdir / "libxxhash.a"], stage, env=env)
    inc = prefix / "include"; inc.mkdir(parents=True, exist_ok=True)
    shutil.copy(src / "xxhash.h", inc / "xxhash.h")
    if (src / "xxh3.h").exists():
        shutil.copy(src / "xxh3.h", inc / "xxh3.h")
    pc = prefix / "lib" / "pkgconfig" / "libxxhash.pc"
    pc.parent.mkdir(parents=True, exist_ok=True)
    pc.write_text(
        f"prefix={prefix}\nlibdir=${{prefix}}/lib\nincludedir=${{prefix}}/include\n\n"
        f"Name: libxxhash\nDescription: xxHash (353 vendored build)\n"
        f"Version: {BY_NAME['xxhash'][1]}\nLibs: -L${{libdir}} -lxxhash\n"
        f"Cflags: -I${{includedir}}\n")
    stamp(build_dir, stage)

def build_freetype(src, build_dir, prefix, platform, env, with_harfbuzz, tag):
    """freetype via cmake.  Pass 1 (tag=ft1) builds without harfbuzz to
    break the freetype <-> harfbuzz cycle; pass 2 (tag=ft2) rebuilds with
    harfbuzz once harfbuzz exists in the prefix.  External deps off except
    the system zlib."""
    stage = f"freetype-{tag}"
    if skip_if_stamped(build_dir, stage): return
    sdk_name, stem = PLATFORMS[platform]
    sdk = sdk_path(sdk_name)
    bdir = build_dir / f"freetype-{tag}"
    if bdir.exists(): shutil.rmtree(bdir)
    minflag = f"-m{stem}-version-min={MIN_IOS}"
    args = ["cmake", "-S", src, "-B", bdir,
            "-DCMAKE_SYSTEM_NAME=iOS",
            f"-DCMAKE_OSX_SYSROOT={sdk}",
            "-DCMAKE_OSX_ARCHITECTURES=arm64",
            f"-DCMAKE_OSX_DEPLOYMENT_TARGET={MIN_IOS}",
            "-DCMAKE_BUILD_TYPE=Release",
            "-DBUILD_SHARED_LIBS=OFF",
            f"-DCMAKE_INSTALL_PREFIX={prefix}",
            "-DFT_DISABLE_BZIP2=ON", "-DFT_DISABLE_PNG=ON",
            "-DFT_DISABLE_BROTLI=ON",
            "-DFT_WITH_ZLIB=ON",            # system zlib from the SDK
            "-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH",
            f"-DCMAKE_PREFIX_PATH={prefix}"]
    args.append("-DFT_WITH_HARFBUZZ=ON" if with_harfbuzz
                else "-DFT_DISABLE_HARFBUZZ=ON")
    args.append(f"-DCMAKE_C_FLAGS={minflag}")
    run(args, stage, env=pkg_env(prefix, env))
    run(["cmake", "--build", bdir, "--parallel"], stage, env=env)
    run(["cmake", "--install", bdir], stage, env=env)
    stamp(build_dir, stage)

def build_uchardet(src, build_dir, prefix, platform, env):
    """uchardet via cmake (its only build system in 0.0.8).  Installs
    libuchardet.a + uchardet.pc, which is how mpv's
    dependency('uchardet') finds it.  Mirrors the freetype cmake
    cross-compile setup; BUILD_SHARED_LIBS must be OFF or we get a
    dylib instead of a static archive.

    CMAKE_POLICY_VERSION_MINIMUM=3.5 is passed ONLY here: uchardet
    0.0.8 declares cmake_minimum_required(VERSION 3.1) and modern
    CMake has removed compatibility with < 3.5 (CI error at
    CMakeLists.txt:2, whose own text suggests this flag).  Freetype's
    cmake call is deliberately left untouched.

    BUILD_BINARY=OFF is also passed ONLY here: the CLI tool target is
    a MACOSX_BUNDLE executable under CMAKE_SYSTEM_NAME=iOS, and its
    install() rule in src/tools/CMakeLists.txt:35 has no BUNDLE
    DESTINATION, which modern CMake rejects at configure time
    (CI round 5).  Upstream gates the whole tools subdirectory on
    BUILD_BINARY (src/CMakeLists.txt:177-179) and only the library
    (libuchardet.a + uchardet.pc) is needed, so the tool is skipped
    via the official option rather than patched."""
    stage = "uchardet"
    if skip_if_stamped(build_dir, stage): return
    sdk_name, stem = PLATFORMS[platform]
    sdk = sdk_path(sdk_name)
    bdir = build_dir / "uchardet"
    if bdir.exists(): shutil.rmtree(bdir)
    minflag = f"-m{stem}-version-min={MIN_IOS}"
    args = ["cmake", "-S", src, "-B", bdir,
            "-DCMAKE_SYSTEM_NAME=iOS",
            f"-DCMAKE_OSX_SYSROOT={sdk}",
            "-DCMAKE_OSX_ARCHITECTURES=arm64",
            f"-DCMAKE_OSX_DEPLOYMENT_TARGET={MIN_IOS}",
            "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
            "-DBUILD_SHARED_LIBS=OFF",
            "-DBUILD_BINARY=OFF",
            f"-DCMAKE_INSTALL_PREFIX={prefix}",
            f"-DCMAKE_C_FLAGS={minflag}",
            f"-DCMAKE_CXX_FLAGS={minflag}"]
    run(args, stage, env=pkg_env(prefix, env))
    run(["cmake", "--build", bdir, "--parallel"], stage, env=env)
    run(["cmake", "--install", bdir], stage, env=env)
    stamp(build_dir, stage)

def build_lcms2(src, build_dir, prefix, cross, penv):
    """lcms2 via its own meson build (ships meson.build + pkg.generate,
    so mpv's dependency('lcms2', version: '>= 2.6') resolves from the
    prefix).  jpeg/tiff stay disabled: not present in the iOS prefix
    and not needed for ICC colour management of video."""
    stage = "lcms2"
    if skip_if_stamped(build_dir, stage): return
    meson_build(src, build_dir / "lcms2", prefix, cross, penv,
                {"jpeg": "disabled", "tiff": "disabled"}, stage)
    stamp(build_dir, stage)

def build_platform(platform, srcs, cache, env, force):
    print(f"=== platform {platform} ===", flush=True)
    build_dir = cache / "build" / platform
    prefix = build_dir / "prefix"
    build_dir.mkdir(parents=True, exist_ok=True); prefix.mkdir(parents=True, exist_ok=True)
    if force:
        for s in build_dir.glob("*.stamp"): s.unlink()
    cross, sdk = write_cross_file(cache, platform, env)
    penv = pkg_env(prefix, env)
    write_system_pcs(prefix, sdk)

    build_xxhash(srcs["xxhash"], build_dir, prefix, platform, env)

    # dav1d — meson cross, encoder off (playback-only profile).
    if not skip_if_stamped(build_dir, "dav1d"):
        meson_build(srcs["dav1d"], build_dir / "dav1d", prefix, cross, penv,
                    {"enable_tools": False, "enable_tests": False,
                     "enable_docs": False}, "dav1d")
        stamp(build_dir, "dav1d")

    # freetype (no harfbuzz) -> harfbuzz -> freetype (with harfbuzz).
    build_freetype(srcs["freetype"], build_dir, prefix, platform, env,
                   with_harfbuzz=False, tag="ft1")
    if not skip_if_stamped(build_dir, "harfbuzz"):
        # gpu disabled: harfbuzz 15.2.0's gpu feature defaults to
        # enabled, and on darwin its util/meson.build then calls
        # add_languages('objcpp', required: true) — which the cross
        # files deliberately do not provide.  The feature builds only
        # the separate experimental libharfbuzz-gpu (src/meson.build);
        # libharfbuzz / libharfbuzz-subset, the only outputs freetype
        # and libass resolve via pkg-config, are unaffected.
        meson_build(srcs["harfbuzz"], build_dir / "harfbuzz", prefix, cross,
                    penv,
                    {"freetype": "enabled", "glib": "disabled",
                     "gobject": "disabled", "icu": "disabled",
                     "cairo": "disabled", "gpu": "disabled",
                     "tests": "disabled",
                     "docs": "disabled", "benchmark": "disabled",
                     "introspection": "disabled"}, "harfbuzz")
        stamp(build_dir, "harfbuzz")
    build_freetype(srcs["freetype"], build_dir, prefix, platform, env,
                   with_harfbuzz=True, tag="ft2")

    if not skip_if_stamped(build_dir, "fribidi"):
        meson_build(srcs["fribidi"], build_dir / "fribidi", prefix, cross,
                    penv, {"docs": False, "tests": False, "bin": False},
                    "fribidi")
        stamp(build_dir, "fribidi")

    # libass: on darwin it uses CoreText — fontconfig must stay off.
    if not skip_if_stamped(build_dir, "libass"):
        meson_build(srcs["libass"], build_dir / "libass", prefix, cross, penv,
                    {"fontconfig": "disabled", "libunibreak": "disabled",
                     "tests": "disabled", "test": "disabled",
                     "profile": "disabled"}, "libass")
        stamp(build_dir, "libass")

    # uchardet (subtitle charset detection) and lcms2 (ICC colour
    # management): both enabled in the original's meson parameters
    # (IOS-FINDINGS §3.1); mpv resolves them from this prefix via
    # pkg-config, so they must land before the mpv stage.
    build_uchardet(srcs["uchardet"], build_dir, prefix, platform, env)
    build_lcms2(srcs["lcms2"], build_dir, prefix, cross, penv)

    # libplacebo: no graphics API at all (stage A pixel-frame design).
    # mpv 0.41 hard-depends on libplacebo (its meson.build declares the
    # dependency without required:false), so the stage stays, but with
    # vulkan and opengl both disabled libplacebo builds in its
    # upstream-supported "no graphics API" form (src/meson.build only
    # warns; the dummy GPU and shader-generation utilities remain).
    # Nothing consumes a libplacebo GPU backend at runtime in this
    # profile: vo_gpu/vo_gpu_next are compiled out with gl=disabled,
    # and tone mapping lives in our frame-after Metal chain (stage C),
    # exactly like the original iOS build (IOS-FINDINGS §3.2).
    # xxhash from the vendored build above.  jinja2 comes from the
    # bootstrap venv (its bin/ is first on PATH in env).
    if not skip_if_stamped(build_dir, "libplacebo"):
        meson_build(srcs["libplacebo"], build_dir / "libplacebo", prefix,
                    cross, penv,
                    {"vulkan": "disabled", "opengl": "disabled",
                     "demos": False, "tests": False, "bench": False,
                     "lcms": "disabled", "dovi": "disabled",
                     "xxhash": "enabled", "glslang": "disabled",
                     "shaderc": "disabled", "fuzz": False}, "libplacebo")
        stamp(build_dir, "libplacebo")

    build_ffmpeg(srcs["ffmpeg"], build_dir, prefix, platform, env)
    build_mpv(srcs["mpv"], build_dir, prefix, cross, penv)
    return prefix

def build_ffmpeg(src, build_dir, prefix, platform, env):
    stage = "ffmpeg"
    if skip_if_stamped(build_dir, stage): return
    sdk_name, stem = PLATFORMS[platform]
    sdk = sdk_path(sdk_name)
    bdir = build_dir / "ffmpeg"
    if bdir.exists(): shutil.rmtree(bdir)
    bdir.mkdir(parents=True)
    minflag = f"-m{stem}-version-min={MIN_IOS}"
    # Playback-only profile (mirrors the reverse-engineered Android build):
    # no encoders/muxers beyond null, dav1d + libass in, VideoToolbox hwaccel,
    # and SecureTransport as the TLS backend — the iOS platform equivalent
    # of the OpenSSL seen in the Android profile (--enable-securetransport
    # selects FFmpeg's SecureTransport TLS implementation in FFmpeg 8.0).
    # Filters are NOT pruned beyond --disable-devices: the default filter
    # set already contains tonemap/scale/subtitles/format/fps/aresample.
    hwaccels = ["h264", "hevc", "mpeg2", "mpeg4", "vp9", "prores"]
    args = [src / "configure",
            f"--prefix={prefix}",
            "--target-os=darwin", "--arch=arm64",
            "--enable-cross-compile",
            f"--cc=xcrun -sdk {sdk_name} clang",
            f"--sysroot={sdk}",
            f"--extra-cflags=-arch arm64 {minflag} -isysroot {sdk} "
            f"-I{prefix}/include",
            f"--extra-ldflags=-arch arm64 {minflag} -isysroot {sdk} "
            f"-L{prefix}/lib",
            "--disable-programs", "--disable-doc", "--disable-debug",
            "--enable-static", "--disable-shared",
            "--pkg-config-flags=--static", "--enable-pic",
            "--disable-encoders", "--disable-muxers", "--enable-muxer=null",
            "--disable-devices",
            "--enable-libdav1d", "--enable-libass",
            "--enable-videotoolbox", "--enable-audiotoolbox",
            "--enable-securetransport",
            "--enable-iconv", "--enable-zlib", "--enable-bzlib"]
    # Prefer the --enable-hwaccels umbrella if this configure knows it,
    # otherwise enumerate the VideoToolbox hwaccels one by one.
    help_txt = out([src / "configure", "--help"], "ffmpeg-help")
    if "--enable-hwaccels" in help_txt:
        args.append("--enable-hwaccels")
    else:
        args += [f"--enable-hwaccel={c}_videotoolbox" for c in hwaccels]
    run(args, stage, env=pkg_env(prefix, env), cwd=bdir)
    run(["make", "-j4"], stage, env=env, cwd=bdir)
    run(["make", "install"], stage, env=env, cwd=bdir)
    stamp(build_dir, stage)

def build_mpv(src, build_dir, prefix, cross, penv):
    # Stage name carries a version suffix for the same reason as the
    # framework stage: the stamp is a plain existence check, so a
    # wanted-table change must rename the stage or a restored cache
    # would skip the rebuild and keep the old configuration.
    # v2: ios-gl disabled (see the wanted table comment).
    stage = "mpv-v2"
    if skip_if_stamped(build_dir, stage): return
    # Switch table (all defensive via meson_args): libmpv on, GL fully
    # off (stage A: the display pipeline is the vendored frame_output
    # vo, matching the original's -Dgl=disabled meson parameters,
    # IOS-FINDINGS §3.1); everything platform-foreign or doc/test off.
    # With gl disabled, plain-gl / videotoolbox-gl / videotoolbox-pl
    # are disabled explicitly as well — they are .require() chains on
    # gl/libplacebo and would otherwise sit at "auto".  The
    # VideoToolbox *decoder* path is unaffected: it is FFmpeg hwaccel
    # plus mpv's hwdec_vt device driver, neither needs GL, and frames
    # reach the vo as IMGFMT_VIDEOTOOLBOX (planes[3] =
    # CVPixelBufferRef).
    # gl-cocoa/cocoa and coreaudio are macOS-only and must not be
    # probed on iOS.
    # avfoundation is disabled explicitly: left at auto it turns ON
    # against the iOS SDK and breaks stock mpv twice (its own AO
    # uses an iOS-unavailable API, and HAVE_AVFOUNDATION un-guards
    # macOS device types in headers ao_audiounit.m includes) — see
    # the module docstring's divergence list.  This is an unresolved
    # difference pending a same-title device A/B against the
    # original player, not an accepted deviation: the original
    # fork's ao compiles on iOS, stock does not, and closing the
    # gap may mean porting that ao's iOS-usable parts.
    # ios-gl is disabled explicitly: it is an auto feature whose probe
    # (an OpenGLES header symbol) always succeeds against the iOS SDK,
    # and upstream's gate for hwdec_ios_gl.m requires nothing else —
    # the file then references the ra_gl backend (ra_gl_get,
    # ra_create_wrapped_tex, ...) that gl=disabled leaves unbuilt,
    # so the app link fails with undefined _ra_* symbols (CI round
    # 15).  The frame_output pipeline takes VT frames as
    # CVPixelBuffers and never uses the GL interop hwdec, so nothing
    # is lost; the original fork necessarily did the equivalent.
    # uchardet/lcms2 are enabled to match the original's meson parameters
    # (IOS-FINDINGS §3.1); both are built into the prefix above.
    # Option names verified against mpv 0.41.0 meson.options: there is no
    # plain `videotoolbox` (the GL interop feature is videotoolbox-gl),
    # no plain `sdl2` (split into sdl2-audio/video/gamepad, all already
    # default-disabled), and no `test` (only the `tests` boolean).
    wanted = {
        # cplayer off (as in the original's flags): it defaults to
        # true, and the CLI executable is dead weight in a libmpv-only
        # pipeline — worse, on darwin mpv then also wires the
        # osxbundle/macos-bundle targets and links an iOS executable
        # with the macOS-SDK -isysroot its objc probe injects.
        "cplayer": False,
        "libmpv": True, "gl": "disabled", "plain-gl": "disabled",
        "ios-gl": "disabled",
        "videotoolbox-gl": "disabled", "videotoolbox-pl": "disabled",
        "audiounit": "enabled", "uchardet": "enabled", "lcms2": "enabled",
        "vulkan": "disabled", "gl-cocoa": "disabled", "cocoa": "disabled",
        "coreaudio": "disabled", "avfoundation": "disabled",
        "sdl2-audio": "disabled", "sdl2-video": "disabled",
        "sdl2-gamepad": "disabled",
        "lua": "disabled", "javascript": "disabled",
        "libbluray": "disabled",
        "rubberband": "disabled", "vapoursynth": "disabled",
        "libarchive": "disabled", "dvdnav": "disabled", "cdda": "disabled",
        "x11": "disabled", "wayland": "disabled", "drm": "disabled",
        "gbm": "disabled", "egl": "disabled",
        "manpage-build": "disabled", "html-build": "disabled",
        "pdf-build": "disabled", "tests": False,
    }
    meson_build(src, build_dir / "mpv", prefix, cross, penv, wanted, stage)
    stamp(build_dir, stage)

# ------------------------------------------------------- framework/xc ------
EXPECTED_LIBS = ["libmpv.a", "libavformat.a", "libavcodec.a",
                 "libavutil.a", "libavfilter.a", "libswscale.a",
                 "libswresample.a", "libplacebo.a", "libass.a",
                 "libdav1d.a", "libfreetype.a", "libharfbuzz.a",
                 "libfribidi.a", "libxxhash.a", "libuchardet.a",
                 "liblcms2.a"]
MPV_HEADERS = ["client.h", "render.h", "render_gl.h", "stream_cb.h",
               "frame_output.h"]

def assemble_framework(platform, cache, env):
    # Stage name carries a version suffix: the workflow cache restores
    # the previous run's .cache353 via restore-keys, stamps included, so
    # any assembly-logic change must bump the suffix or the new code is
    # stamp-skipped and never takes effect.  v1 = flat header layout
    # (round 7), v2 = Headers/mpv/ layout but angled umbrella includes
    # (round 8), v3 = quoted umbrella includes + frame_output.h taken
    # from the patched source tree, v4 = libmpv rebuilt without the
    # ios-gl hwdec object (mpv stage v2) — the assembled input changed.
    stage = f"framework-{platform}-v4"
    build_dir = cache / "build" / platform
    if skip_if_stamped(build_dir, stage):
        return build_dir / "Libmpv.framework"
    prefix = build_dir / "prefix"
    libdir = prefix / "lib"
    libs = [libdir / n for n in EXPECTED_LIBS if (libdir / n).exists()]
    missing = [n for n in EXPECTED_LIBS if not (libdir / n).exists()]
    assert libs, f"{platform}: no static libs in {libdir}"
    if missing:
        print(f"WARNING {platform}: missing (continuing): {missing}",
              flush=True)
    # Any extra .a the installs produced (e.g. libpostproc) joins the merge.
    libs += sorted(p for p in libdir.glob("*.a") if p not in libs)
    fw = build_dir / "Libmpv.framework"
    shutil.rmtree(fw, ignore_errors=True)
    (fw / "Headers").mkdir(parents=True)
    (fw / "Modules").mkdir(parents=True)
    sdk_name, _ = PLATFORMS[platform]
    # Merge every static lib into the single framework binary.
    run(["xcrun", "--sdk", sdk_name, "libtool", "-static", "-o",
         fw / "Libmpv", *libs], stage, env=env)
    # Headers: the full include/mpv set installed by mpv's meson install.
    # Keep the upstream mpv/ directory level under Headers/, and have the
    # umbrella header reference the set with quoted includes
    # ("mpv/client.h"): in a framework module build the angled form
    # <mpv/client.h> is a framework-style lookup that never descends
    # into Headers/mpv/ (CI round 8: "'mpv/client.h' file not found with
    # <angled> include; use \"quotes\" instead" — the file was already
    # in place), while the quoted form resolves relative to the umbrella
    # header's own directory.  Round 7's flat Headers/*.h layout failed
    # both forms.  mpv's own cross-includes are quoted same-dir includes
    # ("client.h" in render.h / stream_cb.h), so they keep resolving
    # with the whole set kept together in that subdirectory.
    mpv_inc = prefix / "include" / "mpv"
    assert mpv_inc.is_dir(), f"{platform}: {mpv_inc} missing (mpv install?)"
    mpv_hdr_dir = fw / "Headers" / "mpv"
    mpv_hdr_dir.mkdir(parents=True)
    for h in mpv_inc.glob("*.h"):
        shutil.copy(h, mpv_hdr_dir / h.name)
    # frame_output.h is added to the mpv tree by our patch, but mpv's
    # meson install_headers list does not name it, so it never lands in
    # the prefix; the Swift display pipeline binds its types/functions
    # directly, so take it from the patched source tree.
    if not (mpv_hdr_dir / "frame_output.h").exists():
        mpv_ver = next(v for n, v, *_ in COMPONENTS if n == "mpv")
        src_hdr = (cache / "src" / f"mpv-{mpv_ver}" / "include" / "mpv"
                   / "frame_output.h")
        assert src_hdr.is_file(), (
            f"{platform}: frame_output.h neither installed nor "
            f"present at {src_hdr}")
        shutil.copy(src_hdr, mpv_hdr_dir / "frame_output.h")
    inc_lines = [f'#include "mpv/{n}"' for n in MPV_HEADERS
                 if (mpv_hdr_dir / n).exists()]
    assert inc_lines, f"{platform}: no known mpv headers in {mpv_inc}"
    (fw / "Headers" / "Libmpv.h").write_text(
        "// Libmpv umbrella header (353 vendored build).\n"
        "#pragma once\n" + "\n".join(inc_lines) + "\n")
    (fw / "Modules" / "module.modulemap").write_text(
        'framework module Libmpv {\n'
        '  umbrella header "Libmpv.h"\n'
        '  export *\n'
        '  module * { export * }\n'
        '  link framework "AVFoundation"\n'
        '  link framework "AudioToolbox"\n'
        '  link framework "CoreMedia"\n'
        '  link framework "CoreVideo"\n'
        '  link framework "VideoToolbox"\n'
        '  link framework "Security"\n'
        '  link framework "Foundation"\n'
        '  link framework "CoreFoundation"\n'
        '  link "c++"\n  link "z"\n  link "iconv"\n  link "bz2"\n'
        '}\n')
    (fw / "Info.plist").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0"><dict>\n'
        '<key>CFBundleExecutable</key><string>Libmpv</string>\n'
        '<key>CFBundleIdentifier</key><string>local.avfan.Libmpv</string>\n'
        '<key>CFBundleName</key><string>Libmpv</string>\n'
        '<key>CFBundlePackageType</key><string>FMWK</string>\n'
        '<key>CFBundleShortVersionString</key><string>0.41.0</string>\n'
        '<key>CFBundleVersion</key><string>353</string>\n'
        f'<key>MinimumOSVersion</key><string>{MIN_IOS}</string>\n'
        '</dict></plist>\n')
    stamp(build_dir, stage)
    return fw

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--platforms", default="device,simulator")
    ap.add_argument("--force", action="store_true",
                    help="clear stage stamps and rebuild")
    a = ap.parse_args()
    root = Path(a.root).resolve()
    assert root.is_dir(), root
    platforms = [p.strip() for p in a.platforms.split(",") if p.strip()]
    assert platforms and all(p in PLATFORMS for p in platforms), platforms
    cache = root / ".cache353"; cache.mkdir(exist_ok=True)
    env = bootstrap(cache)
    srcs = fetch_all(cache)
    frameworks = []
    for p in platforms:
        build_platform(p, srcs, cache, env, a.force)
        frameworks.append(assemble_framework(p, cache, env))
    out_xc = root / "Vendor" / "Libmpv.xcframework"
    (root / "Vendor").mkdir(exist_ok=True)
    shutil.rmtree(out_xc, ignore_errors=True)  # delete-then-create
    args = ["xcodebuild", "-create-xcframework"]
    for fw in frameworks:
        args += ["-framework", fw]
    args += ["-output", out_xc]
    run(args, "xcframework", env=env)
    assert out_xc.is_dir(), out_xc
    print("vendor", out_xc, flush=True)
    print("NOTE: pipeline ported from AVFan (verified green in AVFan CI run 45239463298); first AVDB run still 待验证 — see scripts/mplaykit353/README.md")

if __name__ == "__main__":
    main()
