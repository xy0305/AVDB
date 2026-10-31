import json, sys, re, statistics as S
def clean(t): return re.sub(r'[。、！？!?….・♪〜~ 　「」『』，]','',t or '')
def dice(a,b):
    a,b=clean(a),clean(b)
    g=lambda s: [s[i:i+2] for i in range(len(s)-1)] or ([s] if s else [])
    x,y=g(a),g(b)
    if not x and not y: return 1.0
    from collections import Counter
    cx,cy=Counter(x),Counter(y); inter=sum((cx&cy).values()); return 2*inter/(len(x)+len(y))
def union_cov(ranges,s,e):
    tot=0
    for a,b in ranges:
        lo,hi=max(a,s),min(b,e)
        if hi>lo: tot+=hi-lo
    return min(1,tot/max(0.01,e-s))
def ov(a0,a1,b0,b1): return max(0,min(a1,b1)-max(a0,b0))
def analyse(sim, ref, limit):
    segs=sim['segments']; disp=sim['display']; fed=sim['fed']; utt=sim['utterances']; asr=[a for a in sim['asr'] if a['final']]
    npipe=max([s['pipe'] for s in segs]+[0])
    final_pipe=npipe
    by_text={}
    for s in segs: by_text.setdefault(s['ja'],[]).append(s)
    shown=[]  # (segment, display start,end)
    for d in disp:
        for s in by_text.get(d['ja'],[]): shown.append((s,d['start'],d['end']))
    stages={'covered':0,'reader_gap':0,'vad_rejected':0,'queue_dropped':0,'recognized_empty_or_filtered':0,'lost_on_restart_or_merged':0,'not_displayed_late':0}
    onset=[]; endlag=[]; sims=[]; examples=[]
    refs=[r for r in ref if r['speech'] and r['end']<=limit]
    for r in refs:
        s0,e0=r['start'],r['end']
        def hits(seg): o=ov(seg['start'],seg['end'],s0,e0); return o>=min(0.3*(e0-s0),0.2) or o>=0.5*(seg['end']-seg['start'])
        disp_hits=[(sg,a,b) for sg,a,b in shown if hits(sg) and b>s0-0.5 and a<e0+8]
        if disp_hits:
            stages['covered']+=1
            first=min(a for _,a,_ in disp_hits); onset.append(first-s0); endlag.append(first-e0)
            txt=''.join(dict.fromkeys(sg['ja'] for sg,_,_ in sorted(disp_hits,key=lambda x:x[0]['start'])))
            sims.append(dice(txt,r['ja'])); examples.append((s0,e0,r['ja'],txt,round(first-s0,2)))
            continue
        if union_cov(fed,s0,e0)<0.5: stages['reader_gap']+=1; examples.append((s0,e0,r['ja'],'<reader gap>',None)); continue
        if not any(ov(u['start'],u['end'],s0,e0)>0.05 for u in utt): stages['vad_rejected']+=1; examples.append((s0,e0,r['ja'],'<VAD>',None)); continue
        calls=[a for a in asr if ov(a['start'],a['end'],s0,e0)>0.05]
        if not calls: stages['queue_dropped']+=1; examples.append((s0,e0,r['ja'],'<queue dropped>',None)); continue
        if all(not clean(re.sub(r'<\|[^|]*\|>','',c['raw'])) for c in calls): stages['recognized_empty_or_filtered']+=1; examples.append((s0,e0,r['ja'],'<empty>',None)); continue
        live=[s for s in segs if s['pipe']==final_pipe and hits(s)]
        if not live: stages['lost_on_restart_or_merged']+=1; examples.append((s0,e0,r['ja'],'<lost>',None)); continue
        stages['not_displayed_late']+=1; examples.append((s0,e0,r['ja'],'<not shown: '+live[0]['ja']+'>',None))
    n=len(refs)
    q=lambda xs,p: sorted(xs)[min(len(xs)-1,int(p*len(xs)))] if xs else None
    return {'refs':n,'coverage':stages['covered']/max(1,n),'stages':stages,
            'onset_median':S.median(onset) if onset else None,'onset_p90':q(onset,0.9),
            'after_end_median':S.median(endlag) if endlag else None,'text_sim':S.mean(sims) if sims else None,
            'restarts':sim['restarts'],'catchUps':sim.get('catchUps'),'events':sim['events'][:12],'stageLine':sim.get('stageLine'),'examples':examples}
if __name__=='__main__':
    sim=json.load(open(sys.argv[1])); ref=json.load(open(sys.argv[2])); lim=float(sys.argv[3]) if len(sys.argv)>3 else 1e9
    r=analyse(sim,ref,lim); ex=r.pop('examples')
    print(json.dumps(r,ensure_ascii=False,indent=1))
    if '-v' in sys.argv:
        for e in ex: print(e)
