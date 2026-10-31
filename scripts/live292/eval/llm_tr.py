"""LLM A/B: translate each title's 291-clean display lines in order with history (prev 3 lines ≤ 15 s) + glossary.
usage: llm_tr.py <model sakura|hymt|abl> <port> <short>..."""
import json, sys, time, urllib.request
model, port = sys.argv[1], int(sys.argv[2])
SYS_SAKURA = "你是一个轻小说翻译模型，可以流畅通顺地以日本轻小说的风格将日文翻译成简体中文，并联系上下文正确使用人称代词，不擅自添加原文中没有的代词。"
def chat(messages, **kw):
    body = dict(messages=messages, max_tokens=64, seed=7, cache_prompt=True, **kw)
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    t0 = time.time(); r = json.load(urllib.request.urlopen(req, timeout=120)); dt = time.time() - t0
    return r["choices"][0]["message"]["content"].strip(), r.get("timings", {}), r.get("usage", {}), dt
def gloss_lines(g, ja):
    return [e for e in g if e["ja"] in ja or any(p in ja for p in [e["ja"][:2], e["ja"][-2:]] if len(e["ja"]) >= 4)]
def build(model, ja, hist, gl):
    if model == "sakura":
        msgs = [{"role": "system", "content": SYS_SAKURA}]
        for hj, hz in hist:
            msgs += [{"role": "user", "content": "将下面的日文文本翻译成中文：" + hj}, {"role": "assistant", "content": hz}]
        if gl:
            u = "根据以下术语表（可以为空）：\n" + "\n".join(f"{e['ja']}->{e['zh']} #人名" for e in gl) + "\n将下面的日文文本根据对应关系和备注翻译成中文：" + ja
        else:
            u = "将下面的日文文本翻译成中文：" + ja
        return msgs + [{"role": "user", "content": u}], dict(temperature=0.1, top_p=0.3, frequency_penalty=0.1)
    # HY-MT (and abliterated): terminology + contextual templates in one user turn (no system prompt)
    u = ""
    if gl: u += "参考下面的翻译：\n" + "\n".join(f"{e['ja']} 翻译成 {e['zh']}" for e in gl) + "\n"
    if hist:
        u += "\n".join(h for h, _ in hist) + "\n参考上面的信息，把下面的文本翻译成中文，注意不需要翻译上文，也不要额外解释：\n" + ja
    else:
        u += "将以下文本翻译为中文，注意只需要输出翻译后的结果，不要额外解释：\n" + ja
    return [{"role": "user", "content": u}], dict(temperature=0.7, top_k=20, top_p=0.6, repeat_penalty=1.05)
for short in sys.argv[3:]:
    names = json.load(open(f"{short}_names.json"))
    g = [{"ja": n[0], "zh": n[1]} for n in names]
    # 2+2 halves like LiveMTPrep.glossary
    for n in names:
        if len(n[0]) == 4 and len(n[1]) == 4: g += [{"ja": n[0][:2], "zh": n[1][:2]}, {"ja": n[0][2:], "zh": n[1][2:]}]
    prep = json.load(open(f"{short}_prep.json"))
    disp = json.load(open(f"/workspace/eval291/{short}_291_clean.json"))["display"]
    out, recs, hist = {}, [], []
    for d in disp:
        ja = d["ja"]
        hist = [h for h in hist if d["start"] - h[2] <= 15][-3:]
        p = prep.get(ja, {"kind": "mt", "zh": ""})
        if ja in out: zh = out[ja]["zh"]
        elif p["kind"] in ("skip", "direct"):
            zh = p["zh"]; out[ja] = {"zh": zh, "raw": zh, "kind": p["kind"]}
        else:
            gl = gloss_lines(g, ja)
            msgs, kw = build(model, ja, [(a, b) for a, b, _ in hist], gl)
            zh, tm, us, dt = chat(msgs, **kw)
            out[ja] = {"zh": zh, "raw": zh, "kind": p["kind"], "prompt_n": tm.get("prompt_n"), "predicted_n": tm.get("predicted_n"),
                       "prompt_tokens": us.get("prompt_tokens"), "wall": round(dt, 3), "gloss": bool(gl), "hist": len(hist)}
        if zh: hist.append((ja, zh, d["start"]))
    json.dump(out, open(f"{short}_{model}.json", "w"), ensure_ascii=False, indent=0)
    n = [v for v in out.values() if "predicted_n" in v]
    print(short, model, len(out), "llm", len(n), "avg prompt_n", round(sum(v["prompt_n"] or 0 for v in n) / max(1, len(n)), 1),
          "avg prompt_tokens", round(sum(v["prompt_tokens"] or 0 for v in n) / max(1, len(n)), 1),
          "avg gen", round(sum(v["predicted_n"] or 0 for v in n) / max(1, len(n)), 1), flush=True)
