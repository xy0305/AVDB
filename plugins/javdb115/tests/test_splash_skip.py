#!/usr/bin/env python3
"""Unit tests for splash-ad skip label matching.

The opening ad is Flutter SplashPage (`package:astarte/main/splash_page.dart`)
with `_handleAd` / `_doCountDown` / `_goMain`. The iOS LaunchScreen is only
the system launch storyboard (LaunchImage) and must not be removed. These
tests cover the narrow skip-label policy only. They do not claim the splash
ad is gone on device, and they do not exercise a real Flutter semantics tree.
"""
from __future__ import annotations
import re


def normalize(label: str) -> str:
    return " ".join((label or "").split())


def _rest_ok(rest: str, english: bool) -> bool:
    if rest == "":
        return True
    pattern = (
        r"^([0-9]|sec|secs|second|seconds|s|ad|ads|广告|廣告|\s)+$"
        if english
        else r"^([0-9]|秒|s|S|广告|廣告|ad|Ad|AD|\s)+$"
    )
    return re.fullmatch(pattern, rest, flags=re.I) is not None


def is_splash_skip_label(label: str | None) -> bool:
    s = normalize(label or "")
    if not s:
        return False
    for tok in ("跳过", "跳過", "略过", "略過"):
        if s == tok:
            return True
        if s.startswith(tok) and len(s) <= 16:
            rest = s[len(tok):].strip()
            if _rest_ok(rest, english=False):
                return True
    if s in {"点击跳过", "點擊跳過", "点击跳过广告", "點擊跳過廣告"}:
        return True
    low = s.lower()
    if low == "skip" or low.startswith("skip "):
        rest = s[4:].strip()
        if _rest_ok(rest, english=True):
            return True
    return False


MATCH = [
    "跳过",
    "跳过 5",
    "跳过 5秒",
    "跳过5",
    "跳过广告",
    "跳過",
    "跳過 3",
    "略过",
    "略過",
    "点击跳过",
    "點擊跳過廣告",
    "Skip",
    "skip",
    "Skip 5",
    "Skip 5s",
    "Skip Ad",
    "SKIP 3 seconds",
]

REJECT = [
    "",
    "   ",
    "广告合作",
    "立即支付",
    "立即更新",
    "立即邀请",
    "我知道了",
    "关闭",
    "關閉",
    "稍后",
    "稍後",
    "skipped",
    "skipping",
    "SkipIterable",
    "skip_way",
    "startCountDown",
    "SplashPage",
    "LaunchImage",
    "广告位置、投放时间等",
    "点击跳过并进入会员购买页面，立即支付",  # too long / not an exact click-skip token
]


def test_match_skip_labels():
    for label in MATCH:
        assert is_splash_skip_label(label), label


def test_reject_non_skip_labels():
    for label in REJECT:
        assert not is_splash_skip_label(label), label


def test_does_not_treat_launchscreen_as_ad():
    # iOS UILaunchStoryboardName=LaunchScreen is not the in-app kai ping ad.
    assert not is_splash_skip_label("LaunchScreen")
    assert not is_splash_skip_label("LaunchImage")


def test_whitespace_normalization():
    assert is_splash_skip_label("  跳过  5  ")
    assert is_splash_skip_label("Skip   5")


def main():
    for fn in [
        test_match_skip_labels,
        test_reject_non_skip_labels,
        test_does_not_treat_launchscreen_as_ad,
        test_whitespace_normalization,
    ]:
        fn()
        print(f"PASS {fn.__name__}")
    print("PASS: splash skip label policy (no device claim)")


if __name__ == "__main__":
    main()
