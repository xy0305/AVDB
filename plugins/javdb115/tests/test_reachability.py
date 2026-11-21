#!/usr/bin/env python3
"""Live reachability of public default hosts. Blocked sources are reported, never bypassed."""
from __future__ import annotations
import ssl, sys, time, urllib.error, urllib.request

UA = "AVDB115-plugin-reachability/1.0"

def probe(url: str, timeout: int = 10, context=None):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=context) as r:
            body = r.read(512)
            return {
                "ok": True,
                "status": r.status,
                "final": r.geturl(),
                "type": r.headers.get("Content-Type"),
                "dt": round(time.time() - t0, 2),
                "sample": body[:80],
                "error": None,
            }
    except urllib.error.HTTPError as e:
        body = e.read(200)
        return {
            "ok": False,
            "status": e.code,
            "final": getattr(e, "geturl", lambda: url)(),
            "type": e.headers.get("Content-Type") if e.headers else None,
            "dt": round(time.time() - t0, 2),
            "sample": body[:80],
            "error": f"HTTP {e.code}",
        }
    except Exception as e:
        return {
            "ok": False, "status": None, "final": url, "type": None,
            "dt": round(time.time() - t0, 2), "sample": b"", "error": type(e).__name__ + ": " + str(e)[:180],
        }


def main():
    ctx = ssl.create_default_context()
    rows = []
    # Required public deterministic sources used by the plugin.
    required = [
        ("DMM awsimgsrc SSIS-001 ps",
         "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/ssis00001/ssis00001ps.jpg",
         {200}),
        ("DMM pics SSIS-001 pl",
         "https://pics.dmm.co.jp/digital/video/ssis00001/ssis00001pl.jpg",
         {200}),
        ("MGS ABP-001 pf_e",
         "https://image.mgstage.com/images/prestige/abp/001/pf_e_abp-001.jpg",
         {200}),
        ("External Library default root (no token)",
         "http://163.47.40.207:8000/",
         {200}),
        ("External Library API without token",
         "http://163.47.40.207:8000/api/v1/articles/torrents?keyword=SSIS-001",
         {401}),  # documented: token required
    ]
    optional = [
        ("JavBus SSIS-001 (may be driver-verify)",
         "https://www.javbus.com/SSIS-001"),
        ("Avbase works?q=SSIS-001 (may be 403)",
         "https://www.avbase.net/works?q=SSIS-001"),
        ("Tenhow homepage (not used as a URL constructor in v2)",
         "https://www.tenhow.net/"),
    ]
    failed = []
    for name, url, expect in required:
        r = probe(url, context=ctx if url.startswith("https") else None)
        status = r["status"]
        ok = status in expect
        print(f"{'PASS' if ok else 'FAIL'} {name}: status={status} expect={sorted(expect)} time={r['dt']}s final={r['final']} err={r['error']}")
        if not ok:
            failed.append(name)
        rows.append((name, r))
    for name, url in optional:
        r = probe(url, context=ctx)
        final = r["final"] or ""
        blocked = r["status"] in {403, 429, 503} or "driver-verify" in final or "validateCaptcha" in final
        note = "BLOCKED/CHALLENGE (no bypass)" if blocked else f"status={r['status']}"
        print(f"INFO {name}: {note} final={final} err={r['error']}")
        rows.append((name, r))
    if failed:
        print("FAIL required public sources:", ", ".join(failed))
        sys.exit(1)
    print("PASS required public sources reachable (or 401 without token as documented)")


if __name__ == "__main__":
    main()
