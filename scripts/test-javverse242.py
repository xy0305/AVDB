"""242 offline contracts only; native XCTest is required for layout evidence."""
import unittest,pathlib,plistlib
R=pathlib.Path(__file__).resolve().parents[1]
class Grid242(unittest.TestCase):
 def test_local_three_columns_only(self):
  v=(R/'AVDB/Views/JavVerseView.swift').read_text()
  self.assertEqual(v.count('count: 3)'),2)
  self.assertIn('.frame(maxWidth: 760)',v)
  self.assertIn('MoviePosterCard(movie:',v)
  self.assertIn('rank: entry.rank',v)
  self.assertIn('sourceNumber: entry.label',v)
  self.assertIn('frontPoster: true',v)
  self.assertIn('mapper.resolve(rows)',v)
  self.assertNotIn('AsyncImage(',v)
  self.assertNotIn('.onAppear',v)
 def test_grok_stays_list(self):
  v=(R/'AVDB/Views/JavVerseView.swift').read_text().split('private struct JavVerseGrokPage:',1)[1]
  self.assertIn('List {',v)
  self.assertNotIn('LazyVGrid',v)
 def test_native_geometry_not_source_mock(self):
  t=(R/'UITests/JavVerseNavigationTests.swift').read_text()
  for s in ['frames[0].minY','frames[3].minY','frame.width / frame.height','TEST-004','Neutral detail TEST-001','javverse-neutral-cover-7','largeTypeGridGeometry','PAST-001','TEST-021','Metric must reorder actual rows']:
   self.assertIn(s,t)
 def test_version_and_ios(self):
  p=plistlib.loads((R/'AVDB/Resources/Info.plist').read_bytes())
  self.assertEqual(p['CFBundleVersion'],'258')
  self.assertEqual(p['CFBundleShortVersionString'],'1.0.2')
  b=(R/'AVDB.xcodeproj/project.pbxproj').read_text()
  self.assertEqual(b.count('CURRENT_PROJECT_VERSION = 260;'),2)
  self.assertIn('IPHONEOS_DEPLOYMENT_TARGET = 17.0;',b)
if __name__=='__main__':unittest.main()
