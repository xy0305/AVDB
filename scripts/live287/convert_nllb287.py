#!/usr/bin/env python3
"""Build 287: NLLB-200-distilled-600M (CC-BY-NC-4.0) → Core ML fallback ja→zh-Hans translator.

Vocabulary is trimmed to pieces made of kana / CJK / CJK punctuation / fullwidth / digits+ASCII punctuation
(+ single ASCII letters), so the 256k-row embedding and LM head shrink. Static shapes (ANE-friendly):
encoder 64 source tokens, decoder 48 target positions, no KV cache (the step's logits are selected in-graph
by a one-hot `step` mask). Weights int8 (linear symmetric). Writes:
  <out>/NLLBEncoder.mlpackage  <out>/NLLBDecoder.mlpackage  <out>/nllb287_vocab.json  <out>/nllb287_reference.json
Usage: convert_nllb287.py OUT_DIR [--no-coreml]"""
import json, os, sys, time
import torch, torch.nn as nn
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM
import sentencepiece as spm
from huggingface_hub import snapshot_download

REPO, REV = "facebook/nllb-200-distilled-600M", "f8d333a098d19b4fd9a8b18f94170487ad3f821d"
SRC_LEN, TGT_LEN = 64, 48
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
path = snapshot_download(REPO, revision=REV, allow_patterns=["*.json", "*.model", "pytorch_model.bin"])
sp = spm.SentencePieceProcessor(model_file=os.path.join(path, "sentencepiece.bpe.model"))
tok = AutoTokenizer.from_pretrained(path, src_lang="jpn_Jpan")
model = AutoModelForSeq2SeqLM.from_pretrained(path, attn_implementation="eager", torch_dtype=torch.float32).eval().requires_grad_(False)

def cjk(c):
    o = ord(c)
    return 0x3000 <= o <= 0x30ff or 0x31f0 <= o <= 0x31ff or 0x3400 <= o <= 0x4dbf or 0x4e00 <= o <= 0x9fff \
        or 0xf900 <= o <= 0xfaff or 0xff00 <= o <= 0xffef or 0x2000 <= o <= 0x206f or o in (0xb7, 0xd7)
def keep_piece(p):
    body = p.replace("▁", "")
    if body == "": return True
    if all(cjk(c) or (0x20 <= ord(c) <= 0x7e and not c.isalpha()) for c in body): return True
    return len(body) == 1 and body.isascii()
# HF ids: 0 <s>, 1 <pad>, 2 </s>, 3 <unk>; spm piece i (i >= 3; spm 0..2 = unk/s/\s) -> HF id i + 1.
kept_hf = [0, 1, 2, 3] + [i + 1 for i in range(3, sp.get_piece_size()) if keep_piece(sp.id_to_piece(i))]
JA, ZH = tok.convert_tokens_to_ids("jpn_Jpan"), tok.convert_tokens_to_ids("zho_Hans")
kept_hf += [JA, ZH]
compact = {h: c for c, h in enumerate(kept_hf)}
K = len(kept_hf)
print("vocab", K, "of", model.config.vocab_size)

W = model.model.shared.weight.data[kept_hf].clone()
emb = model.model.encoder.embed_tokens
scale = float(getattr(emb, "embed_scale", 1.0) or 1.0)
print("embed_scale", scale)
E, D = model.model.encoder, model.model.decoder
POS_SRC = E.embed_positions.weights[E.embed_positions.padding_idx + 1:][:SRC_LEN].clone()   # padding at the right ->
POS_TGT = D.embed_positions.weights[D.embed_positions.padding_idx + 1:][:TGT_LEN].clone()   # positions 0..L-1
NEG = -1e4                                                                                   # fp16-safe additive mask
CAUSAL = torch.triu(torch.full((TGT_LEN, TGT_LEN), NEG), 1)[None, None]
H = model.config.encoder_attention_heads; DM = model.config.d_model; HD = DM // H
assert model.config.activation_function == "relu"
def attn(a, x, kv, mask, Lq, Lk):
    """Static-shape re-implementation of M2M100Attention (eager) for tracing."""
    q = (a.q_proj(x) * a.scaling).view(1, Lq, H, HD).transpose(1, 2)
    k = a.k_proj(kv).view(1, Lk, H, HD).transpose(1, 2)
    v = a.v_proj(kv).view(1, Lk, H, HD).transpose(1, 2)
    w = torch.softmax(q @ k.transpose(-1, -2) + mask, dim=-1)
    return a.out_proj((w @ v).transpose(1, 2).reshape(1, Lq, DM))
def ffn(l, h):
    return h + l.fc2(torch.relu(l.fc1(l.final_layer_norm(h))))
class Enc(nn.Module):
    """Explicit M2M100 encoder: constant positions and additive masks (no dynamic shape ops)."""
    def __init__(s):
        super().__init__(); s.W = nn.Parameter(W, requires_grad=False)
        s.register_buffer("pos", POS_SRC)
    def forward(s, input_ids, attention_mask):
        h = s.W[input_ids.long()] * scale + s.pos[None]
        m = (1.0 - attention_mask.float())[:, None, None, :] * NEG
        for l in E.layers:
            x = l.self_attn_layer_norm(h); h = h + attn(l.self_attn, x, x, m, SRC_LEN, SRC_LEN)
            h = ffn(l, h)
        return E.layer_norm(h)
