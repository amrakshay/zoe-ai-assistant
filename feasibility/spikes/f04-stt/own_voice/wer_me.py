#!/usr/bin/env python3
"""WER + latency summary for F04 results.
Usage: python3 wer.py [results_dir] [manifest.tsv]
Normalisation: lowercase, hyphens -> space, drop punctuation/apostrophes, a few spelling
equivalences (summarise/summarize, number words). Term hits = exact token match of the
technical terms in the reference (jira, mr, merge request, databricks, prj 21499, gitlab,
grafana, kubernetes, argocd, collector, ccb).
"""
import json, re, statistics, sys, glob, os

TERMS = ["jira", "mr", "merge request", "databricks", "prj 21499", "gitlab", "grafana",
         "kubernetes", "argocd", "collector", "ccb"]
EQUIV = {"summarize": "summarise", "5": "five", "argo": "argo", "prj21499": "prj 21499"}


def norm(s):
    s = s.lower().replace("’", "'")
    s = re.sub(r"(?<=\w)-(?=\w)", " ", s)
    s = s.replace("'", "")
    s = re.sub(r"(?<=\d),(?=\d)", "", s)  # 21,499 -> 21499
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    s = re.sub(r"\bargo cd\b", "argocd", s)  # common split
    toks = [EQUIV.get(t, t) for t in s.split()]
    return " ".join(toks).split()


def ed(a, b):
    d = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        p, d[0] = d[0], i
        for j in range(1, len(b) + 1):
            p, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, p + (a[i - 1] != b[j - 1]))
    return d[-1]


def pct(xs, q):
    xs = sorted(xs)
    if not xs:
        return float("nan")
    k = (len(xs) - 1) * q
    f = int(k)
    c = min(f + 1, len(xs) - 1)
    return xs[f] + (xs[c] - xs[f]) * (k - f)


def term_hits(ref, hyp):
    r, h = " " + " ".join(ref) + " ", " " + " ".join(hyp) + " "
    tot = hit = 0
    for t in TERMS:
        n = r.count(" " + t + " ")
        if n:
            tot += n
            hit += min(n, h.count(" " + t + " "))
    return hit, tot


def main():
    args = [a for a in sys.argv[1:] if a != "-v"]
    rdir = args[0] if args else "results"
    man = args[1] if len(args) > 1 else "audio/manifest.tsv"
    refs, voice = {}, {}
    for line in open(man):
        p = line.rstrip("\n").split("\t")
        refs[p[0]], voice[p[0]] = p[2], p[1]
    in_voices = {"Rishi", "Aman", "Tara", "me"}
    print("| Run | WER all | WER en-IN voices | WER en-US voices | WER excl. Fred | Tech terms right | First partial p50 / p90 (ms) | Final after last chunk p50 / p90 (ms) | Errors |")
    print("|---|---|---|---|---|---|---|---|---|")
    details = []
    for f in sorted(glob.glob(os.path.join(rdir, "*.jsonl"))):
        rows = [json.loads(l) for l in open(f) if l.strip().startswith("{")]
        rows = [r for r in rows if r.get("id") in refs]
        if not rows:
            continue
        Ef = Nf = E = N = Ei = Ni = Eu = Nu = th = tt = errs = 0
        fp, fin = [], []
        for r in rows:
            ref, hyp = norm(refs[r["id"]]), norm(r.get("hyp", ""))
            e = ed(ref, hyp)
            E += e; N += len(ref)
            if voice[r["id"]] in in_voices:
                Ei += e; Ni += len(ref)
            else:
                Eu += e; Nu += len(ref)
            if voice[r["id"]] != "Fred":
                Ef += e; Nf += len(ref)
            a, b = term_hits(ref, hyp); th += a; tt += b
            if r.get("error"):
                errs += 1
            if r.get("firstPartialMs") is not None:
                fp.append(r["firstPartialMs"])
            if r.get("finalAfterLastChunkMs") is not None:
                fin.append(max(0.0, r["finalAfterLastChunkMs"]))
            details.append((os.path.basename(f)[:-6], r["id"], e, refs[r["id"]], r.get("hyp", "")))
        name = os.path.basename(f)[:-6]
        print(f"| {name} | {E/N:.1%} | {Ei/max(Ni,1):.1%} | {Eu/max(Nu,1):.1%} | {Ef/max(Nf,1):.1%} | {th}/{tt} | {pct(fp,.5):.0f} / {pct(fp,.9):.0f} | {pct(fin,.5):.0f} / {pct(fin,.9):.0f} | {errs} |")
    if "-v" in sys.argv:
        print("\n| Run | Id | Errors | Reference | Hypothesis |\n|---|---|---|---|---|")
        for d in details:
            if d[2]:
                print(f"| {d[0]} | {d[1]} | {d[2]} | {d[3]} | {d[4]} |")


if __name__ == "__main__":
    main()
