"""F05 Python baseline: score clips with openwakeword 0.6 (ONNX) and hey_claude.onnx.
Each short clip is padded with 1 s silence before and after, fed in 80 ms (1280-sample) frames
from a fresh model. Writes per-frame scores to results/py_scores.json."""
import json, sys, wave, glob, os
import numpy as np
from openwakeword.model import Model

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
M = os.path.join(ROOT, "models")
FRAME = 1280

def load(path):
    with wave.open(path) as w:
        assert w.getframerate() == 16000 and w.getnchannels() == 1 and w.getsampwidth() == 2
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)

def new_model():
    return Model(wakeword_models=[os.path.join(M, "hey_claude.onnx")], inference_framework="onnx",
                 melspec_model_path=os.path.join(M, "melspectrogram.onnx"),
                 embedding_model_path=os.path.join(M, "embedding_model.onnx"))

def frames_scores(model, audio):
    n = len(audio) // FRAME
    out = []
    for i in range(n):
        s = model.predict(audio[i*FRAME:(i+1)*FRAME])
        out.append(float(s["hey_claude"]))
    return out

def detections(scores, thr=0.5, refractory_frames=25):  # 2 s / 80 ms
    det, last = 0, -10**9
    for i, s in enumerate(scores):
        if s >= thr and i - last >= refractory_frames:
            det += 1; last = i
    return det

res = {}
pad = np.zeros(16000, dtype=np.int16)
model = new_model()
for f in sorted(glob.glob(os.path.join(ROOT, "audio/pos/*.wav")) + glob.glob(os.path.join(ROOT, "audio/neg/*.wav"))):
    model.reset()
    a = np.concatenate([pad, load(f), pad])
    sc = frames_scores(model, a)
    res[os.path.relpath(f, ROOT)] = sc
# long negatives: concatenate all long files + 5 min of near-silence (low noise)
rng = np.random.default_rng(0)
noise = (rng.normal(0, 30, 16000*300)).astype(np.int16)
long_audio = np.concatenate([load(f) for f in sorted(glob.glob(os.path.join(ROOT, "audio/long/*.wav")))] + [noise])
model.reset()
sc = frames_scores(model, long_audio)
res["long_concat"] = sc
os.makedirs(os.path.join(ROOT, "results"), exist_ok=True)
json.dump(res, open(os.path.join(ROOT, "results/py_scores.json"), "w"))
hours = len(long_audio) / 16000 / 3600
print(f"long: {len(long_audio)/16000/60:.1f} min, max {max(sc):.4f}, dets@0.5 {detections(sc)}, dets@0.3 {detections(sc,0.3)} -> {detections(sc)/hours:.2f}/h")
