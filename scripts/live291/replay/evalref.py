import json, sys, re, statistics as S, difflib
ref=[c for c in json.load(open('ipzz961_ref.json')) if 'WWW' not in c['text'] and '资源' not in c['text']]
# merge OCR fragments of the same cue (<=1 s apart, similar)
m=[]
for c in ref:
    if m and c['start']-m[-1]['end']<=1.0 and difflib.SequenceMatcher(None,m[-1]['text'],c['text']).ratio()>0.5:
        m[-1]['end']=c['end']; continue
    m.append(dict(c))
ref=m
zh=json.load(open('ipzz_zh_cache.json'))
def cl(s): return re.sub(r'[\s，。、！？!?….·・♪〜~「」『』,.\'"0-9]','',s or '')
def f1(a,b):
    from collections import Counter
    a,b=Counter(cl(a)),Counter(cl(b))
    if not a or not b: return 0.0
    i=sum((a&b).values()); p=i/sum(a.values()); r=i/sum(b.values()); return 0 if i==0 else 2*p*r/(p+r)
def run(fn):
    sim=json.load(open(fn)); disp=sim['display']; segs=sim['segments']
    seg_by={s['ja']:s for s in segs}
    cov=0; offs=[]; lat=[]; sims=[]; rows=[]; bests=[]
    for c in ref:
        hit=[d for d in disp if d['end']>c['start']-1.0 and d['start']<c['end']+1.5]
        if not hit: rows.append((c['start'],c['text'],None,None,None)); continue
        cov+=1
        first=min(hit,key=lambda d:d['start'])
        s=seg_by.get(first['ja'])
        if s: offs.append(s['start']-c['start'])
        lat.append(first['start']-c['start'])
        ours=' '.join(dict.fromkeys(zh.get(d['ja'],'') for d in hit))
        sc=f1(ours,c['text']); sims.append(sc)
        best=max(f1(zh.get(d['ja'],''),c['text']) for d in hit); bests.append(best)
        rows.append((c['start'],c['text'],' / '.join(dict.fromkeys(d['ja'] for d in hit)),ours,round(first['start']-c['start'],2)))
    # chance baseline: our lines vs random other cues
    import random; random.seed(1); base=[]
    allz=[zh.get(d['ja'],'') for d in disp]
    for c in ref:
        if allz: base.append(f1(random.choice(allz),c['text']))
    return {'cues':len(ref),'coverage':cov/len(ref),'timing_offset_median':S.median(offs) if offs else None,
            'display_minus_cue_start_median':S.median(lat) if lat else None,'display_p90':sorted(lat)[int(0.9*(len(lat)-1))] if lat else None,
            'zh_char_f1_mean':S.mean(sims) if sims else None,'zh_char_f1_random_baseline':S.mean(base) if base else None,'restarts':sim['restarts'],'matched_coverage_f1>=0.3':sum(b>=0.3 for b in bests)/len(ref),'lines_displayed':len(disp)}, rows
for fn in sys.argv[1:]:
    r,rows=run(fn); print(fn, json.dumps(r,ensure_ascii=False))
    if '-v' in fn or True:
        pass
if len(sys.argv)>1:
    _,rows=run(sys.argv[-1])
    for x in rows: print(x)
