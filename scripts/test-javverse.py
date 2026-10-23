"""Offline fixture & source-contract regression; NOT a Swift compilation/runtime substitute."""
import unittest, json, pathlib, re
ROOT=pathlib.Path(__file__).resolve().parents[1]
class JavVerseTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data=json.loads((ROOT/'AVDB/Resources/JavVerseSnapshot.json').read_text())
  cls.source=(ROOT/'AVDB/Services/JavVerseSource.swift').read_text()
  cls.policy=(ROOT/'AVDB/Services/JavVersePolicy.swift').read_text()
  cls.registration=(ROOT/'scripts/register-javverse.rb').read_text()
  cls.view=(ROOT/'AVDB/Views/JavVerseView.swift').read_text()
 def test_all_real_boards_complete(self):
  b={b['id']:b for b in self.data['boards']}
  self.assertEqual(len(b),7)
  for key in ['daily','weekly','monthly','actresses','series']:
   self.assertEqual([e['rank'] for e in b[key]['entries']],list(range(1,101)))
  self.assertEqual(len(b['featured']['entries']),8)
  self.assertEqual(len(b['recent']['entries']),12)
 def test_real_sentinels_and_no_gap_filling(self):
  b={b['id']:b for b in self.data['boards']}
  self.assertEqual(b['weekly']['entries'][0]['code'],'MFYD-204')
  self.assertEqual(b['weekly']['entries'][97]['code'],'CEMD-751')
  self.assertEqual(b['weekly']['entries'][97]['sourceURL'],b['weekly']['sourceURL'])
  self.assertEqual(b['daily']['entries'][0]['code'],'SONE-371')
  self.assertEqual(b['monthly']['entries'][0]['code'],'SNOS-377')
 def test_period_and_timestamp(self):
  self.assertEqual(self.data['mode'],'staticSnapshot')
  for b in self.data['boards']:self.assertRegex(b['capturedAt'],r'^2026-10-23T17:29:')
  b={b['id']:b for b in self.data['boards']}
  self.assertIn('未显示年份',b['monthly']['period'])
  self.assertIn('未公布',b['series']['period'])
 def test_no_images_or_avdb_ids_in_snapshot(self):
  text=json.dumps(self.data)
  self.assertNotRegex(text,r'(?i)jpg|png|cookie|token|movieID|coverURL')
 def test_exact_identity_policy(self):
  # Neutral identity cases mirrored by the Swift policy; original suffix/zeros remain distinct.
  key=lambda x:x.strip().upper()
  self.assertNotEqual(key('TEST-001'),key('TEST-1'))
  self.assertNotEqual(key('TEST-001V'),key('TEST-001'))
  self.assertIn('JavVerseIdentity.code(row.number ?? "") == key',self.policy)
  self.assertIn('matches.count <= 1',self.policy)
  self.assertIn('guard exhausted',self.policy)
  self.assertIn('unicodeScalars.allSatisfy({ $0.isASCII })',self.source)
  self.assertNotIn('movieID: entry.sourceURL',self.view)
 def test_cancel_account_and_no_scroll_search(self):
  for guard in ['self.accountProvider() == token','self.generation == epoch','prefix(20)','Task.checkCancellation()']:
   self.assertIn(guard,self.source)
  self.assertNotIn('.onAppear',self.view)
  self.assertIn('mapper.cancel()',self.view)
 def test_http_is_diagnostic_and_static_label(self):
  self.assertIn('httpCookieStorage = nil',self.source)
  self.assertIn('httpShouldHandleCookies = false',self.source)
  self.assertIn('statuses.contains(403)',self.view)
  self.assertIn('for _ in 0..<3',self.view)
  self.assertGreaterEqual(self.view.count('静态快照'),5)
 def test_schema_validation_contract(self):
  for text in ['Set(boards.map(\\.id))', 'Self.timestamp(preparedAt)', 'Self.sourceURL(entry.sourceURL)', 'board.coverage == "complete"', 'board.entries.map(\\.rank) == Array(1...board.entries.count)']:
   self.assertIn(text,self.source)
 def test_pagination_preserves_order_contract(self):
  self.assertIn('JavVersePagination.rows(board.entries, page: page)',self.view)
  self.assertIn('entries.dropFirst(page * size).prefix(size)',self.policy)
  self.assertNotIn('.sorted',self.view)
 def test_lifecycle_and_neutral_ui_contract(self):
  self.assertIn('.task(id: probing)',self.view)
  self.assertIn('.onDisappear { probeGeneration = UUID(); probing = false; mapper.cancel() }',self.view)
  self.assertIn('if !Task.isCancelled',self.view)
  self.assertIn('--javverse-neutral-ui',self.view)
  self.assertIn('JavVerseNeutralFixture.mapper()',self.view)
  self.assertIn('#if DEBUG',self.policy)
 def test_sdk_signature_and_actor_contract(self):
  sdk=(ROOT/'AVDB/Services/JavDBSDK.swift').read_text()
  for text in ['keyword: String','page: Int = 1','type: String = "movie"','limit: Int = 20']:
   self.assertIn(text,sdk)
  self.assertIn('@MainActor struct JavVerseView',self.view)
  self.assertIn('@MainActor enum JavVerseMovieResolver',self.policy)
  self.assertIn('type: "movie", limit: 20',self.source)
  search=sdk.split('public func search(',1)[1].split('public func exactMovie(',1)[0]
  self.assertIn('let requestAccount = client.token',search)
  self.assertLess(search.index('guard requestAccount == client.token'),search.index('rememberMovies(movies)'))
  self.assertIn('try Task.checkCancellation()',search)
 def test_registration_and_target_types(self):
  for text in ['JavVerseSource.swift','JavVersePolicy.swift','JavVerseView.swift','JavVerseSnapshot.json',':unit_test_bundle',':ui_test_bundle','TEST_HOST','BUNDLE_LOADER','inherit! :search_paths','--tests']:
   self.assertIn(text,self.registration)
  self.assertNotIn('RankingsView.swift',self.registration)
 def test_released238_text_only_source_label_and_version(self):
  rankings=(ROOT/'AVDB/Views/Rankings/RankingsView.swift').read_text()
  label=rankings.split('private var sourceMenuLabelContent: some View {',1)[1].split('private func reload',1)[0]
  self.assertIn('Text("来源")',label)
  self.assertNotIn('Image(',label)
  self.assertNotIn('Label(',label)
  self.assertNotIn('chevron',label)
  self.assertEqual((ROOT/'AVDB.xcodeproj/project.pbxproj').read_text().count('CURRENT_PROJECT_VERSION = 240;'),2)
if __name__=='__main__':unittest.main()
