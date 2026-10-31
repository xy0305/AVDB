import json, sys, re, statistics as S, difflib, random
from collections import Counter
def load_ref(p):
    ref=[c for c in json.load(open(p)) if not re.search(r'WWW|资源|出品|主演|导演|字幕|翻译|校对',c['text'])]; m=[]
    for c in ref:
        if m and c['start']-m[-1]['end']<=1.0 and difflib.SequenceMatcher(None,m[-1]['text'],c['text']).ratio()>0.5:
            m[-1]['end']=c['end']; continue
        m.append(dict(c))
    return m
zh=json.load(open('ipzz_zh_cache.json'))
def cl(s): return re.sub(r'[\s，。、！？!?….·・♪〜~「」『』（）(),.\'"0-9a-zA-Z-]','',s or '')
def f1(a,b):
    a,b=Counter(cl(a)),Counter(cl(b))
    if not a or not b: return 0.0
    i=sum((a&b).values()); 
    if i==0: return 0.0
    p=i/sum(a.values()); r=i/sum(b.values()); return 2*p*r/(p+r)
def run(fn, ref):
    sim=json.load(open(fn)); disp=sim['display']; seg_by={s['ja']:s for s in sim['segments']}
    cov=0; lat=[]; bests=[]; pairs=[]
    for c in ref:
        hit=[d for d in disp if d['end']>c['start']-1.0 and d['start']<c['end']+1.5]
        if not hit: continue
        cov+=1
        lat.append(min(d['start'] for d in hit)-c['start'])
        sc=[(f1(zh.get(d['ja'],''),c['text']),d) for d in hit]; b,bd=max(sc,key=lambda x:x[0]); bests.append(b)
        if len(cl(bd['ja']))>=4: pairs.append((b,c['start'],bd['ja'],zh.get(bd['ja'],''),c['text']))
    random.seed(1); allz=[zh.get(d['ja'],'') for d in disp]
    base=S.mean(f1(random.choice(allz),c['text']) for c in ref) if allz else 0
    n=len(ref)
    return {'cues':n,'coverage':round(cov/n,3),'matched_f1>=0.3':round(sum(b>=0.3 for b in bests)/n,3),
            'zh_f1_mean':round(S.mean(bests),3) if bests else None,'random_baseline':round(base,3),
            'onset_median_s':round(S.median(lat),2) if lat else None,
            'onset_p90_s':round(sorted(lat)[int(0.9*(len(lat)-1))],2) if lat else None,
            'restarts':sim['restarts'],'lines_displayed':len(disp)}, pairs
if __name__=='__main__':
    titles=[('jur857','JUR-857'),('adn801','ADN-801'),('hmn898','HMN-898'),('ipzz912','IPZZ-912'),('cawd989','CAWD-989')]
    res={}; ex={}
    for s,l in titles:
        ref=load_ref(f'{s}_ref_cn.json')
        for v in ['290','291']:
            for sc in ['device','clean']:
                r,pairs=run(f'{s}_{v}_{sc}.json',ref); res[f'{l} {v} {sc}']=r
                if v=='291' and sc=='clean':
                    # unnatural: matched in time & substantive ja, but low char-F1 vs reference
                    low=sorted([p for p in pairs if p[0]<0.25],key=lambda p:p[0])
                    pick=[p for p in low if len(cl(p[4]))>=4][:5]
                    ex[l]=[{'t':round(p[1],1),'ja':p[2],'ours_zh':p[3],'ref_zh':p[4],'f1':round(p[0],2)} for p in pick]
    json.dump({'results':res,'unnatural_examples':ex},open('batch5_results.json','w'),ensure_ascii=False,indent=1)
    for k,v in res.items(): print(k,v)
