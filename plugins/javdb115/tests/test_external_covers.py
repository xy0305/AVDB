#!/usr/bin/env python3
"""Host tests for External Library + HQ cover helpers (must stay aligned with the dylib)."""
from __future__ import annotations
import json, re, sys
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
SEED = json.loads((ROOT / "tests" / "dmm-label-seed.json").read_text())


def parse_dmm_parts(number: str):
    s = number.strip().lower()
    m = re.match(r"^([0-9]{0,4}[a-z]{2,10})-?0*([0-9]{1,6})$", s)
    if not m:
        return None
    label, serial = m.group(1), int(m.group(2))
    if serial <= 0 or label.startswith("fc2"):
        return None
    return label, serial


def pad(n: int, width: int) -> str:
    digits = str(n)
    return ("0" * max(0, width - len(digits))) + digits


def cid_candidates(number: str) -> list[str]:
    p = parse_dmm_parts(number)
    if not p:
        return []
    label, serial = p
    out: list[str] = []
    def add(c: str):
        if c and c not in out:
            out.append(c)
    rule = SEED.get(label)
    if rule:
        add(rule["prefix"] + label + pad(serial, int(rule["width"])))
    add(label + pad(serial, 5))
    add(label + pad(serial, 3))
    return out[:4]


def digital_urls(cid: str) -> list[str]:
    aws = "https://awsimgsrc.dmm.co.jp/pics_dig"
    return [
        f"{aws}/digital/video/{cid}/{cid}ps.jpg",
        f"{aws}/digital/video/{cid}/{cid}pl.jpg",
    ]


def legacy_urls(cid: str) -> list[str]:
    pics = "https://pics.dmm.co.jp"
    return [
        f"{pics}/digital/video/{cid}/{cid}pl.jpg",
        f"{pics}/mono/movie/adult/{cid}/{cid}pl.jpg",
    ]


def upgrade_dmm(source: str) -> list[str]:
    u = urlparse(source)
    host = (u.hostname or "").lower()
    if host not in {"pics.dmm.co.jp", "awsimgsrc.dmm.co.jp"}:
        return []
    path = u.path
    if host == "awsimgsrc.dmm.co.jp":
        if not path.startswith("/pics_dig"):
            return []
        path = path[len("/pics_dig"):]
    m = re.match(r"^/digital/video/([a-z0-9_]+)/([a-z0-9_]+)(?:ps|pl)\.jpg$", path)
    if m and m.group(1) == m.group(2):
        return digital_urls(m.group(1))
    m = re.match(r"^/mono/movie/(?:adult/|japanese/)?([a-z0-9_]+)/([a-z0-9_]+)(?:ps|pl)\.jpg$", path)
    if m and m.group(1) == m.group(2):
        aws = "https://awsimgsrc.dmm.co.jp/pics_dig"
        cid = m.group(1)
        return [f"{aws}/mono/movie/{cid}/{cid}ps.jpg", f"{aws}/mono/movie/{cid}/{cid}pl.jpg"]
    return []


MAKERS = {
    "ABF": "prestige", "ABW": "prestige", "ABP": "prestige", "CHN": "prestige",
    "JUFE": "prestige", "MAAN": "prestige", "PPT": "prestige", "390JAC": "jackson",
}


def mgs_candidates(number: str) -> list[str]:
    raw = number.strip().upper()
    m = re.match(r"^([A-Z]+|390JAC)-([0-9]{2,5})$", raw)
    if not m:
        return []
    prefix, index = m.group(1), int(m.group(2))
    if index <= 0 or prefix not in MAKERS:
        return []
    lower = prefix.lower()
    maker = MAKERS[prefix]
    number3 = pad(index, 3)
    plain = str(index)
    numbers = [plain] if number3 == plain else [plain, number3]
    out = []
    for digits in numbers:
        base = f"https://image.mgstage.com/images/{maker}/{lower}/{digits}"
        out.append(f"{base}/pf_e_{lower}-{digits}.jpg")
        out.append(f"{base}/pf_o1_{lower}-{digits}.jpg")
    return out


