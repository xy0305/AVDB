from pathlib import Path
import os, subprocess, tempfile, platform
R=Path(__file__).resolve().parents[1]
assert platform.system()=='Darwin'
with tempfile.TemporaryDirectory() as d:
 p=Path(d); html=p/'live.html'
 # No redirects, cookies or page output. Match the production User-Agent exactly.
 ua=(R/'AVDB/Services/OnlinePlaybackCore.swift').read_text().split('static let ua = "',1)[1].split('"',1)[0]
 code=subprocess.check_output(['curl','--silent','--show-error','--max-time','45','--max-filesize','2097152','--proto','=https','--output',str(html),'--write-out','%{http_code}','-H','User-Agent: '+ua,'-H','Referer: https://tangxinvlog.app/','https://tangxinvlog.app/featured/'],text=True)
 print('LIVE262 HTTP='+code,flush=True)
 assert code=='200'
 s=(R/'AVDB/Services/CatalogueMetadata.swift').read_text()
 identity=p/'Identity.swift'; identity.write_text('import Foundation\nenum CatalogueIdentity {'+s.split('enum CatalogueIdentity {',1)[1].split('\nstruct ScrapedMetadata:',1)[0])
 files=['PlaybackDiagnostic','JavRankingCore','MissAVCore','OnlinePlaybackCore','OnlineAdditionalProviders','DetailOnlineAdapters']
 base=[str(R/('AVDB/Services/'+f+'.swift')) for f in files]
 main=p/'Probe.swift';main.write_text('''import Foundation
@main struct Probe {
 static func main() throws {
  let html = try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8)
  let root = TangxinPolicy.featured
  let page = try TangxinParser.list(html,at:root)
  print("BASELINE261 displayed=\\(page.videos.count) next=\\(page.next != nil) rootAllowed=\\(TangxinPolicy.page(root))")
 }
}
''')
 core=p/'TangxinCore.swift';core.write_bytes(subprocess.check_output(['git','show','616b0e8:AVDB/Services/TangxinCore.swift'],cwd=R))
 binary=p/'baseline'
 subprocess.run(['swiftc','-parse-as-library','-swift-version','5',str(identity),*base,str(core),str(main),'-o',str(binary)],check=True)
 subprocess.run([str(binary),str(html)],check=True)
 env=dict(os.environ,TANGXIN_LIVE_HTML=str(html))
 subprocess.run(['python3','scripts/test-tangxin261.py'],cwd=R,env=env,check=True)

 # Compare curl's HTTP result with actual production Darwin DNS / URLSession.
 # Only diagnostics and counts; no HTML/title/media/query data in output/artifacts.
 network=p/'Network263.swift'
 network.write_text('import Foundation\n@main struct Network263 {\n static func main() async {\n  let root = TangxinPolicy.featured\n  do {\n   try await OnlineMediaScope(root:root).validateDNS(mode:.strict,approvedOrigin:true)\n   print("PRODUCTION263 host=tangxinvlog.app stage=DNS strict=accepted (runner only)")\n   let page = try await TangxinClient().list(root)\n   print("PRODUCTION263 host=tangxinvlog.app stage=query HTTP=200 state=\\(page.state.rawValue) displayed=\\(page.videos.count) runnerOnly=true")\n  } catch {\n   print("PRODUCTION263 runnerOnly=true " + OnlineFailure.captured(error,at:.discovery).presentation(at:.discovery).display)\n  }\n }\n}\n')
 netbin=p/'network263'
 subprocess.run(['swiftc','-parse-as-library','-swift-version','5',str(identity),*base,str(R/'AVDB/Services/TangxinCore.swift'),str(network),'-o',str(netbin)],check=True)
 subprocess.run([str(netbin)],check=True,timeout=90)
