import glob, json, difflib
from rapidocr_onnxruntime import RapidOCR
o=RapidOCR(); FPS=4.0
fs=sorted(glob.glob('ipzz_fr/*.jpg')); rows=[]
for i,f in enumerate(fs):
    r,_=o(f); t=''.join(x[1] for x in (r or []) if float(x[2])>0.6 and len(x[1])>=1)
    rows.append((i/FPS, t.strip()))
cues=[]
for t,txt in rows:
    if txt and cues and cues[-1]['open'] and difflib.SequenceMatcher(None,cues[-1]['text'],txt).ratio()>0.6:
        cues[-1]['end']=t+1/FPS
        if len(txt)>len(cues[-1]['text']): cues[-1]['text']=txt
        continue
    if cues: cues[-1]['open']=False
    if txt: cues.append({'start':t,'end':t+1/FPS,'text':txt,'open':True})
    
cues=[{k:v for k,v in c.items() if k!='open'} for c in cues if c['end']-c['start']>=0.5 and 'JUR' not in c['text'] and 'IPZZ' not in c['text']]
json.dump(cues,open('ipzz961_ref.json','w'),ensure_ascii=False,indent=1); print(len(cues))
