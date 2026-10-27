"""Offline HTML parser contracts for JavVerse live fetch. No network in CI."""
import json, pathlib, re, unittest
from html import unescape

R = pathlib.Path(__file__).resolve().parents[1]
FIX = R / "scripts/javverse-fixtures"
SOURCE = (R / "AVDB/Services/JavVerseSource.swift").read_text()
LIVE = (R / "AVDB/Services/JavVerseLiveClient.swift").read_text()
VIEW = (R / "AVDB/Views/JavVerseView.swift").read_text()


def movie_entries(html: str, page_url: str):
    entries = []
    for m in re.finditer(
        r'<(a|div)\b([^>]*\bid="rank-(\d+)"[^>]*)>(.*?)(?=<(?:a|div)\b[^>]*\bid="rank-\d+"|$)',
        html, re.S,
    ):
        rank = int(m.group(3))
        attrs, body = m.group(2), m.group(4)
        code = re.search(r'aria-label="([A-Z0-9]+-[A-Z0-9]+)"', attrs + body[:900])
        if not code:
            code = re.search(r'alt="([A-Z0-9]+-[A-Z0-9]+) 封面"', body)
        assert code, f"missing code rank {rank}"
        work = re.search(r'href="(/work/\d+)"', attrs)
        if work:
            source = "https://javverse.com" + work.group(1)
        else:
            source = page_url.split("#", 1)[0] + f"#rank-{rank}"
        entries.append({"rank": rank, "code": code.group(1).upper(), "sourceURL": source})
    entries.sort(key=lambda e: e["rank"])
    return entries


def person_entries(html: str, prefix: str):
    entries = []
    for m in re.finditer(
        r'<a\b([^>]*\bid="rank-(\d+)"[^>]*)>(.*?)(?=<a\b[^>]*\bid="rank-\d+"|$)',
        html, re.S,
    ):
        rank = int(m.group(2))
        href = re.search(rf'href="({re.escape(prefix)}\d+)"', m.group(1))
        name = re.search(r'class="rank-entry-name"[^>]*>([^<]+)', m.group(3))
        assert href and name
        entries.append({"rank": rank, "label": name.group(1), "href": href.group(1)})
    return sorted(entries, key=lambda e: e["rank"])


def grok_people(html: str):
    marker = html.find('\\"people\\":')
    assert marker >= 0
    unescaped = html[marker:].replace('\\"', '"').replace('\\\\', '\\')
    i = unescaped.find("[")
    depth = 0
    end = None
    for j, ch in enumerate(unescaped[i:], i):
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                end = j + 1
                break
    return json.loads(unescaped[i:end])


class LiveContracts(unittest.TestCase):
    def test_mode_accepts_live_and_static(self):
        self.assertIn('["staticSnapshot", "liveFetch"].contains(mode)', SOURCE)
        self.assertIn("mode: \"liveFetch\"", LIVE)
        self.assertIn("JavVerseLiveClient.fetchSnapshot", VIEW)
        self.assertIn("离线快照", VIEW)
        self.assertIn("实时", VIEW)
        self.assertIn("javverse-refresh", VIEW)
        self.assertIn("x-jv-gate", LIVE)
        self.assertIn("/_browse/gate", LIVE)
        self.assertNotIn("?term=weekly", LIVE)
        # Never claim live when using bundle.
        self.assertIn('mode: "liveFetch"', LIVE)
        self.assertIn("JavVerseSnapshot.bundled()", VIEW)

    def test_probe_stays_cookieless(self):
        probe = SOURCE.split("enum JavVerseHTTPProbe", 1)[1]
        self.assertIn("httpCookieStorage = nil", probe)
        self.assertIn("httpShouldHandleCookies = false", probe)

    def test_live_client_uses_cookie_jar(self):
        self.assertIn("httpShouldSetCookies = true", LIVE)
        self.assertIn("httpCookieAcceptPolicy = .always", LIVE)
        self.assertNotIn("print(cookie", LIVE.lower())
        self.assertNotIn("NSLog", LIVE)

    def test_weekly_fixture_parses_absent_and_codes(self):
        html = (FIX / "weekly-snippet.html").read_text()
        entries = movie_entries(html, "https://javverse.com/rankings/dmm")
        by_rank = {e["rank"]: e for e in entries}
        self.assertEqual(by_rank[1]["code"], "MFYD-204")
        self.assertTrue(by_rank[1]["sourceURL"].endswith("/work/1274"))
        self.assertEqual(by_rank[98]["code"], "CEMD-751")
        self.assertTrue(by_rank[98]["sourceURL"].endswith("#rank-98"))
        self.assertIn("data-absent", html)

    def test_daily_fixture_period_links(self):
        html = (FIX / "daily-snippet.html").read_text()
        links = sorted({unescape(x) for x in re.findall(r'href="(/rankings/dmm\?[^"]*)"', html)})
        self.assertTrue(any("term=daily&period=" in x or "term=daily&amp;period=" in x for x in re.findall(r'href="([^"]+)"', html)))
        entries = movie_entries(html, "https://javverse.com/rankings/dmm?term=daily")
        self.assertEqual(entries[0]["code"], "SNOS-489")

    def test_actresses_and_series_fixtures(self):
        a = person_entries((FIX / "actresses-snippet.html").read_text(), "/actress/")
        self.assertEqual(a[0]["label"], "逢沢みゆ")
        self.assertIn("河北彩花", a[1]["label"])
        s = person_entries((FIX / "series-snippet.html").read_text(), "/series/")
        self.assertEqual(s[0]["label"], "S1 GIRLS COLLECTION")

    def test_grok_fixture_people(self):
        people = grok_people((FIX / "grok-snippet.html").read_text())
        self.assertEqual(len(people), 2)
        self.assertEqual(people[0]["id"], "aika")
        self.assertEqual(set(people[0]["scores"]), {"total", "works", "pop", "face", "body", "award", "years"})
        sample = json.loads((FIX / "grok-people-sample.json").read_text())
        self.assertEqual(sample[0]["actressId"], 409)

    def test_pbx_registers_live_client(self):
        pbx = (R / "AVDB.xcodeproj/project.pbxproj").read_text()
        self.assertGreaterEqual(pbx.count("JavVerseLiveClient.swift"), 4)
        reg = (R / "scripts/register-javverse.rb").read_text()
        self.assertIn("JavVerseLiveClient.swift", reg)

    def test_bundled_snapshot_still_static(self):
        data = json.loads((R / "AVDB/Resources/JavVerseSnapshot.json").read_text())
        self.assertEqual(data["mode"], "staticSnapshot")


if __name__ == "__main__":
    unittest.main()
