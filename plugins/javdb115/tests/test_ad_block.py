#!/usr/bin/env python3
"""Unit tests for identified JavDB in-house ad request matching.

These tests document which URLs may be blocked by a native hook, and
which must be left alone. They do not claim Flutter-painted ads are gone.
"""
from __future__ import annotations
from urllib.parse import urlparse

AD_HOSTS = {
    "jdforrepam.com",
    "www.jdforrepam.com",
    "staging.letidi.com",
    "letidi.com",
    "www.letidi.com",
}


def host_ok(host: str) -> bool:
    host = (host or "").lower()
    if host in AD_HOSTS:
        return True
    return any(host.endswith("." + base) for base in AD_HOSTS)


def is_ad_request(url: str) -> bool:
    u = urlparse(url)
    if u.scheme not in {"http", "https"}:
        return False
    if not host_ok(u.hostname):
        return False
    path = u.path or ""
    return path == "/api/v1/ads" or path.startswith("/api/v1/ads/")


def is_protected(url: str) -> bool:
    u = urlparse(url)
    host = (u.hostname or "").lower()
    path = u.path or ""
    if path.startswith((
        "/api/v1/auth", "/api/v1/sessions", "/api/v1/wallets",
        "/api/v2/plans", "/api/v3/plans", "/api/v4/plans",
        "/api/v1/movies", "/api/v2/movies", "/api/v4/movies",
        "/api/v1/search", "/api/v2/search", "/api/v1/advanced_search",
        "/api/v1/startup", "/api/v1/magnet",
    )):
        return True
    if host == "jdbstatic.com" or host.endswith(".jdbstatic.com"):
        return True
    if any(host.endswith(s) for s in (
        "dmm.co.jp", "mgstage.com", "avbase.net", "javbus.com",
        "115.com", "anxia.com", "115cdn.net",
    )):
        return True
    return False


def should_block(url: str, enabled: bool = True) -> bool:
    if not enabled:
        return False
    if is_protected(url):
        return False
    return is_ad_request(url)


ADS = [
    "https://jdforrepam.com/api/v1/ads",
    "https://jdforrepam.com/api/v1/ads/splash_log",
    "https://jdforrepam.com/api/v1/ads/splash_log?id=1",
    "https://staging.letidi.com/api/v1/ads",
    "http://jdforrepam.com/api/v1/ads",
]

PROTECTED = [
    "https://jdforrepam.com/api/v1/movies/latest",
    "https://jdforrepam.com/api/v1/movies/recommend",
    "https://jdforrepam.com/api/v1/advanced_search",
    "https://jdforrepam.com/api/v1/startup",
    "https://jdforrepam.com/api/v1/auth/captcha",
    "https://jdforrepam.com/api/v1/sessions",
    "https://jdforrepam.com/api/v2/plans/payment_order",
    "https://jdforrepam.com/api/v3/plans",
    "https://jdforrepam.com/api/v4/plans/payment_order",
    "https://jdforrepam.com/api/v1/wallets/sfpay_banks",
    "https://jdforrepam.com/api/v1/search_magnet",
    "https://c0.jdbstatic.com/covers/aq/AqXeXO.jpg",
    "https://c0.jdbstatic.com/samples/aq/AqXeXO_l_0.jpg",
    "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/ssis00001/ssis00001ps.jpg",
    "https://image.mgstage.com/images/prestige/abf/015/pf_e_abf-015.jpg",
    "https://115.com/?ct=offline&ac=space",
    "https://www.avbase.net/works?q=SSIS-001",
]

NEAR_MISS = [
    "https://jdforrepam.com/api/v1/adsome",
    "https://jdforrepam.com/api/v1/articles",
    "https://example.com/api/v1/ads",
    "https://javdb.com/api/v1/ads",  # not an app API host observed in the IPA
]


def test_ad_endpoints_match():
    for url in ADS:
        assert is_ad_request(url), url
        assert should_block(url)
        assert not is_protected(url)


def test_protected_never_blocked():
    for url in PROTECTED:
        assert not should_block(url), url
        # ads path on a payment host would still be protected first if path matches plans/auth
        # none of these are ad paths


def test_near_miss_and_disable():
    for url in NEAR_MISS:
        assert not should_block(url), url
    for url in ADS:
        assert not should_block(url, enabled=False)


def test_does_not_claim_all_ads_blocked():
    # Invariant: Flutter-painted inventory is identified, not "all ads gone".
    assert is_ad_request("https://jdforrepam.com/api/v1/ads")
    assert not is_ad_request("https://c0.jdbstatic.com/covers/aq/AqXeXO.jpg")


def main():
    for fn in [test_ad_endpoints_match, test_protected_never_blocked, test_near_miss_and_disable, test_does_not_claim_all_ads_blocked]:
        fn()
        print(f"PASS {fn.__name__}")
    print("PASS: ad request matching (identified in-house APIs only)")


if __name__ == "__main__":
    main()
