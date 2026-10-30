from pathlib import Path
import sys,subprocess,hashlib,json,plistlib,zipfile
root=Path(sys.argv[1]);out=Path(sys.argv[2]);e=out/'evidence-release';e.mkdir(exist_ok=True)
for p in root.rglob('*'):
 if p.name in ['embedded.mobileprovision'] or p.suffix=='.xcent':p.unlink()
app=root/'Payload/AVDB.app';pl=plistlib.loads((app/'Info.plist').read_bytes())
assert pl['CFBundleVersion']=='287' and pl['CFBundleShortVersionString']=='1.0.2'
assert pl['MinimumOSVersion']=='17.0'
assert not (app/'_CodeSignature').exists()
# Build 286: the Core ML model is compiled into the bundle (CoverSR.mlmodelc).
mc=app/'CoverSR.mlmodelc'; assert (mc/'coremldata.bin').exists(), 'CoverSR.mlmodelc missing'
modelBytes=sum(f.stat().st_size for f in mc.rglob('*') if f.is_file())
# Build 287: live-subtitle models are bundled (folder reference LiveModels).
lm=app/'LiveModels'; assert lm.is_dir(), 'LiveModels folder missing'
live={}
for name,probe in [('openai_whisper-large-v3-v20240930_turbo_632MB','AudioEncoder.mlmodelc'),('openai_whisper-small_216MB','AudioEncoder.mlmodelc'),
                   ('tokenizer-large-v3','tokenizer.json'),('tokenizer-small','tokenizer.json'),('nllb','NLLBDecoder.mlmodelc')]:
    d=lm/name; assert (d/probe).exists(), f'{name}/{probe} missing'
    live[name]=sum(f.stat().st_size for f in d.rglob('*') if f.is_file())
appBytes=sum(f.stat().st_size for f in app.rglob('*') if f.is_file())
ipa=out/'AVDB-unsigned-1.0.2-287-livesub-lut4-online-from269.ipa'
subprocess.run(['zip','-qry',str(ipa),'Payload'],cwd=root,check=True)
with zipfile.ZipFile(ipa) as z: assert z.testzip() is None
manifest={'file':ipa.name,'bytes':ipa.stat().st_size,'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'zipCRC':'PASS','plist':pl,'sourceCommit':pl['AVDBSourceCommit'],'sourceTree':pl['AVDBSourceTree'],'unsigned':True,'coverSRModelBytes':modelBytes,'liveModelBytes':live,'appBytes':appBytes}
(e/'ipa-manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps(manifest,indent=2))
