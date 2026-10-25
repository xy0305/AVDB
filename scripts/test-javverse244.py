"""244: bundled JavVerse timestamps must validate without relaxing rank or source checks."""
import json
import plistlib
import unittest
from pathlib import Path

R = Path(__file__).resolve().parents[1]
PARSER = r'''    private static func timestamp(_ text: String) -> Bool {
        // 243 rejected fractional offsets such as 2026-10-24T03:58:55.413884+00:00.
        // Fractional or whole seconds are valid with Z or ±HH:MM. A zone is required.
        guard let separator = text.firstIndex(of: "T") else { return false }
        let clock = text[text.index(after: separator)...]
        guard clock.contains(":") else { return false }
        let zone = clock.suffix(6)
        let numericZone = zone.count == 6 && (zone.hasPrefix("+") || zone.hasPrefix("-"))
            && zone.dropFirst(1).dropLast(3).allSatisfy(\.isNumber)
            && zone.dropFirst(3).first == ":"
            && zone.suffix(2).allSatisfy(\.isNumber)
        guard clock.hasSuffix("Z") || numericZone else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: text) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text) != nil
    }
'''

class JavVerseTimestamp244(unittest.TestCase):
    def test_real_bundled_offset_is_accepted_without_relaxing_ranks(self):
        source = (R / "AVDB/Services/JavVerseSource.swift").read_text()
        data = json.loads((R / "AVDB/Resources/JavVerseSnapshot.json").read_text())
        prepared = data["preparedAt"]
        self.assertEqual(prepared, "2026-10-24T03:58:55.413884+00:00")
        self.assertEqual(data["grok"]["capturedAt"], prepared)
        self.assertIn(prepared, PARSER)
        self.assertIn(PARSER, source)
        self.assertIn(".withFractionalSeconds", PARSER)
        self.assertIn('guard clock.hasSuffix("Z") || numericZone else { return false }', PARSER)
        self.assertEqual(len(data["boards"]), 13)
        self.assertEqual(len(data["grok"]["people"]), 250)
        for board in data["boards"]:
            ranks = [entry["rank"] for entry in board["entries"]]
            self.assertEqual(ranks, list(range(1, len(board["entries"]) + 1)), board["id"])
            self.assertTrue(board["capturedAt"].endswith("Z"))
        self.assertIn("board.entries.map(\\.rank) == Array(1...board.entries.count)", source)
        self.assertIn('board.coverage == "complete"', source)
        self.assertIn("grok.people.count == 250", source)

    def test_naive_timestamps_fail_closed_and_version_is_244(self):
        source = (R / "AVDB/Services/JavVerseSource.swift").read_text()
        parser = source.split("private static func timestamp", 1)[1].split("private static func sourceURL", 1)[0]
        gate = parser.split("guard clock.hasSuffix", 1)[0]
        self.assertNotIn("return true", gate)
        info = plistlib.loads((R / "AVDB/Resources/Info.plist").read_bytes())
        self.assertEqual((info["CFBundleShortVersionString"], info["CFBundleVersion"]), ("1.0.2", "258"))
        project = (R / "AVDB.xcodeproj/project.pbxproj").read_text()
        self.assertEqual(project.count("CURRENT_PROJECT_VERSION = 258;"), 2)
        self.assertEqual(project.count("MARKETING_VERSION = 1.0.2;"), 2)
        replay = (R / "scripts/test-actor-avatar243.py").read_text()
        self.assertIn('source.split("struct TMDBAvatarTokenStore", 1)[0]', replay)
        self.assertIn('main = "import Foundation\\n"', replay)
        self.assertNotIn("import Foundation\nlet names", replay)

if __name__ == "__main__":
    unittest.main()

# replay stubs stay local to the standalone avatar test

# missing-key replay stub is test-only
