import json, re, sys, statistics as S, difflib, random
from collections import Counter
TITLES = [('ipzz','IPZZ-961'),('jur857','JUR-857'),('adn801','ADN-801'),('hmn898','HMN-898'),('ipzz912','IPZZ-912'),('cawd989','CAWD-989')]
E = '/workspace/eval291/'
def load_ref(s):
    p = E + ('ipzz961_ref.json' if s == 'ipzz' else f'{s}_ref_cn.json')
    ref = [c for c in json.load(open(p)) if not re.search(r'WWW|资源|出品|主演|导演|字幕|翻译|校对', c['text'])]; m = []
    for c in ref:
        if m and c['start']-m[-1]['end'] <= 1.0 and difflib.SequenceMatcher(None, m[-1]['text'], c['text']).ratio() > 0.5:
            m[-1]['end'] = c['end']; continue
        m.append(dict(c))
    return m
def cl(s): return re.sub(r'[\s，。、！？!?….·・♪〜~「」『』（）(),.\'"0-9a-zA-Z\-{}]', '', s or '')
def f1(a, b):
    a, b = Counter(cl(a)), Counter(cl(b))
    if not a or not b: return 0.0
    i = sum((a & b).values())
    if i == 0: return 0.0
    p = i/sum(a.values()); r = i/sum(b.values()); return 2*p*r/(p+r)
REP = re.compile(r'(.{1,4})(?:[，,、 ]?\1){2,}')
EXPL_JA = re.compile(r'ちんぽ|ちんちん|チンポ|まんこ|マンコ|おっぱい|乳首|舐め|なめ|イク|イッ|いく[!！う]?$|気持ちい|出して|中出し|精子|ザーメン|セックス|エッチ|フェラ|挿れ|入れて|奥|濡れ|クリ|しゃぶ|射精|オナ|勃|犯')
REFUSE = re.compile(r'抱歉|无法|不能提供|不适合|不当|对不起，我|I can|I\'m sorry|作为一个|AI|敏感|色情内容')
def systems(s):
    nl = json.load(open('nllb_cache.json')); prep = json.load(open(f'{s}_prep.json'))
    out = {'291 NLLB': lambda ja: nl.get(ja, ''), '292 NLLB+fixes': lambda ja: prep.get(ja, {}).get('zh', '')}
    for m, lab in [('sakura', 'Sakura-1.5B'), ('hymt', 'HY-MT1.5-1.8B'), ('abl', 'HY-MT-abliterated')]:
        try:
            d = json.load(open(f'{s}_{m}_post.json')); out[lab] = (lambda d: lambda ja: d.get(ja, ''))(d)
        except FileNotFoundError: pass
    return out
def run(s, fn):
    ref = load_ref(s); disp = json.load(open(E + f'{s}_291_clean.json'))['display']
    bests = []; pairs = []
    for c in ref:
        hit = [d for d in disp if d['end'] > c['start']-1.0 and d['start'] < c['end']+1.5]
        if not hit: continue
        sc = [(f1(fn(d['ja']), c['text']), d) for d in hit]; b, bd = max(sc, key=lambda x: x[0]); bests.append(b)
        pairs.append((c['start'], bd['ja'], c['text']))
    zs = [fn(d['ja']) for d in disp]; nz = [z for z in zs if z]
    random.seed(1)
    return {'cues': len(ref), 'matched_f1>=0.3': round(sum(b >= 0.3 for b in bests)/len(ref), 3),
            'zh_f1_mean': round(S.mean(bests), 3), 'lines': len(disp), 'shown_zh': len(nz),
            'xianzai_rate': round(sum(z.startswith('现在') for z in nz)/max(1, len(nz)), 3),
            'xianzai_zhidao': sum('现在' in z and '我知道' in z for z in nz),
            'repetition': sum(bool(REP.search(cl(z))) for z in nz)}, pairs
if __name__ == '__main__':
    res = {}; allpairs = {}
    for s, lab in TITLES:
        for name, fn in systems(s).items():
            r, pairs = run(s, fn); res.setdefault(lab, {})[name] = r; allpairs[s] = pairs
    json.dump(res, open('eval292_results.json', 'w'), ensure_ascii=False, indent=1)
    for t, v in res.items():
        for n, r in v.items(): print(f"{t:9s} {n:18s} match {r['matched_f1>=0.3']*100:5.1f}%  F1 {r['zh_f1_mean']:.3f}  现在 {r['xianzai_rate']*100:4.1f}%  现在我知道 {r['xianzai_zhidao']:2d}  rep {r['repetition']}  shown {r['shown_zh']}/{r['lines']}")
    json.dump(allpairs, open('pairs.json', 'w'), ensure_ascii=False)
