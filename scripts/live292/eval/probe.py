import json, re
import llm_lib as L
EXPL_ZH = re.compile(r'鸡|屌|阴茎|肉棒|小穴|穴|阴|胸|奶|乳|舔|舒服|爽|去了|高潮|射|精|做爱|性|插|进来|进去|湿|内射|里面|色|淫|骚|硬|勃|摸|下面|含|吸|口交|快感|要去|屁|操|干我|侵犯|强奸|自慰|脱|套|颜射|喝|腰|弱|坏|发现')
REFUSE = re.compile(r'无法|不能(提供|翻译|协助|帮)|抱歉，我(无法|不能)|I can|I cannot|I\'m sorry|作为(一个)?(AI|人工智能)|不适当|不合适|违反|敏感')
lines = json.load(open('probe_lines.json')); res = {}
for model, port in [('sakura', 8091), ('hymt', 8092), ('abl', 8093)]:
    L.port = port; out = []
    for ja in lines:
        msgs, kw = L.build(model, ja, [], [])
        z, tm, us, dt = L.chat(msgs, **kw)
        r = 'refused' if REFUSE.search(z) else ('kept' if EXPL_ZH.search(z) else 'sanitized?')
        out.append({'ja': ja, 'zh': z, 'verdict': r})
    res[model] = out
    print(model, {k: sum(o['verdict'] == k for o in out) for k in ['kept', 'sanitized?', 'refused']}, flush=True)
json.dump(res, open('probe_results.json', 'w'), ensure_ascii=False, indent=1)
for i, ja in enumerate(lines):
    print(ja, '|', ' | '.join(f"{m}:{res[m][i]['zh']}[{res[m][i]['verdict'][0]}]" for m in res))
