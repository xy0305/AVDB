"""241 source/fixture checks. Not Swift execution; hosted macOS acceptance remains required."""
import unittest,json,pathlib,hashlib,functools
R=pathlib.Path(__file__).resolve().parents[1]
class HistoryGrok241(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.data=json.loads((R/'AVDB/Resources/JavVerseSnapshot.json').read_text());cls.boards=cls.data['boards'];cls.people=cls.data['grok']['people']
 def test_legacy_520_fields_exact(self):
  fields=['id','title','period','capturedAt','sourceURL','coverage','entries']
  original=[{k:b[k] for k in fields} for b in self.boards[:7]]
  digest=hashlib.sha256(json.dumps(original,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
  self.assertEqual(digest,'7ed4798f85bf7a3aff7db4cc5aa023946a777b1823ba14e31d395f78d8d653f5')
 def test_actual_periods_only(self):
  day=[b['periodKey'] for b in self.boards if b.get('term')=='daily']
  self.assertEqual(day,['2026-10-22','2026-10-21','2026-10-20','2026-10-19','2026-10-18','2026-10-17'])
  week=[b['periodKey'] for b in self.boards if b.get('term')=='weekly'];self.assertEqual(week,['2026-10-16','2026-10-09'])
  self.assertEqual(len([b for b in self.boards if b.get('term')=='monthly']),1)
 def test_history_distinct_actual_sentinels(self):
  byid={b['id']:b for b in self.boards}
  self.assertEqual(byid['daily-2026-10-18']['entries'][0]['code'],'NPJB-102')
  self.assertEqual(byid['daily-2026-10-17']['entries'][0]['code'],'SKHB-009')
  self.assertEqual(byid['weekly-2026-10-09']['entries'][0]['code'],'SPONE-001')
  self.assertEqual(len({tuple(e['code'] for e in b['entries']) for b in self.boards if b.get('term')=='daily'}),6)
 def test_history_contiguous_original_ranks(self):
  for b in self.boards[7:]:
   self.assertEqual([e['rank'] for e in b['entries']],list(range(1,101)))
   self.assertIn(b['periodKey'],b['sourceURL'])
 def test_grok_same_original_score_values_and_no_portraits(self):
  self.assertEqual(len(self.people),250);self.assertEqual(len(set(p['id'] for p in self.people)),250)
  self.assertEqual(sum(p['status']=='已故' for p in self.people),2)
  source=(R/'AVDB/Services/JavVerseSource.swift').read_text()
  self.assertIn('["现役", "引退", "已故"].contains($0.status)',source)
  for p in self.people:
   self.assertNotIn('imageUrl',p);self.assertNotIn('works',p)
   self.assertEqual(set(p['scores']),{'total','works','pop','face','body','award','years'})
   for k,v in p['scores'].items():self.assertEqual(p['scoreText'][k],f'{v/1000:.2f}')
 def test_five_metric_public_sort_hashes(self):
  expected=['087f6f8b972c73b2af13f4b729e39a99e7bc1e3d2857101de15b7ef036b7ea64','ee79aa0a2681f391abe9153eb58c56cbc2bafa0fc9c5398696a5d3724649eb0e','3901d039b594d14e89e0223fd5600b2732885a254852989ba391f90cec5b1197','d3fe2dbfa573cff8aaf29a28f03883962ff225ce531758a6f4f6fb09912b7618','702420b98b2ce2e3e0ad66fa5ed3deedc1b223e34d2544238e7223a5d438c58d']
  for metric,digest in zip(['total','works','pop','face','body'],expected):
   ordered=sorted(self.people,key=lambda p:(-p['scores'][metric],-p['scores']['works'] if metric=='total' else 0,p['nameJa'].encode('utf-16-be'),p['id'].encode('utf-16-be')))
   actual=hashlib.sha256('|'.join(p['id'] for p in ordered).encode()).hexdigest();self.assertEqual(actual,digest)
 def test_scoped_cancellable_immediate_list_contract(self):
  source=(R/'AVDB/Services/JavVerseSource.swift').read_text();view=(R/'AVDB/Views/JavVerseView.swift').read_text()
  self.assertIn('cachedBundle',source);self.assertIn('scope',source)
  self.assertIn('JavVerseMapper(scope: board.selectionKey)',view)
  self.assertIn('.id(selected.selectionKey)',view)
  self.assertIn('rows.prefix(6)',view)
  self.assertIn('selection: $tab, scrolls: false',view)
  self.assertNotIn('AsyncImage(',view)
 def test_native_registration_and_test_content(self):
  tests=(R/'UITests/JavVerseBehaviorTests.swift').read_text();ui=(R/'UITests/JavVerseNavigationTests.swift').read_text()
  for name in ['test241RealHistory','test241GrokAllFive','test241PeriodRace','test241MetadataImmediately']:self.assertIn(name,tests)
  self.assertIn('Four tabs must occupy one compact underline row',ui)
if __name__=='__main__':unittest.main()
