"""Score the own-voice wake-word recordings (audio/own/) with hey_claude.onnx (openwakeword 0.6).

- Each block is scored as one stream (fresh model, 1 s of silence in front), 80 ms frames.
- Utterances are found by energy (20 ms RMS above the noise floor + 12 dB, gaps < 0.8 s merged),
  so the cue timing doesn't matter. An utterance counts as a detection when any frame from its
  start to 1 s after its end scores >= the threshold.
- False fires: detections (2 s refractory) on free_talk.wav plus the 30 F04 speech-to-text
  recordings, none of which contain "hey Claude".
Prints a markdown report.
"""
import glob, os, wave
import numpy as np
from openwakeword.model import Model

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
M = os.path.join(ROOT, "models")
OWN = os.environ.get("OWN_DIR") or os.path.join(ROOT, "audio/own")
FRAME, SR = 1280, 16000
THRS = [0.5, 0.3, 0.2, 0.1, 0.05]
EXPECTED = {"pos_normal": 10, "pos_command": 8, "pos_far": 6, "pos_fast": 6, "neg_near": 12}
NEAR = ["Hey cloud", "Hey clod", "Hey Claudia", "Hey Clyde", "Hey cloth", "Okay Claude",
        "Hey, cloud sync", "Claude Code is open", "They clawed it", "A cloudy day", "Hey, close it", "Hey Clara"]


def load(p):
    with wave.open(p) as w:
        assert w.getframerate() == SR and w.getnchannels() == 1 and w.getsampwidth() == 2, p
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)


model = Model(wakeword_models=[os.path.join(M, "hey_claude.onnx")], inference_framework="onnx",
              melspec_model_path=os.path.join(M, "melspectrogram.onnx"),
              embedding_model_path=os.path.join(M, "embedding_model.onnx"))


def scores(audio):
    model.reset()
    a = np.concatenate([np.zeros(SR, np.int16), audio])
    s = np.array([float(model.predict(a[i*FRAME:(i+1)*FRAME])["hey_claude"]) for i in range(len(a)//FRAME)])
    t = (np.arange(len(s)) + 1) * FRAME / SR - 1.0   # time (s, in the original audio) at frame end
    return t, s


def utterances(audio):
    hop = SR // 50
    x = audio[: len(audio)//hop*hop].astype(np.float32).reshape(-1, hop)
    db = 20*np.log10(np.sqrt((x**2).mean(1)) + 1e-6)
    floor = np.percentile(db, 10)
    on = db > floor + 12
    segs, start, last = [], None, None
    for i, v in enumerate(on):
        if v:
            if start is None: start = i
            elif i - last > 40:           # gap > 0.8 s: new utterance
                segs.append((start, last)); start = i
            last = i
    if start is not None: segs.append((start, last))
    return [(a/50, (b+1)/50) for a, b in segs if (b - a + 1) >= 13]   # >= 0.26 s


def dets(t, s, thr, refractory=2.0):
    out, lastt = [], -1e9
    for ti, si in zip(t, s):
        if si >= thr and ti - lastt >= refractory:
            out.append(ti); lastt = ti
    return out


print("# Wake word on my own voice: `hey_claude.onnx`\n")
blocks = {}
for name in EXPECTED:
    p = os.path.join(OWN, name + ".wav")
    if not os.path.exists(p): continue
    a = load(p); t, s = scores(a); u = utterances(a)
    peaks = [float(s[(t >= u0) & (t <= u1 + 1.0)].max(initial=0)) for u0, u1 in u]
    blocks[name] = (u, peaks, len(a)/SR)

print("## Utterances found (by energy) vs cues\n\n| Block | Cues | Utterances found |\n|---|---|---|")
for n, (u, _, d) in blocks.items():
    print(f"| {n} | {EXPECTED[n]} | {len(u)} ({d:.0f} s) |")

print("\n## Recall on \"Hey Claude\" (utterances detected)\n")
print("| Block | " + " | ".join(f"≥ {x}" for x in THRS) + " | Peak score per utterance |")
print("|---|" + "---|"*len(THRS) + "---|")
allp = []
for n, (u, peaks, _) in blocks.items():
    if not n.startswith("pos"): continue
    allp += peaks
    print(f"| {n} | " + " | ".join(f"{sum(p >= x for p in peaks)}/{len(peaks)}" for x in THRS)
          + " | " + ", ".join(f"{p:.2f}" for p in peaks) + " |")
if allp:
    print("| **all** | " + " | ".join(f"**{sum(p >= x for p in allp)}/{len(allp)}** ({sum(p >= x for p in allp)/len(allp):.0%})" for x in THRS) + " | |")

if "neg_near" in blocks:
    u, peaks, _ = blocks["neg_near"]
    print("\n## Near-misses (must not fire)\n")
    print("| Threshold | " + " | ".join(f"≥ {x}" for x in THRS) + " |\n|---|" + "---|"*len(THRS))
    print("| Fired | " + " | ".join(f"{sum(p >= x for p in peaks)}/{len(peaks)}" for x in THRS) + " |")
    if len(peaks) == len(NEAR):
        print("\n| Phrase | Peak score |\n|---|---|")
        for ph, p in zip(NEAR, peaks): print(f"| {ph} | {p:.3f} |")
    else:
        print(f"\n(Found {len(peaks)} utterances for {len(NEAR)} cues, so per-phrase labels are skipped.) Peaks: "
              + ", ".join(f"{p:.3f}" for p in peaks))

neg = []
fp = os.path.join(OWN, "free_talk.wav")
if os.path.exists(fp): neg.append(load(fp))
stt = sorted(glob.glob(os.path.join(ROOT, "../f04-stt/own_voice*/*_me.wav")))
gap = np.zeros(SR // 2, np.int16)
for f in stt: neg += [load(f), gap]
if neg:
    a = np.concatenate(neg); t, s = scores(a); mins = len(a)/SR/60
    print(f"\n## False fires on ordinary speech\n\n{mins:.1f} min: free talk plus {len(stt)} speech-to-text recordings. Peak score {s.max():.3f}.\n")
    print("| Threshold | " + " | ".join(f"≥ {x}" for x in THRS) + " |\n|---|" + "---|"*len(THRS))
    print("| Fires | " + " | ".join(str(len(dets(t, s, x))) for x in THRS) + " |")
