"""244: TMDB key is entered in-app and never bundled. No live person lookup."""
import plistlib
import unittest
from pathlib import Path

R = Path(__file__).resolve().parents[1]


class TMDBAvatar244(unittest.TestCase):
    def test_key_is_device_keychain_not_environment_or_bundle(self):
        resolver = (R / "AVDB/Services/ExternalActorResolver.swift").read_text()
        settings = (R / "AVDB/Views/User/UserView.swift").read_text()
        self.assertIn("struct TMDBAvatarTokenStore: ExternalTokenStore", resolver)
        self.assertIn('kSecAttrService as String: "app.avdb.tmdb-avatar"', resolver)
        self.assertIn("kSecAttrAccessibleWhenUnlockedThisDeviceOnly", resolver)
        self.assertIn("TMDBAvatarSettings.shared.currentKey()", resolver)
        self.assertNotIn('ProcessInfo.processInfo.environment["TMDB_API_KEY"]', resolver)
        self.assertIn('SecureField("TMDB 头像（不回显）"', resolver)
        self.assertIn('Text(settings.configured ? "已设置（不显示内容）" : "未设置")', resolver)
        self.assertIn("if !trimmed.isEmpty { try store.write(trimmed) }", resolver)
        self.assertIn('Button("清除", role: .destructive)', resolver)
        self.assertIn("https://api.themoviedb.org", resolver)
        self.assertIn("不写入日志，不进入 IPA", resolver)
        self.assertIn("tmdb-avatar-settings-entry", settings)
        self.assertIn("guard !key.isEmpty else", resolver)

    def test_missing_key_is_visible_and_existing_avatar_still_wins(self):
        verse = (R / "AVDB/Services/JavVerseSource.swift").read_text()
        view = (R / "AVDB/Views/JavVerseView.swift").read_text()
        miss = (R / "AVDB/Services/MissAVMetadata.swift").read_text()
        self.assertIn('lookup.status == .missingKey { avatarStatus[entry.id] = "未设置" }', verse)
        self.assertIn('Text("未设置")', view)
        self.assertIn('avatar.status == .missingKey ? "未设置"', miss)
        self.assertIn("Existing AVDB artwork always wins", (R / "AVDB/Services/ExternalActorResolver.swift").read_text())
        self.assertIn("hits.count == 1", (R / "AVDB/Services/ExternalActorResolver.swift").read_text())

    def test_version_and_no_secret_literal(self):
        info = plistlib.loads((R / "AVDB/Resources/Info.plist").read_bytes())
        project = (R / "AVDB.xcodeproj/project.pbxproj").read_text()
        self.assertEqual(info["CFBundleShortVersionString"], "1.0.2")
        self.assertEqual(info["CFBundleVersion"], "250")
        self.assertEqual(project.count("CURRENT_PROJECT_VERSION = 250;"), 2)
        self.assertEqual(project.count("IPHONEOS_DEPLOYMENT_TARGET = 17.0;"), 4)
        blob = (R / "AVDB/Services/ExternalActorResolver.swift").read_bytes()
        self.assertNotIn(b"eyJ", blob)
        self.assertNotIn(b"api_key=", blob)


if __name__ == "__main__":
    unittest.main()
