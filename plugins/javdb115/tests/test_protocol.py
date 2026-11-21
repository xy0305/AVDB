#!/usr/bin/env python3
"""Host tests for protocol helpers that must stay aligned with AVDB Pan115Client / the dylib."""
from __future__ import annotations
import json, re, sys
from pathlib import Path
from urllib.parse import unquote_plus, unquote

ROOT = Path(__file__).resolve().parents[1]


def normalize_cookie(raw: str) -> str:
    s = raw.replace("\r\n", " ").replace("\n", " ")
    s = re.sub(r"\s*;\s*", "; ", s)
    s = re.sub(r"[ \t]{2,}", " ", s)
    return s.strip()


def extract_uid(cookie: str):
    m = re.search(r"(?:^|;\s*)UID=(\d+)", normalize_cookie(cookie), re.I)
    return m.group(1) if m else None


def is_offline(text: str) -> bool:
    s = (text or "").strip().lower()
    return s.startswith("magnet:?xt=urn:btih:") or s.startswith("ed2k://|file|")


MAGNET_RE = re.compile(r"magnet:\?xt=urn:btih:[0-9a-fA-F]{32,40}[^\s\"'<>]*", re.I)
ED2K_RE = re.compile(r"ed2k://\|file\|[^|]+\|\d{1,13}\|[0-9a-fA-F]{32}\|/?", re.I)


def first_offline(text: str | None):
    if not text:
        return None
    trim = text.strip()
    if is_offline(trim):
        return trim
    m = MAGNET_RE.search(text) or ED2K_RE.search(text)
    return m.group(0) if m else None


def parse_push(data: bytes):
    text = data.decode("utf-8", "replace")
    if not text:
        return ("failed", "接口无返回")
    if "<html" in text.lower() or "登录" in text:
        return ("failed", "Cookie 无效或已过期")
    try:
        obj = json.loads(text)
    except Exception:
        return ("failed", "接口返回不是 JSON")
    state = obj.get("state")
    ok = state is True or state == 1 or state == "1"
    if ok:
        return ("success", "已推送到 115")
    msg = obj.get("error_msg") or obj.get("error") or obj.get("msg") or ""
    errcode = obj.get("errcode") or obj.get("errno") or 0
    if errcode == 10008 or "已存在" in str(msg) or "重复" in str(msg):
        return ("exists", "115 任务已存在")
    return ("failed", msg or "添加失败")


def parse_master(text: str):
    def capture(line, pat):
        m = re.search(pat, line)
        return m.group(1) if m else None

    def label(name, height, bw):
        n = (name or "").upper()
        mapping = {"BD": "4K", "UD": "1080P", "HD": "720P", "SD": "480P", "LD": "360P"}
        if n in mapping:
            return mapping[n]
        if height >= 2160: return "4K"
        if height >= 1080: return "1080P"
        if height >= 720: return "720P"
        if height >= 480: return "480P"
        if height >= 360: return "360P"
        if bw > 0: return f"{bw // 1000}k"
        return "HLS（分辨率未知）"

    def prio(name, height):
        n = (name or "").upper()
        mapping = {"BD": 4, "UD": 3, "HD": 2, "SD": 1, "LD": 0}
        if n in mapping:
            return mapping[n]
        if height >= 2160: return 4
        if height >= 1080: return 3
        if height >= 720: return 2
        if height >= 480: return 1
        return 0

    lines = [ln.strip() for ln in text.splitlines()]
    streams = []
    for i, line in enumerate(lines):
        if "#EXT-X-STREAM-INF" not in line:
            continue
        name = capture(line, r'NAME="([^"]+)"')
        height = int(capture(line, r"RESOLUTION=\d+x(\d+)") or 0)
        bw = int(capture(line, r"BANDWIDTH=(\d+)") or 0)
        if i + 1 < len(lines):
            u = lines[i + 1]
            if u.startswith("https: //"):
                u = u.replace("https: //", "https://")
            if not u.startswith("http"):
                u = "https://115.com/" + u.lstrip("/")
            if u.startswith("http"):
                streams.append((label(name, height, bw), u, bw + prio(name, height) * 10_000_000))
    streams.sort(key=lambda s: s[2], reverse=True)
    return streams


