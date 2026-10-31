import json, re, statistics as S
from eval292 import EXPL_JA, REFUSE, TITLES
EXPL_ZH = re.compile(r'鸡|屌|阴茎|肉棒|棒|小穴|穴|阴|胸|奶|乳|舔|舒服|爽|去了|高潮|射|精|做爱|性|插|进来|进去|湿|内射|里面|色|淫|骚|硬|勃|摸|下面|含|吸|口交|快感|要去|身体')
def est(prompt_n, gen, pp, tg): return prompt_n / pp + (gen + 1) / tg
# iPhone 13 (A15, 4-core GPU) llama.cpp Metal reference: TinyLlama-1.1B Q4_0 pp512 405 t/s, tg 39 t/s; Q8_0 (1.09 GiB) tg 24 t/s.
SPEED = {'sakura': (405 * 1.10 / 1.54, 24 * 1.09 / 1.17), 'hymt': (405 * 1.10 / 1.79, 24 * 1.09 / 1.05), 'abl': (405 * 1.10 / 1.79, 24 * 1.09 / 1.05)}
out = {}
for m in ['sakura', 'hymt', 'abl']:
    expl = ref = san = 0; ex = []; lat = []; pn = []; gn = []; rows = []
    for s, lab in TITLES:
        try: d = json.load(open(f'{s}_{m}.json'))
        except FileNotFoundError: continue
        for ja, v in d.items():
            if 'predicted_n' not in v: continue
            pn.append(v['prompt_n'] or 0); gn.append(v['predicted_n'] or 0)
            lat.append(est(v['prompt_n'] or 0, v['predicted_n'] or 0, *SPEED[m]))
            z = v['zh']
            if EXPL_JA.search(ja):
                expl += 1
                if REFUSE.search(z): ref += 1; ex.append(('refuse', lab, ja, z))
                elif not EXPL_ZH.search(z): san += 1; ex.append(('sanitized', lab, ja, z))
    if not pn: continue
    lat.sort()
    out[m] = {'llm_lines': len(pn), 'explicit_lines': expl, 'refusals': ref, 'sanitized': san,
              'avg_prompt_tokens_new': round(S.mean(pn), 1), 'avg_gen_tokens': round(S.mean(gn), 1),
              'iphone13_est_pp_tps': round(SPEED[m][0]), 'iphone13_est_tg_tps': round(SPEED[m][1], 1),
              'iphone13_est_s_p50': round(lat[len(lat)//2], 2), 'iphone13_est_s_p95': round(lat[int(len(lat)*0.95)], 2),
              'iphone13_est_s_max': round(lat[-1], 2), 'examples': ex[:40]}
    print(m, {k: v for k, v in out[m].items() if k != 'examples'})
json.dump(out, open('llm_analysis.json', 'w'), ensure_ascii=False, indent=1)
