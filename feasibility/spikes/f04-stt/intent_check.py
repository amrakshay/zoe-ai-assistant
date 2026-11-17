#!/usr/bin/env python3
"""Does Claude still get the request right from an imperfect transcript?

For each run (a wer.py-style JSONL of {id, hyp}):
  1. Interpret: Claude sees ONLY the transcripts (never the reference) plus a short
     description of my work context, standing in for what a real session knows from
     CLAUDE.md and connectors. It writes the command it thinks I meant.
  2. Judge: a separate call compares each interpretation with the reference phrase and
     grades it: same (would do the same thing), partial (right action, a detail wrong or
     missing, e.g. a ticket number), wrong.

Usage: intent_check.py <manifest.tsv> <out.md> <run.jsonl>...
Uses `claude -p` (Sonnet) on my login, with no tools, no MCP and no user settings/hooks.
"""
import json, subprocess, sys, os

CONTEXT = ("The speaker is a software engineer at a software company. Day to day they use "
           "GitLab (MRs, pipelines), Jira (PRJ and ATLAS tickets), Slack, Confluence, PagerDuty, "
           "Grafana, ArgoCD, Kubernetes, Helm, Postgres, Databricks, and dev environments named "
           "alpha, beta and gamma. Components include the collector and runtime manager.")


def claude(prompt):
    r = subprocess.run(["claude", "-p", "--model", "sonnet", "--setting-sources", "project",
                        "--strict-mcp-config", "--tools", "", "--no-session-persistence",
                        "--output-format", "json"], input=prompt, capture_output=True, text=True,
                       timeout=300)
    out = json.loads(r.stdout)["result"].strip()
    if out.startswith("```"):
        out = out.split("\n", 1)[1].rsplit("```", 1)[0]
    return json.loads(out)


def main():
    man, outmd, runs = sys.argv[1], sys.argv[2], sys.argv[3:]
    refs = {}
    for line in open(man):
        p = line.rstrip("\n").split("\t")
        refs[p[0]] = p[2]
    md = ["| Run | Same | Partial | Wrong |", "|---|---|---|---|"]
    detail = ["", "| Run | Id | Transcript | Claude's reading | Reference | Grade |", "|---|---|---|---|---|---|"]
    for run in runs:
        rows = [json.loads(l) for l in open(run) if l.strip().startswith("{")]
        rows = [r for r in rows if r["id"] in refs]
        items = {r["id"]: r.get("hyp", "") for r in rows}
        interp = claude(
            "Each item below is a voice command transcribed by speech-to-text. The transcript may "
            "contain recognition errors (wrong words that sound similar, dropped words). "
            f"Context: {CONTEXT}\nTreat each item independently. For each, write the single command "
            "you think the speaker actually meant, as one short line. If you can't tell, write your best "
            "guess and append ' (?)'.\nReturn ONLY a JSON object mapping id to your reading.\n\n"
            + json.dumps(items, indent=1))
        pairs = {i: {"reference": refs[i], "reading": interp.get(i, "")} for i in items}
        grades = claude(
            "For each id, compare what the speaker said (reference) with an assistant's reading of a "
            "noisy transcript. Grade: \"same\" if acting on the reading would do the same thing as the "
            "reference (wording may differ); \"partial\" if the action is right but a detail is wrong or "
            "missing (an id, name, number, environment); \"wrong\" otherwise.\n"
            "Return ONLY a JSON object mapping id to one of same/partial/wrong.\n\n"
            + json.dumps(pairs, indent=1))
        name = os.path.basename(run)[:-6]
        c = {"same": 0, "partial": 0, "wrong": 0}
        for i in sorted(items):
            g = grades.get(i, "wrong")
            c[g] = c.get(g, 0) + 1
            if g != "same":
                detail.append(f"| {name} | {i} | {items[i]} | {interp.get(i, '')} | {refs[i]} | {g} |")
        n = len(items)
        md.append(f"| {name} | {c['same']}/{n} | {c['partial']}/{n} | {c['wrong']}/{n} |")
        print(md[-1], flush=True)
    open(outmd, "w").write("\n".join(md + detail) + "\n")
    print("\n".join(detail))


if __name__ == "__main__":
    main()
