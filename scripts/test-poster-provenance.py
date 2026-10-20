"""Build221: native production selection/cache/presentation + displayed-source contracts."""
from pathlib import Path
import shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
read=lambda p:(root/p).read_text()
resolver=read('AVDB/Services/DetailPosterResolver.swift')
view=read('AVDB/Views/Detail/MovieDetailView.swift')
image=read('AVDB/Services/ImageLoader.swift')
assert 'let provenance: PosterProvenance' in resolver
assert 'artwork(image: selected.image, source: winner.source, derive: false)' in resolver
assert 'provenance: PosterProvenance(source: source)' in resolver
assert 'DetailPosterCache<DetailPosterArtwork>()' in resolver
assert 'cache.snapshot(key: identity(movie: movie, account: account))' in resolver
assert 'Text(art.provenance.text)' in view
assert '.overlay(alignment: .topLeading)' in view
assert '.padding(.leading, 18).padding(.top, 140)' in view
assert 'Source label must clear the navigation buttons' in read('UITests/PosterNavigationTests.swift')
assert 'presentation.key == posterRequestKey' in view
assert 'presentation.complete(art, key: key, generation: generation)' in view
assert 'guard !Task.isCancelled, posterRequestKey == key' in view
assert 'imageIdentity == requestIdentity, let imageProvenance' in image
assert 'guard !Task.isCancelled, identity == requestIdentity else { return }' in image
assert 'imageProvenance = PosterProvenance(source: source)' in image
assert 'publish(img, identity: identity, source: candidate)' in image
assert 'landscapeFallback = landscapeFallback ?? (img, candidate)' in image
assert 'publish(landscapeFallback.image, identity: identity, source: landscapeFallback.source)' in image
assert 'showsSourceLabel: true' in view and 'showsSourceLabel: Bool = false' in image
assert 'Text(art.label)' in view and view.count('tpdb-artwork-source') == 1
assert '封面来源：ThePornDB' in read('AVDB/Services/TPDBArtworkService.swift')
core='\n'.join(read('AVDB/Services/'+p) for p in ['JavRankingCore.swift','TenhowPoster.swift','TenhowActorLinks.swift','DetailPosterPolicy.swift','DetailPosterCache.swift'])
swift=r'''
actor SourceCompletion {
 var values:[String]=[]
 func add(_ source:String) { values.append(source) }
 func last() -> String? { values.last }
}
@main struct SourceRegression {
 static func main() async {
  let amazon="https://m.media-amazon.com/images/I/exact.jpg"
  let dmm="https://pics.dmm.co.jp/digital/video/exact/exactps.jpg"
  let javdb="https://tp.spfcas.com/private/covers/exact.jpg?token=do-not-display"
  let pairs=[(amazon,"Amazon"),(dmm,"DMM"),(javdb,"JavDB"),
   ("https://awsimgsrc.dmm.co.jp/pics_dig/exact.jpg","DMM"),
   ("https://www.tenhow.net/images/B000000001.jpg","Tenhow"),
   ("https://c0.jdbstatic.com/covers/exact.jpg","JavDB"),
   ("https://www.javbus.com/pics/cover/exact_b.jpg","JavBus"),
   ("https://image.mgstage.com/images/exact.jpg","MGS")]
  for (url,label) in pairs { assert(PosterProvenance(source:url).label == label) }
  for url in ["", "fixture://neutral", "file:///private/secret.jpg", "https://tp.spfcas.com.evil.test/private.jpg", "https://external.test/image?token=private"] {
   let p=PosterProvenance(source:url)
   assert(p.label == "原始封面/未知来源")
   assert(!p.text.contains("private") && !p.text.contains("token"))
  }
  // Actual production scheduler, decoded-quality winner and warm result cache.
  // The last completed result deliberately loses: do not label the last probe.
  let completion=SourceCompletion()
  let values:[DetailPosterQuality]=await DetailPosterSelection.collect(sources:[amazon,dmm]) { source,_ in
   do { try await Task.sleep(nanoseconds:source == amazon ? 5_000_000 : 50_000_000) } catch { return nil }
   await completion.add(source)
   return DetailPosterQuality(source:source,width:source == amazon ? 1050:700,height:source == amazon ? 1500:1000,originalPortrait:true)
  }
  let last=await completion.last();assert(last == dmm)
  let winner=DetailPosterQuality.winner(values)!
  assert(winner.source == amazon)
  let provenance=PosterProvenance(source:winner.source)
  let cache=DetailPosterCache<PosterProvenance>()
  let cached=await cache.value(key:"film-A/account-A") { provenance }
  assert(cached == provenance && cached?.label == "Amazon")
  assert(cache.snapshot(key:"film-A/account-A").artwork == provenance)
  let warm=await cache.value(key:"film-A/account-A") { fatalError("warm source made another request") }
  assert(warm == provenance)
  assert(cache.snapshot(key:"film-B/account-A").artwork == nil)
  assert(cache.snapshot(key:"film-A/account-B").artwork == nil)
  let generation=UUID()
  var shown=DetailPosterPresentation<PosterProvenance>(key:"film-B",generation:generation,layout:.resolving)
  shown.complete(provenance,key:"film-A",generation:generation)
  assert(shown.layout.artwork == nil)
  shown.complete(provenance,key:"film-B",generation:UUID())
  assert(shown.layout.artwork == nil)
  let fallback=PosterProvenance(source:javdb)
  shown.complete(fallback,key:"film-B",generation:generation)
  assert(shown.layout.artwork?.label == "JavDB")
  shown.complete(provenance,key:"film-B",generation:generation)
  assert(shown.layout.artwork?.label == "JavDB") // no late source overwrite
  let cancelled=Task { await cache.value(key:"cancelled-film") {
   do { try await Task.sleep(nanoseconds:5_000_000_000); return provenance } catch { return nil }
  } }
  while cache.fixtureLeaseCount(key:"cancelled-film") != 1 { await Task.yield() }
  cancelled.cancel()
  let result=await cancelled.value;assert(result == nil)
  assert(cache.snapshot(key:"cancelled-film").artwork == nil)
  assert(!cache.snapshot(key:"cancelled-film").isLandscape)
  print("PASS build221 native production winner-not-last-result, source cache roundtrip/snapshot, honest fallback, cancelled lease and movie/account/generation isolation")
 }
}
'''
if shutil.which('swiftc'):
 with tempfile.TemporaryDirectory() as td:
  p=Path(td);(p/'main.swift').write_text(core+'\n'+swift)
  subprocess.run(['swiftc','-D','DEBUG','-swift-version','5','-parse-as-library',str(p/'main.swift'),'-o',str(p/'test')],check=True)
  subprocess.run([str(p/'test')],check=True,timeout=20)
else:
 print('PASS build221 View/resolver/fallback source contracts; SKIP native execution: requires macOS Swift CI')
