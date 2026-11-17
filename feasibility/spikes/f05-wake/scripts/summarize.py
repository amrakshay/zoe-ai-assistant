"""Summarise per-clip max scores from results/<name>_scores.json; optional second file to compare."""
import json, sys, os, csv
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
a = json.load(open(os.path.join(ROOT, f"results/{sys.argv[1]}_scores.json")))
idx = {r[0]: (r[1], r[2]) for r in csv.reader(open(os.path.join(ROOT, "audio/index.tsv")), delimiter="\t")}
POS = ["hey claude", "hey Claude, can you check my calendar", "hey Claude what time is it"]
NEG = ["hey cloud", "say cloud out loud", "hey clod", "the weather today looks cloudy", "please open the terminal and run the tests", "hey there how are you"]
rows = []
for k, v in a.items():
    if k == "long_concat": continue
    kind, vi, j = os.path.basename(k)[:-4].split("_")
    voice, rate = idx[vi]
    text = (POS if kind == "p" else NEG)[int(j)]
    rows.append((kind, text, voice, rate, max(v)))
for kind in "pn":
    texts = POS if kind == "p" else NEG
    for t in texts:
        r = [x for x in rows if x[0] == kind and x[1] == t]
        ms = sorted(x[4] for x in r)
        print(f"{kind} | {t} | n={len(ms)} | min {ms[0]:.3f} | median {ms[len(ms)//2]:.3f} | max {ms[-1]:.3f} | >=0.5: {sum(m>=0.5 for m in ms)}")
print("\nper voice/rate (positives detected @0.5 of 3 | max neg score):")
for vi in sorted(idx, key=int):
    v, rt = idx[vi]
    p = [x[4] for x in rows if x[0]=="p" and x[2]==v and x[3]==rt]
    n = [x[4] for x in rows if x[0]=="n" and x[2]==v and x[3]==rt]
    print(f"  {v:22s} {rt}: {sum(s>=0.5 for s in p)}/3 pos max {[round(s,3) for s in p]} | neg max {max(n):.3f}")
if len(sys.argv) > 2:
    b = json.load(open(os.path.join(ROOT, f"results/{sys.argv[2]}_scores.json")))
    worst, n = 0.0, 0
    for k in a:
        if k not in b: continue
        L = min(len(a[k]), len(b[k]))
        d = max(abs(x-y) for x, y in zip(a[k][:L], b[k][:L]))
        worst = max(worst, d); n += L
        if len(a[k]) != len(b[k]): print("len mismatch", k, len(a[k]), len(b[k]))
    print(f"\nmax |{sys.argv[1]} - {sys.argv[2]}| per-frame score diff over {n} frames: {worst:.2e}")
