#!/usr/bin/env python3
"""Unit tests for movie-detail 115 chip policy: catalog-number extraction
and action-row / tab label matching.

These tests do not claim the Dart-row hook or the v6 overlay were laid out
on a device.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_external_covers import identity_key, parse_dmm_parts

ACTION_LABELS = {
    "想看", "看过", "看過",
    "存入清單", "存入清单",
    "離線觀看", "离线观看",
}

BOTTOM_TABS = {
    "短評", "短评", "相關清單", "相关清单",
}


def normalize(label: str) -> str:
    return " ".join((label or "").split())


def is_action_row_label(label: str | None) -> bool:
    return normalize(label or "") in ACTION_LABELS


def is_magnet_tab_label(label: str | None) -> bool:
    s = normalize(label or "")
    if s in {"磁鏈下載", "磁链下载"}:
        return True
    for tok in ("磁鏈下載", "磁链下载"):
        if s.startswith(tok):
            rest = s[len(tok):].strip()
            return rest == "" or re.fullmatch(r"[0-9]{1,4}", rest) is not None
    return False


def is_bottom_tab_label(label: str | None) -> bool:
    return is_magnet_tab_label(label) or normalize(label or "") in BOTTOM_TABS


def is_vip_banner_label(label: str | None) -> bool:
    s = normalize(label or "")
    return s in {"購買VIP", "购买VIP"} or s.startswith("購買VIP") or s.startswith("购买VIP")


def _token_if_catalog(token: str) -> str | None:
    t = (token or "").strip()
    if not t:
        return None
    if not (identity_key(t) or parse_dmm_parts(t)):
        return None
    return t.upper()


def catalog_number_in_text(text: str | None) -> str | None:
    s = (text or "").strip()
    if not s:
        return None
    m = re.search(r"(?:番號|番号)\s*[:：]?\s*([A-Za-z0-9][A-Za-z0-9._-]{1,24})", s)
    if m:
        ok = _token_if_catalog(m.group(1))
        if ok:
            return ok
    ok = _token_if_catalog(s)
    if ok:
        return ok
    token_re = re.compile(
        r"(?<![A-Za-z0-9])([A-Za-z]{1,4}[0-9]{1,4}[-_ ][0-9]{2,10}|"
        r"[0-9]{1,4}[A-Za-z]{2,12}[-_ ]?[0-9]{2,10}|"
        r"[A-Za-z]{2,12}[-_ ]?[0-9]{2,10})(?![A-Za-z0-9])"
    )
    for m in token_re.finditer(s):
        ok = _token_if_catalog(m.group(1))
        if ok:
            return ok
    return None


def looks_like_movie_detail(labels: list[str], number: str | None) -> bool:
    if not number:
        return False
    want = any(normalize(s) == "想看" for s in labels)
    watched = any(normalize(s) in {"看过", "看過"} for s in labels)
    listed = any(normalize(s) in {"存入清單", "存入清单"} for s in labels)
    offline = any(normalize(s) in {"離線觀看", "离线观看"} for s in labels)
    unique = sum([want, watched, listed, offline])
    if listed or offline:
        return unique >= 1
    return unique >= 2


def test_extract_from_nav_and_field():
    assert catalog_number_in_text("MIDA-859") == "MIDA-859"
    assert catalog_number_in_text("  mida-859  ") == "MIDA-859"
    assert catalog_number_in_text("番號: MIDA-859") == "MIDA-859"
    assert catalog_number_in_text("番号：MIDA-859") == "MIDA-859"
    assert catalog_number_in_text("番號 MIDA-859") == "MIDA-859"
    assert catalog_number_in_text("番号: SSIS-001") == "SSIS-001"
    assert catalog_number_in_text("标题里夹着 MIDA-859 和别的字") == "MIDA-859"


def test_reject_non_catalog_text():
    assert catalog_number_in_text("") is None
    assert catalog_number_in_text("想看") is None
    assert catalog_number_in_text("想看人数倒序") is None
    assert catalog_number_in_text("購買VIP") is None
    assert catalog_number_in_text("23:59") is None
    assert catalog_number_in_text("磁鏈下載 6") is None
    assert catalog_number_in_text("FC2-123456") is None


def test_action_and_tab_labels():
    for label in ["想看", "看过", "看過", "存入清單", "存入清单", "離線觀看", "离线观看", "  想看  "]:
        assert is_action_row_label(label), label
    for label in ["想看人数倒序", " 人想看,", "我想看这部视频", "我看过的", "未标「看过」", "購買VIP", "MIDA-859", ""]:
        assert not is_action_row_label(label), label
    assert is_magnet_tab_label("磁鏈下載")
    assert is_magnet_tab_label("磁链下载 6")
    assert is_bottom_tab_label("短評")
    assert is_bottom_tab_label("相關清單")
    assert not is_magnet_tab_label("下載")
    assert is_vip_banner_label("購買VIP")
    assert is_vip_banner_label("购买VIP")
    assert not is_vip_banner_label("想看")


def test_detail_page_heuristic():
    assert looks_like_movie_detail(["想看", "看过", "存入清單", "離線觀看"], "MIDA-859")
    assert looks_like_movie_detail(["想看", "离线观看"], "SSIS-001")
    assert looks_like_movie_detail(["存入清单"], "MIDA-859")
    assert not looks_like_movie_detail(["想看", "看过", "存入清單"], None)
    assert not looks_like_movie_detail(["想看"], "MIDA-859")  # only one non-distinctive chip
    assert not looks_like_movie_detail(["我想看这部视频", "我看过的"], "MIDA-859")


def test_does_not_claim_same_row_insertion():
    # Invariant: policy identifies the Flutter row. Device success of the
    # v7 runtime hook is not claimed here.
    assert is_action_row_label("想看")
    assert catalog_number_in_text("MIDA-859") == "MIDA-859"


def main():
    for fn in [
        test_extract_from_nav_and_field,
        test_reject_non_catalog_text,
        test_action_and_tab_labels,
        test_detail_page_heuristic,
        test_does_not_claim_same_row_insertion,
    ]:
        fn()
        print(f"PASS {fn.__name__}")
    print("PASS: detail action policy (no device-success claim)")


if __name__ == "__main__":
    main()
