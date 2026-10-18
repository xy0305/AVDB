"""Controlled phase timings of production scheduler/cache, not live network benchmarks."""
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
view=(root/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
for s in ['private var posterMovie: Movie? { DetailPosterResolver.posterMovie(seed: posterSeed, detail: vm.movie) }','guard let movie = posterMovie else { return }','model.movie = trusted','init(movie: Movie)','await vm.load()']:
    assert s in view,s
# Poster and full metadata are independent SwiftUI tasks; no await vm.load in poster task.
poster=view.split('.task(id: posterRequestKey)',1)[1].split('.safeAreaInset',1)[0]
assert 'await vm.load()' not in poster
for f in ['AVDB/Views/Components/JAVDBUI.swift','AVDB/Views/Components/MovieGridView.swift','AVDB/Views/Home/HomeView.swift']:
    assert 'MovieDetailView(movie: movie)' in (root/f).read_text()
core='\n'.join((root/'AVDB/Services'/f).read_text() for f in ['JavRankingCore.swift','TenhowPoster.swift','TenhowActorLinks.swift','DetailPosterPolicy.swift','DetailPosterCache.swift'])
swift=r'''
actor PhaseProbe {
 var started=[String:Double](); var finished=[String:Double](); var calls=0
 func start(_ key:String) { started[key]=ProcessInfo.processInfo.systemUptime; calls += 1 }
 func end(_ key:String) { finished[key]=ProcessInfo.processInfo.systemUptime }
 func times() -> ([String:Double],[String:Double],Int) { (started,finished,calls) }
}
@main struct LatencyRegression {
 static func main() async {
  let p=PhaseProbe(); let start=ProcessInfo.processInfo.systemUptime
  let result:[DetailPosterQuality] = await DetailPosterSelection.collect(sources:["legacy","other"],budget:1,discover:{ _ in
   await p.start("discovery")
   try? await Task.sleep(nanoseconds:120_000_000)
   await p.end("discovery"); return ["tenhow","amazon"]
  }) { source,_ in
   await p.start(source)
   try? await Task.sleep(nanoseconds:source == "legacy" ? 100_000_000 : 10_000_000)
   await p.end(source)
   return DetailPosterQuality(source:source,width:source == "amazon" ? 1050 : 700,height:source == "amazon" ? 1500 : 1000,originalPortrait:true)
  }
  let (began,ended,calls)=await p.times()
  assert(calls == 5 && result.count == 4)
  // Assert causal overlap, not a fragile absolute elapsed-time threshold.
  assert(began["legacy"]! < ended["discovery"]!)
  assert(ended["legacy"]! < began["amazon"]!)
  assert(DetailPosterQuality.winner(result)?.source == "amazon")
  let duration=ProcessInfo.processInfo.systemUptime-start
  assert(duration < 0.8) // all legal candidates completed: don't wait for 1s deadline
  let cache=DetailPosterCache<Int>()
  let cold=await cache.value(key:"same") { 7 }; assert(cold == 7)
  let warmStart=ProcessInfo.processInfo.systemUptime
  assert(cache.snapshot(key:"same").artwork == 7) // synchronous, no await or network
  let warm=await cache.value(key:"same") { fatalError("warm cache performed work") }
  assert(warm == 7)
  print(String(format:"PASS controlled production phase timing: discovery %.1fms, legacy %.1fms, total %.1fms; synchronous warm snapshot + cache value %.3fms; overlap, late Amazon winner, early completion", (ended["discovery"]!-began["discovery"]!)*1000,(ended["legacy"]!-began["legacy"]!)*1000,duration*1000,(ProcessInfo.processInfo.systemUptime-warmStart)*1000))
 }
}
'''
if not shutil.which('swiftc'):
    print('PASS navigation/metadata independence static checks; phase timing requires macOS Swift CI')
else:
    with tempfile.TemporaryDirectory() as td:
        p=Path(td); (p/'main.swift').write_text(core+'\n'+swift)
        subprocess.run(['swiftc','-parse-as-library',str(p/'main.swift'),'-o',str(p/'test')],check=True)
        subprocess.run([str(p/'test')],check=True,timeout=15)
