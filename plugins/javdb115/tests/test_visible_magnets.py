#!/usr/bin/env python3
"""Host tests for visible magnet-list parsing and one-tap link selection.

These tests encode why v7 missed already-visible 磁鏈下載 rows (MIDA-859
titles / ED2K / file counts, no raw URI in the accessibility tree) and how
v8 reconstructs JavDB Magnets.detailLink the same way as buildMagnetLink /
rebuildEd2kLink. They do not claim a device push succeeded.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_protocol import is_offline, MAGNET_RE, ED2K_RE, first_offline
from test_detail_actions import catalog_number_in_text, is_magnet_tab_label, is_action_row_label
from test_external_covers import identity_key


MAGNET_PREFIX = "magnet:?xt=urn:btih:"
ED2K_PREFIX = "ed2k://|file|"


def magnet_link(hash_: str, name: str | None = None) -> str:
    h = hash_.strip().lower()
    out = f"{MAGNET_PREFIX}{h}"
    if name:
        # Same allowed set as the dylib: alnum + -._
        enc = "".join(
            ch if (ch.isalnum() or ch in "-._") else f"%{ord(ch):02X}"
            for ch in name
        )
        out += f"&dn={enc}"
    return out


def link_from_fields(hash_=None, name=None, type_=None, url=None) -> str | None:
    ty = (type_ or "").lower()
    u = (url or "").strip()
    if ty == "ed2k" or u.lower().startswith(ED2K_PREFIX):
        if is_offline(u):
            return u
        found = first_offline(u) if u else None
        return found
    h = (hash_ or "").strip()
    if not re.fullmatch(r"[0-9a-fA-F]{32,40}", h or ""):
        return u if is_offline(u) else None
    link = magnet_link(h, name)
    return link if is_offline(link) else None


def text_matches_catalog(text: str | None, number: str | None) -> bool:
    if not number:
        return True
    if not text:
        return False
    if identity_key(text) and identity_key(text) == identity_key(number):
        return True
    folded = text.upper()
    wanted = (identity_key(number) or number).upper()
    if wanted and wanted in folded:
        return True
    compact_w = wanted.replace("-", "").replace("_", "")
    compact_t = folded.replace("-", "").replace("_", "")
    return bool(compact_w) and compact_w in compact_t


def preferred_link(links: list[str], number: str | None) -> str | None:
    best_m = any_m = best_e = any_e = None
    for link in links:
        if not is_offline(link):
            continue
        name = None
        m = re.search(r"[?&]dn=([^&]+)", link, re.I)
        if m:
            from urllib.parse import unquote
            name = unquote(m.group(1))
        elif link.lower().startswith(ED2K_PREFIX):
            parts = link.split("|")
            if len(parts) >= 3:
                name = parts[2]
        match = text_matches_catalog(link, number) or text_matches_catalog(name, number)
        if link.lower().startswith("magnet:"):
            any_m = any_m or link
            if match and not best_m:
                best_m = link
        else:
            any_e = any_e or link
            if match and not best_e:
                best_e = link
    return best_m or best_e or any_m or any_e or (links[0] if links else None)


# Labels like the already-visible MIDA-859 磁鏈下載 tab (titles, ED2K, file counts).
# Raw magnet/ed2k URIs are not in this tree — that is why v7 asked the user to
# open the tab or paste a link even though the list was on screen.
SCREENSHOT_LABELS = [
    "MIDA-859",
    "想看", "看过", "存入清單", "離線觀看",
    "磁鏈下載 6", "短評", "相關清單",
    "MIDA-859-U.LTX 4K",
    "ED2K",
    "15 個檔案",
    "MIDA-859-C",
    "ED2K",
    "8 個檔案",
    "2.1 GB",
]


def test_visible_rows_have_no_raw_uri_in_accessibility():
    blob = "\n".join(SCREENSHOT_LABELS)
    assert first_offline(blob) is None
    assert not MAGNET_RE.search(blob)
    assert not ED2K_RE.search(blob)
    assert is_magnet_tab_label("磁鏈下載 6")
    assert catalog_number_in_text("MIDA-859-U.LTX 4K") == "MIDA-859"
    assert is_action_row_label("想看")


def test_reconstruct_magnet_detail_link():
    link = link_from_fields(
        hash_="0123456789ABCDEF0123456789ABCDEF01234567",
        name="MIDA-859-U.LTX 4K",
        type_="magnet",
    )
    assert link is not None
    assert link.startswith(MAGNET_PREFIX)
    assert "0123456789abcdef0123456789abcdef01234567" in link
    assert "dn=" in link
    assert "MIDA-859" in link
    assert is_offline(link)


def test_passthrough_already_valid_ed2k_url():
    ed = "ed2k://|file|MIDA-859-C.mp4|123456789|0123456789abcdef0123456789abcdef|/"
    link = link_from_fields(type_="ed2k", url=ed, name="MIDA-859-C")
    assert link == ed
    assert is_offline(link)


def test_reject_non_hash_and_unsigned_api_not_used():
    assert link_from_fields(hash_="zzzz", type_="magnet", name="MIDA-859") is None
    assert link_from_fields(hash_="", type_="magnet") is None
    # Policy: we only reconstruct from already-resident fields, never invent
    # a signed getMovieMagnets request.
    src = Path(__file__).resolve().parents[1] / "src"
    text = (src / "AVDB115VisibleMagnets.m").read_text()
    assert "getMovieMagnets" not in text or "without calling getMovieMagnets" in (
        src / "AVDB115VisibleMagnets.h"
    ).read_text()
    actions = (src / "AVDB115DetailActions.m").read_text()
    assert "Do not call getMovieMagnets" in actions or "不会请求带签名的磁力接口" in actions
    assert "preferredLink" in actions
    assert "residentLinksMatchingCatalog" in actions


def test_preferred_picks_catalog_magnet_for_one_tap():
    other = magnet_link("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "SSIS-001")
    wanted = magnet_link("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "MIDA-859-U.LTX 4K")
    ed = "ed2k://|file|MIDA-859-C.mp4|12345|0123456789abcdef0123456789abcdef|/"
    pick = preferred_link([ed, other, wanted], "MIDA-859")
    assert pick == wanted
    # Single catalog magnet: one-tap, no chooser.
    assert preferred_link([wanted], "MIDA-859") == wanted


def test_filename_matches_catalog():
    assert text_matches_catalog("MIDA-859-U.LTX 4K", "MIDA-859")
    assert text_matches_catalog("mida859c", "MIDA-859")
    assert not text_matches_catalog("SSIS-001-U", "MIDA-859")


def main():
    for fn in [
        test_visible_rows_have_no_raw_uri_in_accessibility,
        test_reconstruct_magnet_detail_link,
        test_passthrough_already_valid_ed2k_url,
        test_reject_non_hash_and_unsigned_api_not_used,
        test_preferred_picks_catalog_magnet_for_one_tap,
        test_filename_matches_catalog,
    ]:
        fn()
        print(f"PASS {fn.__name__}")
    print("PASS: visible magnet parse / one-tap pick (no device-push claim)")


if __name__ == "__main__":
    main()
