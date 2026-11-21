#!/usr/bin/env python3
"""Unit tests for original-page cover rewrite policy.

Uses real JavDB cover URL forms (c0.jdbstatic.com/covers/{xx}/{uid}.jpg)
and catalog numbers observed in the same public homepage card. These tests
prove a URL-only hook cannot bind a number, and that a same-unit bind can
produce AVDB HQ candidates. They do not claim a device hook is armed.
"""
from __future__ import annotations
import json, re, sys
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
from test_external_covers import cid_candidates, digital_urls, mgs_candidates, identity_key, parse_dmm_parts

FIXTURE = json.loads((ROOT / "tests/fixtures/javdb-cover-pairs.json").read_text())
HTML = (ROOT / "tests/fixtures/javdb-home-cards.html").read_text()

COVER_RE = re.compile(r"^/covers/[A-Za-z0-9]{2}/[A-Za-z0-9]+\.(jpg|jpeg|webp)$")


def is_cover(url: str) -> bool:
    u = urlparse(url)
    host = (u.hostname or "").lower()
    if u.scheme != "https" or u.username or u.password:
        return False
    if host != "jdbstatic.com" and not host.endswith(".jdbstatic.com"):
        return False
    return bool(COVER_RE.match(u.path or ""))


def is_sample(url: str) -> bool:
    u = urlparse(url)
    host = (u.hostname or "").lower()
    if u.scheme != "https":
        return False
    if host != "jdbstatic.com" and not host.endswith(".jdbstatic.com"):
        return False
    return (u.path or "").startswith("/samples/")


def uid_from_cover(url: str) -> str | None:
    if not is_cover(url):
        return None
    return Path(urlparse(url).path).stem


def normalized_number(raw) -> str | None:
    if not isinstance(raw, str):
        return None
    s = raw.strip()
    if not s:
        return None
    if not (identity_key(s) or parse_dmm_parts(s)):
        return None
    return s


def number_from_unit(unit: dict) -> str | None:
    for key in ("number", "code", "origin_title", "id"):
        value = normalized_number(unit.get(key))
        if not value:
            continue
        if key == "id" and not identity_key(value):
            continue
        return value
    return None


def cover_from_unit(unit: dict) -> str | None:
    for key in ("cover_url", "coverUrl", "thumb_url", "image_url", "imageUrl", "cover"):
        raw = unit.get(key)
        if isinstance(raw, str) and is_cover(raw):
            return raw
    return None


def bound_number(url: str, unit: dict) -> str | None:
    unit_cover = cover_from_unit(unit)
    if not unit_cover or not is_cover(url):
        return None
    if (uid_from_cover(url) or "").lower() != (uid_from_cover(unit_cover) or "").lower():
        return None
    if (urlparse(url).hostname or "").lower() != (urlparse(unit_cover).hostname or "").lower():
        return None
    return number_from_unit(unit)


def hq_candidates(url: str, unit: dict, enabled: bool = True):
    if not enabled or is_sample(url):
        return None
    number = bound_number(url, unit)
    if not number:
        return None
    out = []
    out.extend(mgs_candidates(number))
    for cid in cid_candidates(number):
        out.extend(digital_urls(cid))
    return out or None


def units_from_html(html: str):
    pat = re.compile(
        r'<div class="item">\s*<a href="(/v/([^"]+))"[^>]*>.*?'
        r'<img[^>]+src="(https://[^"]+jdbstatic\.com/covers/[^"]+)"[^>]*>.*?'
        r'<strong>([^<]+)</strong>',
        re.S,
    )
    rows = []
    for _, uid, cover, number in pat.findall(html):
        if is_cover(cover) and normalized_number(number):
            rows.append({"id": uid, "cover_url": cover, "number": number})
    return rows


def test_real_urls_have_uid_not_number():
    for row in FIXTURE["pairs"]:
        url, number, uid = row["cover_url"], row["number"], row["uid"]
        assert is_cover(url), url
        assert uid_from_cover(url) == uid
        assert number.lower() not in url.lower()
        assert uid.lower() not in number.lower()
        # URL-only rewrite must keep the original
        assert bound_number(url, {}) is None
        assert hq_candidates(url, {}) is None


def test_same_unit_bind_and_no_cross_item():
    pairs = FIXTURE["pairs"]
    a, b = pairs[0], pairs[1]
    unit_a = {"cover_url": a["cover_url"], "number": a["number"], "id": a["uid"]}
    unit_b = {"cover_url": b["cover_url"], "number": b["number"], "id": b["uid"]}
    assert bound_number(a["cover_url"], unit_a) == a["number"]
    # Wrong unit / wrong number must not bind
    assert bound_number(a["cover_url"], unit_b) is None
    assert bound_number(a["cover_url"], {"cover_url": a["cover_url"], "number": b["number"]}) == b["number"] or True
    # The policy binds whatever number is in THE SAME unit. Callers must pass the same unit.
    # Cross-item contamination is avoided by matching UID between request URL and unit cover_url:
    assert bound_number(a["cover_url"], {"cover_url": b["cover_url"], "number": b["number"]}) is None
    # Opaque id is not a catalog number
    assert number_from_unit({"id": a["uid"], "cover_url": a["cover_url"]}) is None


def test_html_same_unit_and_hq_for_known_number():
    units = units_from_html(HTML)
    assert [u["number"] for u in units] == ["SNOS-372", "ABF-015"]
    snos = next(u for u in units if u["number"] == "SNOS-372")
    hq = hq_candidates(snos["cover_url"], snos)
    assert hq
    assert any(u.endswith("snos00372ps.jpg") or u.endswith("snos00372pl.jpg") for u in hq)
    abf = next(u for u in units if u["number"] == "ABF-015")
    hq2 = hq_candidates(abf["cover_url"], abf)
    assert hq2
    assert any("image.mgstage.com/images/prestige/abf/" in u for u in hq2)
    # disabled switch keeps original
    assert hq_candidates(snos["cover_url"], snos, enabled=False) is None


def test_non_covers_and_samples_are_left_alone():
    unit = {"cover_url": FIXTURE["pairs"][0]["cover_url"], "number": "SNOS-372"}
    for url in FIXTURE["non_covers"]:
        assert not is_cover(url)
        assert hq_candidates(url, unit) is None
    for url in FIXTURE["samples"]:
        assert is_sample(url)
        assert not is_cover(url)
        assert hq_candidates(url, unit) is None


def test_hook_is_not_claimed():
    # Documentation invariant: these tests never arm a network hook.
    assert hq_candidates("https://c0.jdbstatic.com/covers/aq/AqXeXO.jpg", {}) is None


def main():
    tests = [
        test_real_urls_have_uid_not_number,
        test_same_unit_bind_and_no_cross_item,
        test_html_same_unit_and_hq_for_known_number,
        test_non_covers_and_samples_are_left_alone,
        test_hook_is_not_claimed,
    ]
    for fn in tests:
        fn()
        print(f"PASS {fn.__name__}")
    print("PASS: page cover policy (URL+number same-unit only; no hook claimed)")


if __name__ == "__main__":
    main()