class Dec(nn.Module):
    def __init__(s):
        super().__init__(); s.W = nn.Parameter(W, requires_grad=False)
        s.register_buffer("pos", POS_TGT); s.register_buffer("causal", CAUSAL)
    def forward(s, decoder_input_ids, encoder_hidden, encoder_mask, step):
        h = s.W[decoder_input_ids.long()] * scale + s.pos[None]
        em = (1.0 - encoder_mask.float())[:, None, None, :] * NEG
        for l in D.layers:
            x = l.self_attn_layer_norm(h); h = h + attn(l.self_attn, x, x, s.causal, TGT_LEN, TGT_LEN)
            x = l.encoder_attn_layer_norm(h); h = h + attn(l.encoder_attn, x, encoder_hidden, em, TGT_LEN, SRC_LEN)
            h = ffn(l, h)
        h = D.layer_norm(h)
        h = (h * step.unsqueeze(-1)).sum(1)
        return h @ s.W.t()
enc, dec = Enc().eval(), Dec().eval()

def encode_src(text):
    ids = tok(text).input_ids
    c = [compact.get(i, 3) for i in ids][:SRC_LEN]
    m = [1] * len(c) + [0] * (SRC_LEN - len(c)); c = c + [1] * (SRC_LEN - len(c))
    return torch.tensor([c], dtype=torch.int32), torch.tensor([m], dtype=torch.int32)
def greedy(text):
    ids, mask = encode_src(text)
    with torch.no_grad():
        h = enc(ids, mask)
        seq = [2, compact[ZH]]
        while len(seq) < TGT_LEN:
            d = torch.ones(1, TGT_LEN, dtype=torch.int32); d[0, :len(seq)] = torch.tensor(seq)
            st = torch.zeros(1, TGT_LEN); st[0, len(seq) - 1] = 1
            nxt = int(dec(d, h, mask, st).argmax(-1))
            seq.append(nxt)
            if nxt == 2: break
    return seq
inv = {c: h for h, c in compact.items()}
def detok(seq):
    return tok.decode([inv[c] for c in seq], skip_special_tokens=True)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ja_samples287 import SENTENCES
ref = []
for s in SENTENCES:
    t = time.time(); seq = greedy(s["ja"]); dt = time.time() - t
    full = model.generate(**tok(s["ja"], return_tensors="pt"), forced_bos_token_id=ZH, num_beams=1, do_sample=False, max_new_tokens=TGT_LEN - 2)
    full_txt = tok.decode(full[0], skip_special_tokens=True)
    ref.append({"ja": s["ja"], "src": encode_src(s["ja"])[0][0].tolist(), "seq": seq, "zh": detok(seq), "full": full_txt, "torch_s": dt})
    print(f"{dt:.2f}s {s['ja']} -> {detok(seq)}  | full: {full_txt}")
agree = sum(r["zh"] == r["full"] for r in ref)
print(f"trimmed == full-vocab greedy on {agree}/{len(ref)}")

pieces = []
for c, h in enumerate(kept_hf):
    if 4 <= c < K - 2: pieces.append([sp.id_to_piece(h - 1), sp.get_score(h - 1)])
json.dump({"model": REPO, "revision": REV, "license": "CC-BY-NC-4.0", "srcLen": SRC_LEN, "tgtLen": TGT_LEN,
           "vocabSize": K, "bos": 0, "pad": 1, "eos": 2, "unk": 3, "jpn_Jpan": compact[JA], "zho_Hans": compact[ZH],
           "pieceOffset": 4, "pieces": pieces}, open(os.path.join(out, "nllb287_vocab.json"), "w"), ensure_ascii=False)
json.dump(ref, open(os.path.join(out, "nllb287_reference.json"), "w"), ensure_ascii=False, indent=1)
if "--no-coreml" in sys.argv: sys.exit(0)

import coremltools as ct
import coremltools.optimize.coreml as cto
def convert(module, example, inputs, outputs, name):
    with torch.no_grad(): traced = torch.jit.trace(module, example, check_trace=False, strict=False)
    m = ct.convert(traced, inputs=inputs, outputs=outputs, convert_to="mlprogram",
                   minimum_deployment_target=ct.target.iOS17, compute_precision=ct.precision.FLOAT16)
    m = cto.linear_quantize_weights(m, cto.OptimizationConfig(global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric", weight_threshold=2048)))
    m.author = "AVDB build 287 from facebook/nllb-200-distilled-600M"; m.license = "CC-BY-NC-4.0"
    m.save(os.path.join(out, name)); print("saved", name)
ids, mask = encode_src(SENTENCES[0]["ja"])
convert(enc, (ids, mask), [ct.TensorType("input_ids", shape=(1, SRC_LEN), dtype=int), ct.TensorType("attention_mask", shape=(1, SRC_LEN), dtype=int)],
        [ct.TensorType("hidden")], "NLLBEncoder.mlpackage")
with torch.no_grad(): h = enc(ids, mask)
d = torch.ones(1, TGT_LEN, dtype=torch.int32); st = torch.zeros(1, TGT_LEN); st[0, 1] = 1
convert(dec, (d, h, mask, st), [ct.TensorType("decoder_input_ids", shape=(1, TGT_LEN), dtype=int), ct.TensorType("encoder_hidden", shape=(1, SRC_LEN, 1024)),
        ct.TensorType("encoder_mask", shape=(1, SRC_LEN), dtype=int), ct.TensorType("step", shape=(1, TGT_LEN))], [ct.TensorType("logits")], "NLLBDecoder.mlpackage")
