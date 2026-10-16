"""DMM safety regressions run actual Swift production parsers/scheduler on macOS."""
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
services=root/'AVDB/Services'
core='\n'.join((services/f).read_text() for f in ['JavRankingCore.swift','TenhowPoster.swift','TenhowActorLinks.swift','DetailPosterPolicy.swift'])
resolver=(services/'DetailPosterResolver.swift').read_text()
for literal in ['DMMPoster.candidates(metadata:', 'validatedSources(movie)', 'official.count <= 2', 'matches.formUnion(match.images)', 'result += images.prefix(1)', 'target.path == path']:
    assert literal in resolver,literal
assert 'HEAD' not in resolver and 'Referer' not in resolver
assert 'maxAttempts = 6' in core and 'concurrency = 2' in core and 'totalBudget: TimeInterval = 12' in core
swift=r'''
@main struct DMMRegression {
 static func main() async throws {
  typealias T = TenhowPoster
  for (raw, expected) in [("118abf295","abf-295"),("1sods098","sods-98"),("d2gvh891","gvh-891"),("h_1059godr1287","godr-1287")] {
   assert(T.cid(raw,storefront:.retail) == expected)
  }
  assert(T.cid("ssis00497",storefront:.digital) == "ssis-497")
  assert(T.cid("13dsvr01968",storefront:.digital) == "13dsvr-1968")
  assert(T.cid("13dsvr01968",storefront:.retail) == nil)
  assert(T.number("13DSVR-1968") == "13dsvr-1968")
  assert(T.cid("dsvr01968",storefront:.digital) != T.cid("13dsvr01968",storefront:.digital))
  assert(T.cid("118abf295",storefront:.digital) == nil)
  for raw in ["118abf295a","118abf295so","118abf295限定","13dsvr01968x","d2gvh891s","h_1059godr1287pl","118abf000"] {
   assert(T.cid(raw,storefront:.retail) == nil)
  }
  func link(_ cid:String,_ store:T.Storefront) -> String {
   let target = store == .retail ? "https://www.dmm.co.jp/mono/dvd/-/detail/=/cid=\(cid)/" : "https://video.dmm.co.jp/av/content/?id=\(cid)"
   var c=URLComponents(string:"https://al.fanza.co.jp/")!
   c.queryItems=[URLQueryItem(name:"lurl",value:target)]
   return c.url!.absoluteString
  }
  func record(_ ids:[(String,T.Storefront)]) -> String {
   "<div class='um_image_a um_popup'><a title='拡大表示' href='images/B084SXDZYQ.jpg'>image</a>" + ids.map { "<a href='\(link($0.0,$0.1))'>DMM</a>" }.joined() + "</div>"
  }
  let href=link("118abf295",.retail)
  assert(T.linkedCID(href)?.storefront == .retail)
  assert(T.linkedCID(link("ssis00497",.digital))?.storefront == .digital)
  let retail=try T.match(html:record([("118abf295",.retail),("abf00295",.digital)]),number:"ABF-295")
  assert(retail?.images.count == 1 && retail?.official.count == 2)
  assert(retail?.official.contains("https://awsimgsrc.dmm.co.jp/pics_dig/mono/movie/118abf295/118abf295ps.jpg") == true)
  assert(retail?.official.contains("https://pics.dmm.co.jp/mono/movie/adult/118abf295/118abf295ps.jpg") == true)
  let conflict=try T.images(html:record([("13dsvr01968",.digital),("dsvr01968",.digital)]),number:"13DSVR-1968")
  assert(conflict.isEmpty)
  let suffix=try T.images(html:record([("118abf295",.retail),("118abf295so",.retail)]),number:"ABF-295")
  assert(suffix.isEmpty)
  let unbound=try T.images(html:record([("118abf295",.retail)])+record([("ssis00497",.digital)]),number:"SSIS-497")
  assert(unbound.count == 1)
  let standard="https://pics.dmm.co.jp/mono/movie/adult/118abf295/118abf295ps.jpg"
  let high="https://awsimgsrc.dmm.co.jp/pics_dig/mono/movie/118abf295/118abf295ps.jpg"
  assert(DMMPoster.candidates(metadata:standard,number:"ABF-295") == [high,standard])
  let japanese=standard.replacingOccurrences(of:"/adult/",with:"/japanese/")
  assert(DMMPoster.candidates(metadata:japanese,number:"ABF-295") == [high,japanese])
  assert(DMMPoster.candidates(metadata:standard+"?w=200&h=300#preview",number:"ABF-295") == [high,standard])
  assert(DMMPoster.candidates(metadata:standard.replacingOccurrences(of:"ps.jpg",with:"pl.jpg"),number:"ABF-295") == [high,standard])
  assert(DetailPosterPolicy.allowedPublicImage(URL(string:high)!))
  assert(DetailPosterPolicy.allowedPublicImage(URL(string:standard)!))
  for bad in [standard+"?token=x",standard+"?w=bad",standard+"?w=200&w=300",standard.replacingOccurrences(of:"ps.jpg",with:"jp-1.jpg"),standard.replacingOccurrences(of:"/adult/",with:"/unknown/"),standard.replacingOccurrences(of:"/adult/",with:"/adult/japanese/"),standard.replacingOccurrences(of:"dmm.co.jp",with:"dmm.co.jp.evil.test"),standard.replacingOccurrences(of:"118abf295ps",with:"118abf296ps"),high.replacingOccurrences(of:"/movie/",with:"/movie/adult/"),"https://pics.dmm.co.jp/digital/amateur/118abf295/118abf295ps.jpg","https://m.media-amazon.com/images/I/118abf295ps.jpg?w=200"] {
   assert(DMMPoster.candidates(metadata:bad,number:"ABF-295").isEmpty,bad)
  }
  assert(DMMPoster.candidates(metadata:standard,number:"ABF-296").isEmpty)
  assert(!DMMPoster.allowedImage(URL(string:standard+"?w=200")!))
  assert(!DMMPoster.allowedImage(URL(string:standard.replacingOccurrences(of:"ps.jpg",with:"pl.jpg"))!))
  // Failed AWS request never prevents standard; neither CDN receives a score bonus.
  let fallback:[DetailPosterQuality] = await DetailPosterSelection.collect(sources:[high,standard],budget:0.2) { source,_ in
   source == high ? nil : DetailPosterQuality(source:source,width:700,height:1000,originalPortrait:true)
  }
  assert(DetailPosterQuality.winner(fallback)?.source == standard)
  for winner in [high,standard] {
   let results:[DetailPosterQuality] = await DetailPosterSelection.collect(sources:[high,standard],budget:0.2) { source,_ in
    let h=source == winner ? 1500 : 1000
    return DetailPosterQuality(source:source,width:h*7/10,height:h,originalPortrait:true)
   }
   assert(DetailPosterQuality.winner(results)?.source == winner)
  }
  let fair:[String] = await DetailPosterSelection.collect(sources:["javdb","mgs","old3","old4","old5","old6"],budget:0.3,discover:{ _ in
   try? await Task.sleep(nanoseconds:40_000_000)
   return ["tenhow","amazon",high,standard]
  }) { source,_ in source }
  assert(Set(fair) == Set(["javdb","mgs","tenhow","amazon",high,standard]))
  print("PASS production Swift DMM storefront/CID, record binding, strict URL normalization, AWS fallback, actual-dimension score preference and fair six-slot discovery")
 }
}
'''
if not shutil.which('swiftc'):
    print('PASS DMM static integration; actual Swift assertions require macOS CI')
else:
    with tempfile.TemporaryDirectory() as td:
        p=Path(td); (p/'main.swift').write_text(core+'\n'+swift)
        subprocess.run(['swiftc','-parse-as-library',str(p/'main.swift'),'-o',str(p/'test')],check=True)
        subprocess.run([str(p/'test')],check=True,timeout=30)
