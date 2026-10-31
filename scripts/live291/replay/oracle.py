# Offline oracle: silero VAD (sherpa-onnx) + SenseVoice-Small (same int8 model as the app), whole file, no realtime limits.
import sys, json, wave, numpy as np, sherpa_onnx, re
wav, out = sys.argv[1], sys.argv[2]
M='/workspace/so289/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17'
w=wave.open(wav); a=np.frombuffer(w.readframes(w.getnframes()),dtype=np.int16).astype(np.float32)/32768
cfg=sherpa_onnx.VadModelConfig(); cfg.silero_vad.model='silero_vad.onnx'; cfg.silero_vad.min_silence_duration=0.3
cfg.silero_vad.min_speech_duration=0.2; cfg.silero_vad.max_speech_duration=8; cfg.silero_vad.threshold=0.4; cfg.sample_rate=16000
vad=sherpa_onnx.VoiceActivityDetector(cfg, buffer_size_in_seconds=900)
rec=sherpa_onnx.OfflineRecognizer.from_sense_voice(model=M+'/model.int8.onnx',tokens=M+'/tokens.txt',language='ja',use_itn=True,num_threads=4)
segs=[]
for i in range(0,len(a),512):
    vad.accept_waveform(a[i:i+512])
    while not vad.empty():
        s=vad.front; segs.append((s.start/16000,(s.start+len(s.samples))/16000,np.array(s.samples))); vad.pop()
vad.flush()
while not vad.empty():
    s=vad.front; segs.append((s.start/16000,(s.start+len(s.samples))/16000,np.array(s.samples))); vad.pop()
res=[]
for st,en,x in segs:
    s=rec.create_stream(); s.accept_waveform(16000,x); rec.decode_stream(s)
    t=re.sub(r'<\|[^|]*\|>','',s.result.text).strip()
    t=re.sub(r'(?<=[^\x00-\x7F])[ \t\u3000]+(?=[^\x00-\x7F])','',t)
    body=re.sub(r'[。、！？!?….・♪〜~ 　「」『』]','',t)
    res.append({'start':round(st,2),'end':round(en,2),'ja':t,'speech':bool(body)})
json.dump(res,open(out,'w'),ensure_ascii=False,indent=1)
print(len(res),'segments',sum(r['speech'] for r in res),'with text')
