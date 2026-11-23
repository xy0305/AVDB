#!/usr/bin/env python3
"""Build 353 — Libmpv native build pipeline for AVDB (CI only; 待 CI 首跑验证).

Builds a single static Libmpv.xcframework (device + simulator, arm64,
iOS 17.0 minimum) from pinned upstream tarballs:

  FFmpeg / mpv / libplacebo / dav1d / libass / freetype / harfbuzz /
  fribidi / xxHash  — versions and sha256 are pinned in COMPONENTS below
  (coordinator-verified; do not bump without re-pinning the hashes).

Output:  <repo-root>/Vendor/Libmpv.xcframework
Cache:   <repo-root>/.cache353/{downloads,src,build,cross,venv}
         One <stage>.stamp per (platform, stage); re-runs skip finished
         stages.  --force clears the stamps (and per-platform build dirs).

Usage:
  python3 scripts/mplaykit353/build_libmpv.py <repo-root> \
      [--platforms device,simulator] [--force]

Platform notes (verified against mpv 0.42 meson.build, not guessed):
  * mpv 0.42 hard-requires libplacebo >= 7.387.0.
  * -Dvulkan=disabled is legal for mpv: the vulkan option is
    get_option('vulkan').require(libplacebo-has-vulkan).  libplacebo is
    therefore built -Dvulkan=disabled -Dopengl=enabled (the OpenGL backend
    needs neither glslang nor shaderc).
  * iOS GL is plain-gl: plain_gl.allowed() sets features['gl'] and compiles
    opengl/libmpv_gl.c + ra_gl.c; the host app supplies a GLES context via
    the libmpv render API.  The darwin branch would otherwise look for the
    (macOS-only) OpenGL framework via gl-cocoa, so -Dgl-cocoa=disabled.
  * ao_audiounit (audiounit) only requires darwin and works on iOS;
    coreaudio does not exist on iOS.
  * Every optional mpv/libplacebo/libass/... -D flag goes through
    meson_args(), which greps the extracted meson.options /
    meson_options.txt first and only passes options that actually exist,
    so an unknown option can never fail the configure step.
  * pkg-config supply (fixed after the first CI run): PKG_CONFIG_LIBDIR
    is pinned to the vendored prefix, so the SDK's system zlib — named
    in freetype2.pc's Requires.private — is described by a hand-written
    zlib.pc (write_system_pcs), and the cross files set no sys_root,
    because meson would export it as PKG_CONFIG_SYSROOT_DIR and
    pkg-config would relocate the prefix's own absolute paths into the
    SDK, breaking every vendored .pc lookup.

This script is written on Linux and has never run end-to-end: the whole
pipeline is 待 CI 首跑验证 on a macos-26 runner with Xcode.  See README.md
for the three most likely first-run failure points.
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
    ("mpv",       "0.42.0",
     "https://github.com/mpv-player/mpv/archive/refs/tags/v0.42.0.tar.gz",
     "bcfebbfa2b65a6d88dc97ea18117831072373e38b5785a2afb874ed4df5070dd"),
    ("libplacebo", "7.387.0",   # mpv 0.42 meson.build floor: >= 7.387.0
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
    pkg-config, xcrun, cmake (freetype is built with cmake)."""
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
    # only the old 0.1.x line and must NOT be used here.
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
    return srcs

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
    harfbuzz stage in the first CI run.  mpv's dependency('zlib')
    (required, both 0.41 and 0.42) and FFmpeg's check_pkg_config(zlib)
    hit the same wall.  Describe the SDK's system zlib with absolute
    paths (the cross files deliberately set no sys_root, so nothing
    relocates them).  Written unconditionally at platform start so a
    cached prefix from an earlier, failed run picks the file up
    without --force."""
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

    # libplacebo: OpenGL backend only; vulkan off (no glslang/shaderc
    # needed), xxhash from the vendored build above.  jinja2 comes from
    # the bootstrap venv (its bin/ is first on PATH in env).
    if not skip_if_stamped(build_dir, "libplacebo"):
        meson_build(srcs["libplacebo"], build_dir / "libplacebo", prefix,
                    cross, penv,
                    {"vulkan": "disabled", "opengl": "enabled",
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
    stage = "mpv"
    if skip_if_stamped(build_dir, stage): return
    # Switch table (all defensive via meson_args): libmpv + plain-gl +
    # audiounit on; everything platform-foreign or doc/test off.  vulkan
    # disabled is legitimate — see module docstring.  gl-cocoa/cocoa and
    # coreaudio are macOS-only and must not be probed on iOS.
    wanted = {
        # cplayer off: it defaults to true in mpv's meson.options,
        # and the CLI executable is dead weight in a libmpv-only
        # pipeline — worse, on darwin mpv then also wires the
        # osxbundle/macos-bundle targets and links an iOS executable
        # with the macOS-SDK -isysroot its objc probe injects.
        "cplayer": False,
        "libmpv": True, "plain-gl": "enabled", "videotoolbox": "enabled",
        "audiounit": "enabled",
        "vulkan": "disabled", "gl-cocoa": "disabled", "cocoa": "disabled",
        "coreaudio": "disabled", "sdl2": "disabled",
        "lua": "disabled", "javascript": "disabled",
        "libbluray": "disabled", "uchardet": "disabled",
        "rubberband": "disabled", "vapoursynth": "disabled",
        "libarchive": "disabled", "dvdnav": "disabled", "cdda": "disabled",
        "x11": "disabled", "wayland": "disabled", "drm": "disabled",
        "gbm": "disabled", "egl": "disabled",
        "manpage-build": "disabled", "html-build": "disabled",
        "pdf-build": "disabled", "tests": False, "test": False,
    }
    meson_build(src, build_dir / "mpv", prefix, cross, penv, wanted, stage)
    stamp(build_dir, stage)

# ------------------------------------------------------- framework/xc ------
EXPECTED_LIBS = ["libmpv.a", "libavformat.a", "libavcodec.a",
                 "libavutil.a", "libavfilter.a", "libswscale.a",
                 "libswresample.a", "libplacebo.a", "libass.a",
                 "libdav1d.a", "libfreetype.a", "libharfbuzz.a",
                 "libfribidi.a", "libxxhash.a"]
MPV_HEADERS = ["client.h", "render.h", "render_gl.h", "stream_cb.h"]

def assemble_framework(platform, cache, env):
    stage = f"framework-{platform}"
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
    mpv_inc = prefix / "include" / "mpv"
    assert mpv_inc.is_dir(), f"{platform}: {mpv_inc} missing (mpv install?)"
    for h in mpv_inc.glob("*.h"):
        shutil.copy(h, fw / "Headers" / h.name)
    inc_lines = [f"#include <mpv/{n}>" for n in MPV_HEADERS
                 if (fw / "Headers" / n).exists()]
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
        '  link framework "OpenGLES"\n'
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
        '<key>CFBundleIdentifier</key><string>local.avdb.Libmpv</string>\n'
        '<key>CFBundleName</key><string>Libmpv</string>\n'
        '<key>CFBundlePackageType</key><string>FMWK</string>\n'
        '<key>CFBundleShortVersionString</key><string>0.42.0</string>\n'
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
    print("NOTE: pipeline is 待 CI 首跑验证 — see scripts/mplaykit353/README.md")

if __name__ == "__main__":
    main()