def amazon_original(url: str) -> str | None:
    u = urlparse(url)
    host = (u.hostname or "").lower()
    if u.scheme != "https" or host not in {"m.media-amazon.com", "images-na.ssl-images-amazon.com"}:
        return None
    if u.username or u.password or u.port or u.query or u.fragment or "%" in url:
        return None
    path = u.path
    allowed_i = re.match(r"^/images/I/[A-Za-z0-9+_.-]{1,150}\.jpg$", path)
    allowed_p = re.match(r"^/images/P/[A-Z0-9]{10}\.0[19]\.MAIN\._SCRM_\.jpg$", path)
    if not (allowed_i or allowed_p):
        return None
    m = re.match(r"^(/images/I/[A-Za-z0-9+-]{1,100})\._(?:AC_)?SL[1-9][0-9]{1,3}_\.jpg$", path)
    if not m:
        return url
    original = f"https://{host}{m.group(1)}.jpg"
    return original


def identity_key(raw: str) -> str | None:
    text = raw.strip().upper()
    patterns = [
        r"^([A-Z]{1,4}[0-9]{1,4})[-_ ]([0-9]{2,10})$",
        r"^([0-9]{1,4}[A-Z]{2,12})[-_ ]?([0-9]{2,10})$",
        r"^([A-Z]{2,12})[-_ ]?([0-9]{2,10})$",
    ]
    for pat in patterns:
        m = re.match(pat, text)
        if not m:
            continue
        prefix, serial = m.group(1), m.group(2)
        if prefix.startswith("FC2"):
            return None
        n = int(serial)
        if n <= 0:
            return None
        return f"{prefix}-{n}"
    return None


def normalized_url(raw: str) -> str | None:
    value = raw.strip()
    from urllib.parse import urlsplit, urlunsplit
    p = urlsplit(value)
    scheme = (p.scheme or "").lower()
    if scheme not in {"http", "https"}:
        return None
    if not p.hostname or p.username or p.password or p.query or p.fragment:
        return None
    if p.path not in {"", "/"}:
        return None
    if p.port is not None and not (1 <= p.port <= 65535):
        return None
    # Drop path to root, keep netloc (including port).
    return urlunsplit((scheme, p.netloc, "", "", "")).rstrip("/") + ("" if ":" in p.netloc or "." in p.netloc else "")


def valid_token(token: str) -> bool:
    if token == "":
        return True
    return all(33 <= b <= 126 for b in token.encode("utf-8"))


def parse_envelope(data: bytes):
    obj = json.loads(data.decode("utf-8"))
    payload = obj.get("data")
    if payload is None:
        raise ValueError("schema")
    if not isinstance(payload, list):
        raise ValueError("schema")
    links = []
    for item in payload:
        if not isinstance(item, dict) or "id" not in item or not item.get("download_url"):
            raise ValueError("schema")
        links.append(item)
    return links


def html_is_challenge(html: str, final_url: str = "") -> bool:
    u = (final_url or "").lower()
    if any(s in u for s in ("/doc/driver-verify", "validatecaptcha", "/cdn-cgi/challenge")):
        return True
    low = (html or "").lower()
    return any(s in low for s in (
        "validatecaptcha", "/errors/validatecaptcha", "cf-chl", "just a moment",
        "cf-challenge", "driver-verify", "checking your browser",
    ))


def avbase_images(html: str, number: str):
    m = re.search(r"<script\b([^>]*)>(.*?)</script\s*>", html, re.I | re.S)
    # unique __NEXT_DATA__
    hits = []
    for sm in re.finditer(r"<script\b([^>]*)>(.*?)</script\s*>", html, re.I | re.S):
        if re.search(r"(?:^|\s)id\s*=\s*[\"']__NEXT_DATA__[\"']", sm.group(1)):
            hits.append(sm.group(2))
    if len(hits) != 1:
        return []
    root = json.loads(hits[0])
    page = (root.get("props") or {}).get("pageProps") or {}
    if page.get("work"):
        rows = [page["work"]]
    else:
        rows = page.get("works") or []
    wanted = identity_key(number)
    if not wanted:
        return []
    pool = [w for w in rows if isinstance(w, dict) and identity_key(str(w.get("work_id") or "")) and
            identity_key(str(w.get("work_id"))) == wanted]
    if len({identity_key(str(w.get("work_id"))) for w in pool}) != 1:
        return []
    out, seen = [], set()
    def consider(raw):
        if not isinstance(raw, str):
            return
        upgraded = upgrade_dmm(raw) or [raw]
        for item in upgraded:
            u = urlparse(item)
            host = (u.hostname or "").lower()
            if host not in {"awsimgsrc.dmm.co.jp", "pics.dmm.co.jp", "image.mgstage.com"}:
                continue
            if item in seen:
                continue
            seen.add(item)
            out.append(item)
    for work in pool:
        for product in work.get("products") or []:
            pid = product.get("product_id")
            if identity_key(str(pid or "")) == wanted:
                consider(product.get("image_url"))
                consider(product.get("thumbnail_url"))
    return out


