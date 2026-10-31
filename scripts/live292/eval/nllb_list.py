import json, sys, torch
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM
torch.set_num_threads(8)
name='facebook/nllb-200-distilled-600M'
tok=AutoTokenizer.from_pretrained(name, src_lang='jpn_Jpan'); m=AutoModelForSeq2SeqLM.from_pretrained(name).eval()
cache=json.load(open(sys.argv[1])); todo=[t for t in json.load(open(sys.argv[2])) if t not in cache]
for i in range(0,len(todo),16):
    b=todo[i:i+16]; x=tok(b,return_tensors='pt',padding=True)
    with torch.no_grad(): y=m.generate(**x,forced_bos_token_id=tok.convert_tokens_to_ids('zho_Hans'),max_new_tokens=64,num_beams=1)
    for s,o in zip(b,tok.batch_decode(y,skip_special_tokens=True)): cache[s]=o
json.dump(cache,open(sys.argv[1],'w'),ensure_ascii=False,indent=0); print('nllb',len(todo),'new')
