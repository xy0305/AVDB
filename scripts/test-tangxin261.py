from pathlib import Path
import platform,subprocess,tempfile
R=Path(__file__).resolve().parents[1]
assert platform.system()=='Darwin','Production Swift tests require Xcode; Linux checks are not a substitute'
with tempfile.TemporaryDirectory() as d:
 p=Path(d);s=(R/'AVDB/Services/CatalogueMetadata.swift').read_text();i=p/'Identity.swift'
 i.write_text('import Foundation\nenum CatalogueIdentity {'+s.split('enum CatalogueIdentity {',1)[1].split('\nstruct ScrapedMetadata:',1)[0])
 files=['AVDB/Services/PlaybackDiagnostic.swift','AVDB/Services/JavRankingCore.swift','AVDB/Services/MissAVCore.swift','AVDB/Services/OnlinePlaybackCore.swift','AVDB/Services/OnlineAdditionalProviders.swift','AVDB/Services/DetailOnlineAdapters.swift','AVDB/Views/Player/PlaybackVideoMetrics.swift','AVDB/Services/TangxinCore.swift','scripts/TangxinFixtures261.swift','scripts/TangxinNetworkRegression263.swift','scripts/TangxinRegression261.swift']
 binary=p/'tangxin261'
 subprocess.run(['swiftc','-parse-as-library','-swift-version','5',str(i),*[str(R/f) for f in files],'-o',str(binary)],check=True)
 subprocess.run(['sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(binary)],check=True,timeout=120)
