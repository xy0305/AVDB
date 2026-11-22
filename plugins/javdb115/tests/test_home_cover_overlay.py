#!/usr/bin/env python3
"""Source-level checks for the v14 homepage HD cover overlay."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"


def read(name: str) -> str:
    return (SRC / name).read_text(encoding="utf-8")


def test_overlay_does_not_patch_app_framework():
    src = read("AVDB115HomeCoverOverlay.m")
    for banned in ("vm_protect", "mach_vm_protect", "App.framework", "VM_PROT_COPY"):
        assert banned not in src, f"overlay must not {banned}"
    page = read("AVDB115PageCover.m")
    # Honest: TEXT rewrite is still impossible; overlay is the armed path.
    assert "vm_protect" in page
    assert "return YES" in page


def test_uses_existing_cover_resolver_and_catalog_numbers():
    src = read("AVDB115HomeCoverOverlay.m")
    assert "AVDB115CoverResolver" in src
    assert "resolveNumber:" in src
    assert "catalogNumberInText" in src
    assert "近期可播放更新" in src
    assert "kAVDB115HomeCoverMinGrid" in src
    assert "looksLikeMovieDetailWithActionLabels" in src
    assert "userInteractionEnabled = NO" in src
    assert "eligiblePortrait" in src
    # Do not invent a new cover host; resolver supplies DMM/MGS/etc.
    for host in ("example.com", "placeholder", "picsum"):
        assert host not in src.lower()


def test_skipped_on_detail_and_when_disabled():
    src = read("AVDB115HomeCoverOverlay.m")
    assert "replaceEnabled" in src
    assert "onDetail" in src
    assert "isPlayerPresented" in src or "setSuppressed" in src


def test_tweak_installs_overlay():
    tweak = read("Tweak.m")
    assert tweak.count("[AVDB115HomeCoverOverlay install]") >= 2


def main():
    tests = [
        test_overlay_does_not_patch_app_framework,
        test_uses_existing_cover_resolver_and_catalog_numbers,
        test_skipped_on_detail_and_when_disabled,
        test_tweak_installs_overlay,
    ]
    for fn in tests:
        fn()
        print(f"PASS {fn.__name__}")
    print("PASS: homepage HD cover overlay (source policy)")


if __name__ == "__main__":
    main()
