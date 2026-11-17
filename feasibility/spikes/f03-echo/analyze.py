"""F03 echo analysis. Run: uv run --with numpy --with soundfile python analyze.py novp vp speak"""
import json, sys
import numpy as np, soundfile as sf

def db(p): return 10 * np.log10(max(p, 1e-20))

def load(case):
    mic, sr = sf.read(f"{case}_mic.wav", dtype="float64")
    ref, rsr = sf.read(f"{case}_ref.wav", dtype="float64")
    meta = json.load(open(f"{case}_meta.json"))
    t = np.arange(int(len(ref) * sr / rsr)) / sr
    ref48 = np.interp(t, np.arange(len(ref)) / rsr, ref)
    return mic, ref48, sr, meta

def xcorr_peak(seg, ref):
    n = 1 << int(np.ceil(np.log2(len(seg) + len(ref))))
    c = np.fft.irfft(np.fft.rfft(seg, n) * np.conj(np.fft.rfft(ref, n)), n)[: len(seg) - len(ref) + 1]
    # normalise by local energy of seg under the ref window
    e = np.sqrt(np.convolve(seg ** 2, np.ones(len(ref)), "valid")) * np.linalg.norm(ref)
    r = np.abs(c) / np.maximum(e, 1e-12)
    k = int(np.argmax(r))
    return r[k], k

def linear_echo_power(mic, ref, nfft=2048):
    """Power in mic linearly predictable from ref (Welch cross-spectrum): sum |Sxy|^2/Sxx, per sample."""
    hop = nfft // 2; w = np.hanning(nfft)
    Sxx = np.zeros(nfft // 2 + 1); Sxy = np.zeros(nfft // 2 + 1, complex); Syy = np.zeros(nfft // 2 + 1); m = 0
    for i in range(0, min(len(mic), len(ref)) - nfft, hop):
        X = np.fft.rfft(w * ref[i:i + nfft]); Y = np.fft.rfft(w * mic[i:i + nfft])
        Sxx += abs(X) ** 2; Syy += abs(Y) ** 2; Sxy += Y * np.conj(X); m += 1
    lin = np.sum(np.abs(Sxy) ** 2 / np.maximum(Sxx, 1e-20)); tot = np.sum(Syy)
    return lin / tot  # fraction of mic power that is linear echo

rows = {}
for case in sys.argv[1:]:
    mic, ref, sr, meta = load(case)
    ps, pe = meta["play_start"], meta["play_end"]
    sil = mic[int(0.3 * sr):ps]
    play = mic[ps:pe]
    p_sil, p_play = np.mean(sil ** 2), np.mean(play ** 2)
    seg = mic[ps - int(0.1 * sr): min(len(mic), pe + int(1.0 * sr))]
    rho, k = xcorr_peak(seg, ref[: len(ref)])
    lag_ms = (k - int(0.1 * sr)) / sr * 1000
    al = mic[ps - int(0.1 * sr) + k:][: len(ref)]
    frac = linear_echo_power(al, ref[: len(al)])
    p_lin = frac * np.mean(al ** 2)
    bins = [round(db(np.mean(mic[i:i + int(0.25 * sr)] ** 2)), 1) for i in range(0, len(mic) - int(0.25 * sr), int(0.25 * sr))]
    rows[case] = dict(sil_db=db(p_sil), play_db=db(p_play), delta=db(p_play) - db(p_sil),
                      excess_db=db(max(p_play - p_sil, 1e-20)), rho=rho, lag_ms=lag_ms,
                      lin_frac=frac, lin_db=db(p_lin), peak=float(np.max(np.abs(mic))), bins=bins)

print("| case | silence RMS dBFS | playback RMS dBFS | playback - silence dB | excess (echo) power dBFS | xcorr peak (norm) | lag ms | linear-echo share of mic power | linear echo dBFS |")
print("|---|---|---|---|---|---|---|---|---|")
for c, r in rows.items():
    print(f"| {c} | {r['sil_db']:.1f} | {r['play_db']:.1f} | {r['delta']:+.1f} | {r['excess_db']:.1f} | {r['rho']:.3f} | {r['lag_ms']:.0f} | {100*r['lin_frac']:.1f}% | {r['lin_db']:.1f} |")
if "novp" in rows:
    for c in rows:
        if c == "novp": continue
        print(f"ERLE {c} vs novp: excess-power {rows['novp']['excess_db'] - rows[c]['excess_db']:.1f} dB; linear-echo {rows['novp']['lin_db'] - rows[c]['lin_db']:.1f} dB")
for c, r in rows.items():
    print(c, "250ms-bin dBFS:", r["bins"])

# Per-250 ms bin: level and best local normalised correlation with the reference (lag 0-800 ms),
# to tell leaked synth speech from other room sound.
print("\nper-bin (t s: dBFS / local xcorr) during playback")
for case in sys.argv[1:]:
    mic, ref, sr, meta = load(case); ps = meta["play_start"]; B = int(0.25 * sr); out = []
    for i in range(0, len(mic) - B, B):
        seg = mic[i:i + B]
        if np.mean(seg ** 2) < 1e-6: out.append(f"{i/sr:.2f}:{db(np.mean(seg**2)):.0f}/-"); continue
        best = 0
        for lag in range(0, int(0.8 * sr), int(0.002 * sr)):
            j = i - ps - lag
            if j < 0 or j + B > len(ref): continue
            r = ref[j:j + B]; d = np.linalg.norm(r) * np.linalg.norm(seg)
            if d > 0: best = max(best, abs(np.dot(r, seg)) / d)
        out.append(f"{i/sr:.2f}:{db(np.mean(seg**2)):.0f}/{best:.2f}")
    print(case, " ".join(out))
    play_bins = [db(np.mean(mic[i:i+B]**2)) for i in range(meta["play_start"], meta["play_end"] - B, B)]
    post = [db(np.mean(mic[i:i+B]**2)) for i in range(meta["play_end"] + int(0.5*sr), len(mic) - B, B)]
    print(f"{case}: median playback-bin {np.median(play_bins):.1f} dBFS, median post-playback floor {np.median(post):.1f} dBFS")
