"""Neutral fixtures execute the shipping Swift identity/avbase/DMM/model parsers.
No live content fixtures and no simulated tests are reported as live evidence.
"""
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
read=lambda p:(root/p).read_text()
core=read('AVDB/Services/JavRankingCore.swift')
metadata=read('AVDB/Services/CatalogueMetadata.swift').split('private final class CatalogueRedirectBlocker:')[0]
models=read('AVDB/Services/ExternalLibraryClient.swift').split('final class ExternalLibraryClient')[0]+read('AVDB/Models/JSONFlex.swift')+read('AVDB/Models/Movie.swift')
stub='public enum CoverURLBuilder { public static func coverURLs(for number:String?) -> (poster:String?,backdrop:String?) { (nil,nil) } }\n'
source=core+metadata+stub+models+r'''
@main struct CatalogueRegression {
 static func main() throws {
  for n in ["R18-292","r18_292","Ｒ１８－２９２","723GGH-009","200GANA-3000","13DSVR-1968","IPX-247","FC2-PPV-1234567"] { assert(JRPolicy.exactCode(n) != nil,n) }
  assert(JRPolicy.exactCode("R18-292") == "R18-292")
  assert(JRPolicy.exactCode("R18-292") != JRPolicy.exactCode("R1-8292"))
  assert(JRPolicy.exactCode("R18292") == nil)
  assert(JRPolicy.exactCode("723GGH-009") != JRPolicy.exactCode("GGH-009"))
  assert(JRPolicy.catalogueCode("R18-292 neutral fixture") == "R18-292")
  assert(JRPolicy.catalogueCode("XR18-2920bad") == nil)
  assert(JRPolicy.exactCode("R18-292 suffix") == nil)
  assert(JRPolicy.exactCode("FC2-PPV-00123") == "FC2PPV00123")
  assert(JRPolicy.exactCode("Studio.2026.10.20") == nil)
  assert(CatalogueIdentity.key("FC2-12345") == nil)
  assert(CatalogueIdentity.key("R18-0292") == "R18-292")
  assert(CatalogueIdentity.key("723GGH-009") == "723GGH-9")
  assert(CatalogueIdentity.matches("GGH-009",wanted:"723GGH-009"))
  assert(!CatalogueIdentity.matches("123GGH-009",wanted:"723GGH-009"))
  assert(!CatalogueIdentity.matches("R18-292",wanted:"R19-292"))
  assert(CatalogueIdentity.queryForms("R18-292") == ["R18-292","R18292"])
  func page(_ works:[[String:Any]]) throws -> String {
   let data=try JSONSerialization.data(withJSONObject:["props":["pageProps":["works":works]]])
   return "<script id='__NEXT_DATA__' type='application/json'>"+String(data:data,encoding:.utf8)!+"</script>"
  }
  let jp="https://awsimgsrc.dmm.co.jp/pics_dig/digital/amateur/ggh009/ggh009jp.jpg"
  let linked="https://video.dmm.co.jp/amateur/content/?id=ggh009"
  let product:[String:Any] = ["product_id":"ggh009","url":linked,"thumbnail_url":jp,"image_url":jp,"maker":["name":"Neutral maker"],"iteminfo":["volume":"01:30:00"]]
  let work:[String:Any] = ["work_id":"GGH-009","prefix":"","title":"Neutral fixture","products":[product],"min_date":"Thu Mar 23 2023 09:00:00 GMT+0900 (Japan Standard Time)","actors":[["name":"Neutral actor"]]]
  let html=try page([work])
  let result=AvbaseMetadata.parse(html:html,number:"723GGH-009")!
  assert(result.number == "723GGH-009" && result.digitalCID == "ggh009")
  assert(result.poster == jp && result.cover == jp && result.images == [jp])
  assert(result.releaseDate == "2023-03-23" && result.duration == 90)
  assert(result.actorNames == ["Neutral actor"])
  assert(result.sourceURL == "https://www.avbase.net/works/GGH-009")
  assert(AvbaseMetadata.parse(html:html,number:"723GGH-010") == nil)
  assert(AvbaseMetadata.parse(html:html+html,number:"723GGH-009") == nil)
  var duplicate=work;duplicate["prefix"]="edition"
  assert(AvbaseMetadata.selected([duplicate,work],number:"723GGH-009")?["prefix"] as? String == "")
  var other=work;other["work_id"]="123GGH-009"
  assert(AvbaseMetadata.selected([other],number:"723GGH-009") == nil)
  var conflicting=work;conflicting["work_id"]="456GGH-009"
  assert(AvbaseMetadata.selected([other,conflicting],number:"GGH-009") == nil)
  var p2=product;p2["product_id"]="unrelated001"
  var w2=work;w2["products"]=[p2]
  let unrelatedHTML = try page([w2])
  assert(AvbaseMetadata.parse(html:unrelatedHTML,number:"723GGH-009")?.images.isEmpty == true)
  let bad="https://awsimgsrc.dmm.co.jp/pics_dig/digital/amateur/other001/other001jp.jpg"
  assert(AvbaseMetadata.image(bad,productID:"ggh009",dmm:true) == nil)
  assert(AvbaseMetadata.image(jp+"?w=999",productID:"ggh009",dmm:true) == nil)
  assert(AvbaseMetadata.image(jp.replacingOccurrences(of:"awsimgsrc.dmm.co.jp",with:"awsimgsrc.dmm.co.jp.evil.test"),productID:"ggh009",dmm:true) == nil)
  assert(AvbaseMetadata.image(jp.replacingOccurrences(of:"jp.jpg",with:"jp-1.jpg"),productID:"ggh009",dmm:true) == nil)
  let mgs="https://image.mgstage.com/images/shirouto/sp/siro/5000/h1-06_sp-siro-5000.jpg"
  assert(AvbaseMetadata.image(mgs,productID:"SIRO-5000",dmm:false) == mgs)
  assert(AvbaseMetadata.image(mgs.replacingOccurrences(of:"h1-06",with:"sample-06"),productID:"SIRO-5000",dmm:false) == nil)
  assert(AvbaseMetadata.image(mgs,productID:"SIRO-5001",dmm:false) == nil)
  assert(AvbaseMetadata.image(jp,productID:"ggh009",dmm:false) == nil)
  assert(DMMAmateurMetadata.link(linked)?.amateur == true)
  assert(DMMAmateurMetadata.boundLink(linked,number:"723GGH-009")?.cid == "ggh009")
  assert(DMMAmateurMetadata.boundLink(linked,number:"723GGH-010") == nil)
  assert(AvbaseMetadata.image(jp,productID:"ggh009",dmm:true,namespace:"/digital/video/") == nil)
  assert(DMMAmateurMetadata.link(linked+"&id=other001") == nil)
  assert(DMMAmateurMetadata.link("https://video.dmm.co.jp.evil.test/amateur/content/?id=ggh009") == nil)
  func dmm(_ package:[String:Any]) throws -> Data {
   try JSONSerialization.data(withJSONObject:["data":["ppvContent":["title":"Neutral direct fixture","duration":5400,"packageImage":package,"description":"<p>Neutral text</p><script>unsafe()</script>"]]])
  }
  let packages:[[String:Any]] = [["largeUrl":NSNull(),"mediumUrl":jp],["mediumUrl":jp],["largeUrl":jp]]
  for package in packages {
   let direct=DMMAmateurMetadata.parse(data:try dmm(package),cid:"ggh009",number:"723GGH-009")!
   assert(direct.cover == jp && direct.poster == jp && direct.duration == 90)
   assert(direct.summary == "Neutral text")
  }
  assert(DMMAmateurMetadata.parse(data:Data(#"{"errors":[{}],"data":{"ppvContent":{"title":"No"}}}"#.utf8),cid:"ggh009",number:"723GGH-009") == nil)
  assert(DMMAmateurMetadata.parse(data:Data(#"{"data":{"ppvContent":null}}"#.utf8),cid:"ggh009",number:"723GGH-009") == nil)
  let movie=Movie(id:"real-javdb-id",type:"0",number:"723GGH-009")
  let enriched=movie.withCatalogueMetadata(result)
  assert(enriched.id == movie.id && enriched.number == movie.number && enriched.type == "0")
  assert(enriched.title == "Neutral fixture" && enriched.coverURL == jp && enriched.duration == 90)
  let preserved=Movie(id:"id",type:"0",number:"723GGH-009",title:"Primary title",coverURL:"https://existing.test/image.jpg").withCatalogueMetadata(result)
  assert(preserved.title == "Primary title" && preserved.coverURL == "https://existing.test/image.jpg")
  assert(Movie(id:"id",type:"2",number:"723GGH-009").withCatalogueMetadata(result).title == nil)
  assert(Movie(id:"id",type:"0",number:"723GGH-010").withCatalogueMetadata(result).catalogueMetadata == nil)
  assert(Movie(id:"id",number:"R18-292").codePrefix == "R18")
  assert(Movie(id:"id",number:"723GGH-009").codePrefix == "723GGH")
  print("PASS native production numeric-prefix identity, avbase namespaces/record binding, nullable amateur package images, unchanged JavDB IDs and metadata merge")
 }
}
'''
assert 'private func enrichCatalogue' in read('AVDB/Services/JavDBSDK.swift')
assert 'bound + exact + sources + rules' in read('AVDB/Services/DetailPosterResolver.swift')
assert 'singleImage' in read('AVDB/Services/DetailPosterResolver.swift')
assert 'httpCookieStorage = nil' in read('AVDB/Services/CatalogueMetadata.swift')
assert 'CatalogueMetadata.swift in Sources' in read('AVDB.xcodeproj/project.pbxproj')
if shutil.which('swiftc'):
 with tempfile.TemporaryDirectory() as tmp:
  p=Path(tmp);(p/'tests.swift').write_text(source)
  subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(p/'tests.swift'),'-o',str(p/'tests')],check=True)
  subprocess.run([str(p/'tests')],check=True)
else:
 print('SKIP native fixture execution: Swift compiler unavailable locally; macOS release CI must execute this test')
print('PASS catalogue metadata source integration contracts (not a live provider success claim)')