def test_dmm_cids():
    assert parse_dmm_parts("FC2-123456") is None
    assert cid_candidates("SSIS-001") == ["ssis00001", "ssis001"]
    assert cid_candidates("MILK-311")[0] == "h_1240milk00311"
    assert "milk00311" in cid_candidates("MILK-311")
    assert cid_candidates("ABP-001")[0] == "118abp00001"
    urls = digital_urls("ssis00001")
    assert urls[0] == "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/ssis00001/ssis00001ps.jpg"
    assert urls[1].endswith("ssis00001pl.jpg")
    legacy = legacy_urls("ssis00001")
    assert legacy[0] == "https://pics.dmm.co.jp/digital/video/ssis00001/ssis00001pl.jpg"
    up = upgrade_dmm("https://pics.dmm.co.jp/digital/video/ssis00001/ssis00001pl.jpg")
    assert up == urls


def test_mgs():
    urls = mgs_candidates("ABP-001")
    assert "https://image.mgstage.com/images/prestige/abp/1/pf_e_abp-1.jpg" in urls
    assert "https://image.mgstage.com/images/prestige/abp/001/pf_e_abp-001.jpg" in urls
    assert mgs_candidates("SSIS-001") == []


def test_amazon():
    src = "https://m.media-amazon.com/images/I/91ktf3uskCL._SL1500_.jpg"
    assert amazon_original(src) == "https://m.media-amazon.com/images/I/91ktf3uskCL.jpg"
    already = "https://m.media-amazon.com/images/I/91ktf3uskCL.jpg"
    assert amazon_original(already) == already
    assert amazon_original("https://example.com/x.jpg") is None


def test_identity():
    assert identity_key("ssis-001") == "SSIS-1"
    assert identity_key("SSIS-001") == "SSIS-1"
    assert identity_key("FC2-123456") is None


def test_normalized_url():
    assert normalized_url("http://163.47.40.207:8000") in {
        "http://163.47.40.207:8000", "http://163.47.40.207:8000/"
    }
    assert normalized_url("https://fixture.invalid/") in {
        "https://fixture.invalid", "https://fixture.invalid/"
    }
    for invalid in [
        "ftp://fixture.invalid",
        "https://u:p@fixture.invalid",
        "https://fixture.invalid/path",
        "https://fixture.invalid?q=1",
        "https://fixture.invalid#fragment",
        "https://fixture.invalid:0",
    ]:
        assert normalized_url(invalid) is None, invalid


def test_token_and_envelope():
    assert valid_token("")
    assert valid_token("synthetic-first")
    assert not valid_token("has space")
    assert not valid_token("令牌")
    links = parse_envelope(b'{"data":[{"id":1,"download_url":"magnet:?xt=urn:btih:synthetic","title":"t"}]}')
    assert links[0]["id"] == 1 and links[0]["download_url"].startswith("magnet:")
    try:
        parse_envelope(b'{"data":null}')
        raise AssertionError("null data must fail")
    except ValueError:
        pass
    assert parse_envelope(b'{"data":[]}') == []


def test_challenge_and_avbase_fixture():
    assert html_is_challenge("<html></html>", "https://www.javbus.com/doc/driver-verify?referer=x")
    assert html_is_challenge("<html>validateCaptcha</html>", "https://www.javbus.com/SSIS-001")
    assert not html_is_challenge("<html><img src='https://www.javbus.com/pics/cover/foo_b.jpg'></html>", "https://www.javbus.com/SSIS-001")
    fixture = (ROOT / "tests" / "fixtures" / "avbase-ssis-001.html").read_text()
    images = avbase_images(fixture, "SSIS-001")
    assert any(u.endswith("ssis00001ps.jpg") for u in images)
    assert any(u.endswith("ssis00001pl.jpg") for u in images)


def main():
    tests = [
        test_dmm_cids, test_mgs, test_amazon, test_identity,
        test_normalized_url, test_token_and_envelope, test_challenge_and_avbase_fixture,
    ]
    for fn in tests:
        fn()
        print(f"PASS {fn.__name__}")
    print("PASS: external library + HQ cover helpers")


if __name__ == "__main__":
    main()