def normalized_key(raw: str | None) -> str:
    if not raw:
        return ""
    s = raw.lower().replace("-", "").replace("_", "").replace(" ", "").replace(".", "")
    return s.replace("fc2ppv", "fc2")


def name_matches(filename: str, keyword: str) -> bool:
    name = normalized_key(filename)
    key = normalized_key(keyword)
    if not key or not name:
        return False
    if key in name:
        return True
    return False if ("." not in keyword and " " not in keyword) else False


def form_encoded(s: str) -> str:
    out = []
    for ch in s.encode("utf-8"):
        if chr(ch).isalnum() or chr(ch) in "-._~":
            out.append(chr(ch))
        else:
            out.append(f"%{ch:02X}")
    return "".join(out)


def test_cookie():
    raw = "UID=123;\n CID=abc  ;   SEID=xyz"
    c = normalize_cookie(raw)
    assert "UID=123" in c and "CID=abc" in c and "SEID=xyz" in c
    assert extract_uid(c) == "123"
    assert extract_uid("nope") is None


def test_links():
    mag = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=TEST-001"
    ed = "ed2k://|file|TEST-001.mp4|12345|0123456789abcdef0123456789abcdef|/"
    assert is_offline(mag) and is_offline(ed)
    assert not is_offline("https://example.com/a.mp4")
    blob = f"see {mag} and also {ed} thanks"
    assert first_offline(blob) == mag
    assert first_offline("  " + ed + "  ") == ed


def test_push_parse():
    assert parse_push(b'{"state":true}')[0] == "success"
    assert parse_push(b'{"state":1}')[0] == "success"
    assert parse_push(b'{"state":false,"errcode":10008}')[0] == "exists"
    assert parse_push('{"state":false,"error_msg":"任务已存在"}'.encode())[0] == "exists"
    assert parse_push(b'{"state":false,"error_msg":"quota"}') == ("failed", "quota")
    assert parse_push(b"<html>login")[1] == "Cookie 无效或已过期"
    assert parse_push(b"not-json")[1] == "接口返回不是 JSON"


def test_master():
    text = """
#EXTM3U
#EXT-X-STREAM-INF:NAME="UD",RESOLUTION=1920x1080,BANDWIDTH=4000000
https://cdn.example/1080.m3u8
#EXT-X-STREAM-INF:NAME="HD",RESOLUTION=1280x720,BANDWIDTH=2000000
https: //cdn.example/720.m3u8
#EXT-X-STREAM-INF:NAME="BD",RESOLUTION=3840x2160,BANDWIDTH=12000000
/rel/4k.m3u8
""".strip()
    streams = parse_master(text)
    assert [s[0] for s in streams] == ["4K", "1080P", "720P"]
    assert streams[0][1] == "https://115.com/rel/4k.m3u8"
    assert streams[2][1] == "https://cdn.example/720.m3u8"


def test_name_match():
    assert name_matches("SSIS-001.mp4", "SSIS-001")
    assert name_matches("ssis001-c.mkv", "SSIS-001")
    assert not name_matches("SSIS-002.mp4", "SSIS-001")
    assert name_matches("FC2PPV-1234567.mp4", "FC2-1234567")


def test_form_encode():
    assert form_encoded("abc-._~") == "abc-._~"
    assert form_encoded("a b") == "a%20b"
    mag = "magnet:?xt=urn:btih:aa"
    enc = form_encoded(mag)
    assert "%" in enc and ":" not in enc.replace("%", "")


def main():
    tests = [test_cookie, test_links, test_push_parse, test_master, test_name_match, test_form_encode]
    for fn in tests:
        fn()
        print(f"PASS {fn.__name__}")
    print("PASS: protocol helpers aligned with AVDB 115 push/play")


if __name__ == "__main__":
    main()
