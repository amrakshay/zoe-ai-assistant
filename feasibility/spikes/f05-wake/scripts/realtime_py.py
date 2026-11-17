"""Python reference: feed 80 ms frames at real-time pace for N seconds; report process CPU % and max RSS."""
import sys, time, wave, resource, os
import numpy as np
from openwakeword.model import Model
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); M = os.path.join(ROOT, "models")
w = wave.open(sys.argv[1]); a = np.frombuffer(w.readframes(w.getnframes()), np.int16)
secs = float(sys.argv[2])
m = Model(wakeword_models=[M+"/hey_claude.onnx"], inference_framework="onnx",
          melspec_model_path=M+"/melspectrogram.onnx", embedding_model_path=M+"/embedding_model.onnx")
for k in range(12): m.predict(a[k*1280:(k+1)*1280])
n = int(secs/0.08); t0 = time.monotonic(); c0 = time.process_time()
for k in range(n):
    d = t0 + (k+1)*0.08 - time.monotonic()
    if d > 0: time.sleep(d)
    s = ((k+12)*1280) % (len(a)-1280)
    m.predict(a[s:s+1280])
wall = time.monotonic()-t0; cpu = time.process_time()-c0
print(f"python openwakeword: frames={n} wall={wall:.1f}s cpu={cpu:.3f}s avgCPU={100*cpu/wall:.2f}% maxRSS={resource.getrusage(resource.RUSAGE_SELF).ru_maxrss/1e6:.1f} MB")
