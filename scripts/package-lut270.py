from pathlib import Path
import sys,subprocess,hashlib,json,plistlib,zipfile
root=Path(sys.argv[1]);out=Path(sys.argv[2]);e=out/'evidence-release';e.mkdir(exist_ok=True)
for p in root.rglob('*'):
 if p.name in ['embedded.mobileprovision'] or p.suffix=='.xcent':p.unlink()
app=root/'Payload/AVDB.app';pl=plistlib.loads((app/'Info.plist').read_bytes())
assert pl['CFBundleVersion']=='270' and pl['CFBundleShortVersionString']=='1.0.2'
assert pl['MinimumOSVersion']=='17.0'
assert not (app/'_CodeSignature').exists()
ipa=out/'AVDB-unsigned-1.0.2-270-lut4-online-from269.ipa'
subprocess.run(['zip','-qry',str(ipa),'Payload'],cwd=root,check=True)
with zipfile.ZipFile(ipa) as z: assert z.testzip() is None
manifest={'file':ipa.name,'bytes':ipa.stat().st_size,'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'zipCRC':'PASS','plist':pl,'sourceCommit':pl['AVDBSourceCommit'],'sourceTree':pl['AVDBSourceTree'],'unsigned':True}
(e/'ipa-manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps(manifest,indent=2))
